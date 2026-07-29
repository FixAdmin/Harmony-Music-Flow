import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/recommendation_item.dart';
import '../music_service.dart';

class LastFmProvider extends GetxService {
  final Dio _dio = Dio();
  final MusicServices _musicServices = Get.find<MusicServices>();

  String get _apiKey =>
      (Hive.box('AppPrefs').get('lastFmApiKey') ?? '').toString().trim();

  bool get isConfigured => _apiKey.isNotEmpty;

  Future<List<RecommendationCandidate>> getSimilarTracks(MediaItem seed,
      {int limit = 8}) async {
    if (!isConfigured) return [];
    final artist = (seed.artist ?? '').split(',').first.trim();
    final track = seed.title.trim();
    if (artist.isEmpty || track.isEmpty) return [];

    try {
      final response = await _dio.get(
        'https://ws.audioscrobbler.com/2.0/',
        queryParameters: {
          'method': 'track.getsimilar',
          'artist': artist,
          'track': track,
          'api_key': _apiKey,
          'format': 'json',
          'limit': limit,
          'autocorrect': 1,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final tracks = response.data?['similartracks']?['track'];
      if (tracks is! List) return [];

      final candidates = <RecommendationCandidate>[];
      for (final entry in tracks.take(limit).toList().asMap().entries) {
        final item = entry.value;
        if (item is! Map) continue;
        final trackName = item['name']?.toString().trim();
        final artistName = item['artist']?['name']?.toString().trim();
        if (trackName == null ||
            trackName.isEmpty ||
            artistName == null ||
            artistName.isEmpty) {
          continue;
        }
        final resolved = await _resolveTrack(artistName, trackName);
        if (resolved == null) continue;
        candidates.add(RecommendationCandidate(
          item: resolved,
          source: 'lastfm',
          seedId: seed.id,
          sourceScore: double.tryParse(item['match']?.toString() ?? '') ?? .7,
          sourceRank: entry.key,
        ));
      }
      return candidates;
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> getTopTags(MediaItem seed, {int limit = 8}) async {
    if (!isConfigured) return [];
    final artist = (seed.artist ?? '').split(',').first.trim();
    final track = seed.title.trim();
    if (artist.isEmpty && track.isEmpty) return [];

    final tags = <String>{};
    if (artist.isNotEmpty && track.isNotEmpty) {
      tags.addAll(await _fetchTags({
        'method': 'track.getTopTags',
        'artist': artist,
        'track': track,
        'autocorrect': 1,
      }, limit: limit));
    }
    if (tags.length < 3 && artist.isNotEmpty) {
      tags.addAll(await _fetchTags({
        'method': 'artist.getTopTags',
        'artist': artist,
        'autocorrect': 1,
      }, limit: limit));
    }
    return tags.take(limit).toList();
  }

  Future<List<String>> _fetchTags(
    Map<String, dynamic> query, {
    int limit = 8,
  }) async {
    try {
      final response = await _dio.get(
        'https://ws.audioscrobbler.com/2.0/',
        queryParameters: {
          ...query,
          'api_key': _apiKey,
          'format': 'json',
        },
        options: Options(
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      final raw = response.data?['toptags']?['tag'];
      final items = raw is List
          ? raw
          : raw is Map
              ? [raw]
              : const [];
      return items
          .whereType<Map>()
          .map((item) => item['name']?.toString().trim() ?? '')
          .where((tag) => tag.isNotEmpty)
          .take(limit)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<MediaItem?> _resolveTrack(String artist, String title) async {
    try {
      final results = await _musicServices.search('$artist $title',
          filter: 'songs', limit: 5);
      MediaItem? best;
      var bestScore = 0.0;
      for (final value in results.values) {
        if (value is! List) continue;
        for (final item in value) {
          if (item is! MediaItem) continue;
          final artistScore = RecommendationMediaJson.textSimilarity(
            RecommendationMediaJson.normalizedArtist(item.artist ?? ''),
            artist,
          );
          final titleScore =
              RecommendationMediaJson.textSimilarity(item.title, title);
          if (artistScore < .5 || titleScore < .68) continue;
          final score = (artistScore * .4) + (titleScore * .6);
          if (score > bestScore) {
            best = item;
            bestScore = score;
          }
        }
      }
      return best;
    } catch (_) {}
    return null;
  }
}
