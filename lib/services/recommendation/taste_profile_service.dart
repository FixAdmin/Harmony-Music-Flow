import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/listening_event.dart';
import '../../models/media_Item_builder.dart';
import '../../models/recommendation_item.dart';
import '../../models/taste_profile.dart';

class TasteProfileService extends GetxService {
  static const int _recentPlayFallbackLimit = 12;

  TasteProfileService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  Box get _eventsBox => Hive.box('ListeningEvents');
  Box get _profileBox => Hive.box('TasteProfile');
  Box get _cacheBox => Hive.box('RecommendationCache');

  Future<TasteProfile> buildProfile() async {
    final now = _now();
    final recentSeeds = <MediaItem>[];
    final seenSeedKeys = <String>{};
    final suppressedSeedKeys = <String>{};
    final topArtists = <String, double>{};
    final skippedArtists = <String, double>{};
    final playedSongIds = <String>{};
    final likedSongIds = <String>{};
    final playedSongKeys = <String>{};
    final likedSongKeys = <String>{};
    final skippedSongKeys = <String>{};
    final lastPlayedAtBySongKey = <String, int>{};
    final dismissedSongIds =
        Set<String>.from(_cacheBox.get('dismissedSongIds') ?? const []);
    final dismissedSongKeys =
        Set<String>.from(_cacheBox.get('dismissedSongKeys') ?? const []);

    final events = <ListeningEvent>[];
    final values = _eventsBox.values.toList().reversed.take(2000);
    for (final raw in values) {
      if (raw is! Map) continue;
      try {
        events.add(ListeningEvent.fromJson(raw));
      } catch (_) {
        continue;
      }
    }

    final latestDecisiveEventBySongKey = <String, String>{};
    for (final event in events) {
      if (!_isDecisivePositiveEvent(event.type) &&
          !_isNegativePreferenceEvent(event.type)) {
        continue;
      }
      final songKey = RecommendationMediaJson.normalizedSongKey(event.song);
      latestDecisiveEventBySongKey.putIfAbsent(songKey, () => event.type);
    }
    for (final entry in latestDecisiveEventBySongKey.entries) {
      if (_isNegativePreferenceEvent(entry.value)) {
        skippedSongKeys.add(entry.key);
        suppressedSeedKeys.add(entry.key);
      }
    }

    for (final event in events) {
      final song = event.song;
      final songKey = RecommendationMediaJson.normalizedSongKey(song);
      final artist = RecommendationMediaJson.normalizedPrimaryArtist(song);
      final positiveDecay = _decay(event.timestamp, now, halfLifeDays: 45);
      final negativeDecay = _decay(event.timestamp, now, halfLifeDays: 21);

      switch (event.type) {
        case ListeningEventType.like:
          _addScore(topArtists, artist, 4 * positiveDecay);
          break;
        case ListeningEventType.completed70:
          _addScore(topArtists, artist, 2 * positiveDecay);
          break;
        case ListeningEventType.flowMoreLikeThis:
          _addScore(topArtists, artist, 2.25 * positiveDecay);
          break;
        case ListeningEventType.recommendationClick:
          _addScore(topArtists, artist, 1.25 * positiveDecay);
          break;
        case ListeningEventType.playStart:
          _addScore(topArtists, artist, .15 * positiveDecay);
          break;
        case ListeningEventType.skipEarly:
          _addScore(skippedArtists, artist, 1.35 * negativeDecay);
          _addScore(topArtists, artist, -.7 * negativeDecay);
          break;
        case ListeningEventType.flowPlayLessLikeThis:
          _addScore(skippedArtists, artist, 1.1 * negativeDecay);
          _addScore(topArtists, artist, -1.0 * negativeDecay);
          break;
        case ListeningEventType.dismissRecommendation:
          suppressedSeedKeys.add(songKey);
          break;
        case ListeningEventType.flowBlockTrack:
        case ListeningEventType.flowBlockArtist:
          // Active blacklist entries and dismissals own suppression. Keeping
          // historical block events neutral makes unblock/undo reversible.
          break;
      }

      if (_countsAsPlayed(event.type)) {
        playedSongIds.add(song.id);
        playedSongKeys.add(songKey);
        final timestamp = event.timestamp.millisecondsSinceEpoch;
        final currentTimestamp = lastPlayedAtBySongKey[songKey] ?? 0;
        if (timestamp > currentTimestamp) {
          lastPlayedAtBySongKey[songKey] = timestamp;
        }
      }

      if (_isPositiveSeedEvent(event.type) &&
          !suppressedSeedKeys.contains(songKey) &&
          !dismissedSongIds.contains(song.id) &&
          !dismissedSongKeys.contains(songKey) &&
          seenSeedKeys.add(songKey)) {
        recentSeeds.add(song);
      }
    }

    await _addLibrarySeeds(
      recentSeeds,
      seenSeedKeys,
      suppressedSeedKeys,
      dismissedSongIds,
      dismissedSongKeys,
      'LIBFAV',
      likedSongIds,
      likedSongKeys,
      topArtists: topArtists,
    );
    if (events.isEmpty) {
      await _addLibrarySeeds(
        recentSeeds,
        seenSeedKeys,
        suppressedSeedKeys,
        dismissedSongIds,
        dismissedSongKeys,
        'LIBRP',
        playedSongIds,
        playedSongKeys,
        limit: _recentPlayFallbackLimit,
      );
    }

    topArtists.removeWhere((_, score) => score <= .05);
    skippedArtists.removeWhere((_, score) => score <= .05);

    final profile = TasteProfile(
      recentSeeds: recentSeeds.take(30).toList(),
      topArtists: topArtists,
      skippedArtists: skippedArtists,
      playedSongIds: playedSongIds,
      likedSongIds: likedSongIds,
      dismissedSongIds: dismissedSongIds,
      playedSongKeys: playedSongKeys,
      likedSongKeys: likedSongKeys,
      dismissedSongKeys: dismissedSongKeys,
      skippedSongKeys: skippedSongKeys,
      lastPlayedAtBySongKey: lastPlayedAtBySongKey,
    );
    await _profileBox.put('summary', profile.toSummaryJson());
    return profile;
  }

