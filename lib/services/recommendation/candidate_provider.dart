import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/recommendation_item.dart';
import '../../models/taste_profile.dart';
import '../music_service.dart';
import 'candidate_pool.dart';
import 'lastfm_provider.dart';
import 'provider_request.dart';

class CandidateProvider extends GetxService {
  static const _requestTimeout = Duration(seconds: 6);

  final MusicServices _musicServices = Get.find<MusicServices>();
  final LastFmProvider _lastFmProvider = Get.find<LastFmProvider>();

  Future<List<RecommendationCandidate>> getCandidates(TasteProfile profile,
      {int limit = 60}) async {
    if (!profile.hasSignals) return [];

    final seeds = _uniqueSeeds(profile.recentSeeds).take(5).toList();
    final radioQuota = (limit * .62).round();
    final relatedQuota = (limit * .28).round();
    final lastFmQuota = limit - radioQuota - relatedQuota;
    final lastFmSeedCount = seeds.take(3).length;
    final lastFmPerSeed = lastFmSeedCount == 0
        ? 0
        : (lastFmQuota / lastFmSeedCount).ceil().clamp(2, 4).toInt();

    final radioFuture = Future.wait(
      seeds.map((seed) => _getYouTubeRadio(seed, limit: 10)),
    );
    final relatedFuture = Future.wait(
      seeds.map((seed) => _getYouTubeRelated(seed, limit: 10)),
    );
    final lastFmFuture = _lastFmProvider.isConfigured
        ? Future.wait(
            seeds.take(3).map(
                  (seed) => getLastFmCandidates(
                    seed,
                    limit: lastFmPerSeed,
                  ),
                ),
          )
        : Future.value(<List<RecommendationCandidate>>[]);

    final radio = CandidatePool.roundRobin(
      await radioFuture,
      limit: radioQuota,
    );
    final related = CandidatePool.roundRobin(
      await relatedFuture,
      limit: relatedQuota,
      rotation: 1,
    );
    final lastFm = CandidatePool.roundRobin(
      await lastFmFuture,
      limit: lastFmQuota,
      rotation: 2,
    );

    return CandidatePool.mergeBuckets([
      CandidateBucket(items: radio, quota: radioQuota),
      CandidateBucket(items: related, quota: relatedQuota),
      CandidateBucket(items: lastFm, quota: lastFmQuota),
    ], limit: limit);
  }

  Future<List<RecommendationCandidate>> getYouTubeRadioCandidates(
      MediaItem seed,
      {int limit = 14}) {
    return _getYouTubeRadio(seed, limit: limit);
  }

  Future<List<RecommendationCandidate>> getYouTubeRelatedCandidates(
    MediaItem seed, {
    int limit = 14,
  }) {
    return _getYouTubeRelated(seed, limit: limit);
  }

  Future<List<RecommendationCandidate>> getLastFmCandidates(MediaItem seed,
      {int limit = 8}) async {
    if (!_lastFmProvider.isConfigured) return Future.value([]);
    return ProviderRequest.resolve(
      _lastFmProvider.getSimilarTracks(seed, limit: limit),
      timeout: _requestTimeout,
      fallback: const <RecommendationCandidate>[],
    );
  }

  Future<List<RecommendationCandidate>> getSearchCandidates(
    String query, {
    int limit = 12,
    String source = 'station_search',
    String? seedId,
    double sourceScore = .64,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return [];
    try {
      final result = await ProviderRequest.resolve<dynamic>(
        _musicServices.search(
          normalizedQuery,
          filter: 'songs',
          limit: limit,
          ignoreSpelling: true,
        ),
        timeout: _requestTimeout,
        fallback: const <String, dynamic>{},
      );
      final tracks = <MediaItem>[];
      for (final value in result.values) {
        if (value is List) {
          tracks.addAll(value.whereType<MediaItem>());
        }
      }
      return tracks
          .where((track) => track.id.trim().isNotEmpty)
          .toList()
          .asMap()
          .entries
          .map((entry) => RecommendationCandidate(
                item: entry.value,
                source: source,
                seedId: seedId,
                sourceScore: sourceScore,
                sourceRank: entry.key,
              ))
          .take(limit)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<RecommendationCandidate>> _getYouTubeRadio(MediaItem seed,
      {int limit = 14}) async {
    try {
      final result = await ProviderRequest.resolve<dynamic>(
        _musicServices.getWatchPlaylist(
          videoId: seed.id,
          radio: true,
          limit: limit,
        ),
        timeout: _requestTimeout,
        fallback: const <String, dynamic>{},
      );
      final tracks = List<MediaItem>.from(result['tracks'] ?? const []);
      return tracks
          .where((track) => !RecommendationMediaJson.sameSong(track, seed))
          .toList()
          .asMap()
          .entries
          .map((entry) => RecommendationCandidate(
                item: entry.value,
                source: 'youtube_radio',
                seedId: seed.id,
                sourceScore: .9,
                sourceRank: entry.key,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<RecommendationCandidate>> _getYouTubeRelated(MediaItem seed,
      {int limit = 14}) async {
    try {
      final lang = Hive.box('AppPrefs').get('currentAppLanguageCode') ?? 'en';
      final related = await ProviderRequest.resolve<dynamic>(
        _musicServices.getContentRelatedToSong(seed.id, lang),
        timeout: _requestTimeout,
        fallback: const <dynamic>[],
      );
      if (related is! List) return [];

      final tracks = <MediaItem>[];
      for (final section in related) {
        if (section is! Map) continue;
        final contents = section['contents'];
        if (contents is! List) continue;
        tracks.addAll(contents.whereType<MediaItem>());
      }
      return tracks
          .where((track) => !RecommendationMediaJson.sameSong(track, seed))
          .toList()
          .asMap()
          .entries
          .map((entry) => RecommendationCandidate(
                item: entry.value,
                source: 'youtube_related',
                seedId: seed.id,
                sourceScore: .8,
                sourceRank: entry.key,
              ))
          .take(limit)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Iterable<MediaItem> _uniqueSeeds(Iterable<MediaItem> seeds) sync* {
    final seen = <String>{};
    for (final seed in seeds) {
      final key = RecommendationMediaJson.normalizedSongKey(seed);
      if (seed.id.trim().isEmpty || !seen.add(key)) continue;
      yield seed;
    }
  }
}
