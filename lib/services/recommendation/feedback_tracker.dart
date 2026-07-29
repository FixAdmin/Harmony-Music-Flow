import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/listening_event.dart';
import '../../models/recommendation_item.dart';

class FeedbackTracker extends GetxService {
  static const int maxEvents = 10000;
  static const int _maxDedupeEntries = 500;
  static const String dedupeStateKey = 'feedbackDedupeV2';
  static const String lastMeaningfulFeedbackAtKey = 'lastMeaningfulFeedbackAt';
  static const String feedbackRevisionKey = 'feedbackRevision';

  FeedbackTracker({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  Box get _eventsBox => Hive.box('ListeningEvents');
  Box get _prefsBox => Hive.box('AppPrefs');
  Box get _settingsBox => Hive.box('RecommendationSettings');

  bool get isEnabled =>
      (_prefsBox.get('recommendationsEnabled') ?? true) ||
      (_prefsBox.get('flowEnabled') ?? true);

  int get feedbackRevision {
    final value = _settingsBox.get(feedbackRevisionKey);
    return value is int && value >= 0 ? value : 0;
  }

  Future<void> recordPlayStart(
    MediaItem song, {
    String? source,
    String? sessionId,
  }) {
    return record(
      ListeningEventType.playStart,
      song,
      source: source,
      sessionId: sessionId,
      duplicateWindow: const Duration(minutes: 2),
      meaningful: false,
    );
  }

  Future<void> recordCompleted70(MediaItem song,
      {int? positionSeconds,
      int? durationSeconds,
      String? source,
      String? sessionId}) {
    return record(
      ListeningEventType.completed70,
      song,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      source: source,
      sessionId: sessionId,
      duplicateWindow: const Duration(minutes: 15),
    );
  }

  Future<void> recordSkipEarly(MediaItem song,
      {int? positionSeconds,
      int? durationSeconds,
      String? source,
      String? sessionId}) {
    return record(
      ListeningEventType.skipEarly,
      song,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      source: source,
      sessionId: sessionId,
      duplicateWindow: const Duration(minutes: 10),
    );
  }

  Future<void> recordLike(MediaItem song, {String? source, String? sessionId}) {
    return record(
      ListeningEventType.like,
      song,
      source: source,
      sessionId: sessionId,
      duplicateWindow: const Duration(hours: 12),
    );
  }

  Future<void> recordRecommendationClick(MediaItem song) {
    return record(
      ListeningEventType.recommendationClick,
      song,
      source: 'for_you',
      duplicateWindow: const Duration(minutes: 5),
    );
  }

  Future<void> recordDismissRecommendation(MediaItem song) {
    return record(
      ListeningEventType.dismissRecommendation,
      song,
      source: 'for_you',
      duplicateWindow: const Duration(hours: 12),
    );
  }

  Future<void> recordFlowMoreLikeThis(MediaItem song, {String? sessionId}) {
    return record(
      ListeningEventType.flowMoreLikeThis,
      song,
      source: 'flow',
      sessionId: sessionId,
      duplicateWindow: const Duration(minutes: 5),
    );
  }

  Future<void> recordFlowPlayLessLikeThis(MediaItem song, {String? sessionId}) {
    return record(
      ListeningEventType.flowPlayLessLikeThis,
      song,
      source: 'flow',
      sessionId: sessionId,
      duplicateWindow: const Duration(minutes: 10),
    );
  }

  Future<void> recordFlowBlockTrack(MediaItem song, {String? sessionId}) {
    return record(
      ListeningEventType.flowBlockTrack,
      song,
      source: 'flow',
      sessionId: sessionId,
      duplicateWindow: const Duration(hours: 12),
    );
  }

  Future<void> recordFlowBlockArtist(MediaItem song, {String? sessionId}) {
    return record(
      ListeningEventType.flowBlockArtist,
      song,
      source: 'flow',
      sessionId: sessionId,
      duplicateWindow: const Duration(hours: 12),
    );
  }

  Future<void> record(
    String type,
    MediaItem song, {
    int? positionSeconds,
    int? durationSeconds,
    String? source,
    String? sessionId,
    Duration duplicateWindow = const Duration(minutes: 1),
    bool meaningful = true,
  }) async {
    if (!isEnabled) return;
    final now = _now();
    final songKey = RecommendationMediaJson.normalizedSongKey(song);
    final dedupeKey = '$type:${songKey.isEmpty ? song.id : songKey}';
    final dedupe = _readDedupeState();
    final lastTimestamp = dedupe[dedupeKey];
    if (lastTimestamp != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastTimestamp)) <
            duplicateWindow) {
      return;
    }

    dedupe[dedupeKey] = now.millisecondsSinceEpoch;
    if (meaningful) {
      await markMeaningfulChange(at: now);
    }
    final event = ListeningEvent(
      type: type,
      song: song,
      timestamp: now,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      source: source,
      sessionId: sessionId,
    );
    await _eventsBox.add(event.toJson());
    await _settingsBox.put(dedupeStateKey, _trimDedupeState(dedupe, now));
    await _trimEvents();
  }

  Future<void> clearHistory() async {
    await _eventsBox.clear();
    await _settingsBox.delete(dedupeStateKey);
    await _settingsBox.delete(lastMeaningfulFeedbackAtKey);
    await _advanceFeedbackRevision();
  }

  Future<void> markMeaningfulChange({DateTime? at}) async {
    await _advanceFeedbackRevision();
    await _settingsBox.put(
      lastMeaningfulFeedbackAtKey,
      (at ?? _now()).millisecondsSinceEpoch,
    );
  }

  Future<void> _advanceFeedbackRevision() {
    return _settingsBox.put(feedbackRevisionKey, feedbackRevision + 1);
  }

  Map<String, int> _readDedupeState() {
    final raw = _settingsBox.get(dedupeStateKey);
    if (raw is! Map) return {};
    return {
      for (final entry in raw.entries)
        if (entry.value is int) entry.key.toString(): entry.value as int,
    };
  }

  Map<String, int> _trimDedupeState(Map<String, int> values, DateTime now) {
    final oldestAllowed =
        now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    final entries = values.entries
        .where((entry) => entry.value >= oldestAllowed)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map<String, int>.fromEntries(entries.take(_maxDedupeEntries));
  }

  Future<void> _trimEvents() async {
    final overflow = _eventsBox.length - maxEvents;
    if (overflow <= 0) return;
    for (var i = 0; i < overflow; i++) {
      await _eventsBox.deleteAt(0);
    }
  }
}