  Future<void> _addLibrarySeeds(
    List<MediaItem> seeds,
    Set<String> seenSeedKeys,
    Set<String> suppressedSeedKeys,
    Set<String> dismissedSongIds,
    Set<String> dismissedSongKeys,
    String boxName,
    Set<String> targetIds,
    Set<String> targetKeys, {
    Map<String, double>? topArtists,
    int limit = 60,
  }) async {
    final box = await Hive.openBox(boxName);
    for (final raw in box.values.toList().reversed.take(limit)) {
      if (raw is! Map) continue;
      try {
        final song = MediaItemBuilder.fromJson(raw);
        final songKey = RecommendationMediaJson.normalizedSongKey(song);
        targetIds.add(song.id);
        targetKeys.add(songKey);
        if (topArtists != null) {
          _addScore(
            topArtists,
            RecommendationMediaJson.normalizedPrimaryArtist(song),
            1.25,
          );
        }
        if (!suppressedSeedKeys.contains(songKey) &&
            !dismissedSongIds.contains(song.id) &&
            !dismissedSongKeys.contains(songKey) &&
            seenSeedKeys.add(songKey)) {
          seeds.add(song);
        }
      } catch (_) {}
    }
  }

  bool _countsAsPlayed(String type) {
    return type == ListeningEventType.playStart ||
        type == ListeningEventType.completed70 ||
        type == ListeningEventType.skipEarly;
  }

  bool _isPositiveSeedEvent(String type) {
    return type == ListeningEventType.playStart ||
        type == ListeningEventType.completed70 ||
        type == ListeningEventType.like ||
        type == ListeningEventType.recommendationClick ||
        type == ListeningEventType.flowMoreLikeThis;
  }

  bool _isDecisivePositiveEvent(String type) {
    return type == ListeningEventType.like ||
        type == ListeningEventType.completed70 ||
        type == ListeningEventType.flowMoreLikeThis;
  }

  bool _isNegativePreferenceEvent(String type) {
    return type == ListeningEventType.skipEarly ||
        type == ListeningEventType.flowPlayLessLikeThis;
  }

  double _decay(
    DateTime timestamp,
    DateTime now, {
    required int halfLifeDays,
  }) {
    final ageHours = math.max(0, now.difference(timestamp).inHours);
    return math.pow(.5, ageHours / (halfLifeDays * 24)).toDouble();
  }

  void _addScore(Map<String, double> target, String key, double amount) {
    if (key.isEmpty || amount == 0) return;
    target[key] = (target[key] ?? 0) + amount;
  }
}
