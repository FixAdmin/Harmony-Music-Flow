import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/recommendation/feedback_tracker.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  var now = DateTime.utc(2026, 7, 14, 12);

  MediaItem song(String id) {
    return MediaItem(id: id, title: 'Signal', artist: 'Nova');
  }

  setUp(() async {
    now = DateTime.utc(2026, 7, 14, 12);
    tempDir = await Directory.systemTemp.createTemp('feedback_tracker_test');
    Hive.init(tempDir.path);
    await Hive.openBox('AppPrefs');
    await Hive.openBox('ListeningEvents');
    await Hive.openBox('RecommendationSettings');
    await Hive.box('AppPrefs').put('recommendationsEnabled', true);
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('dedupe survives service recreation and alternate upload ids', () async {
    await FeedbackTracker(now: () => now).recordPlayStart(song('video-a'));
    now = now.add(const Duration(minutes: 1));
    await FeedbackTracker(now: () => now).recordPlayStart(song('video-b'));

    expect(Hive.box('ListeningEvents').length, 1);

    now = now.add(const Duration(minutes: 2));
    await FeedbackTracker(now: () => now).recordPlayStart(song('video-b'));
    expect(Hive.box('ListeningEvents').length, 2);
  });

  test('only meaningful feedback invalidates recommendation cache', () async {
    final tracker = FeedbackTracker(now: () => now);
    await tracker.recordPlayStart(song('video-a'));
    expect(
      Hive.box('RecommendationSettings')
          .containsKey(FeedbackTracker.lastMeaningfulFeedbackAtKey),
      isFalse,
    );

    now = now.add(const Duration(seconds: 10));
    await tracker.recordSkipEarly(song('video-a'));
    expect(
      Hive.box('RecommendationSettings')
          .get(FeedbackTracker.lastMeaningfulFeedbackAtKey),
      now.millisecondsSinceEpoch,
    );
  });

  test('records feedback when only Flow is enabled', () async {
    await Hive.box('AppPrefs').put('recommendationsEnabled', false);
    await Hive.box('AppPrefs').put('flowEnabled', true);

    await FeedbackTracker(now: () => now).recordLike(song('flow-only'));

    expect(Hive.box('ListeningEvents'), hasLength(1));
  });

  test('does not record feedback when recommendations and Flow are disabled',
      () async {
    await Hive.box('AppPrefs').put('recommendationsEnabled', false);
    await Hive.box('AppPrefs').put('flowEnabled', false);

    await FeedbackTracker(now: () => now).recordLike(song('disabled'));

    expect(Hive.box('ListeningEvents'), isEmpty);
  });

  test('meaningful feedback revision is monotonic', () async {
    final tracker = FeedbackTracker(now: () => now);

    await tracker.recordLike(song('first'));
    final firstRevision = tracker.feedbackRevision;
    now = now.add(const Duration(seconds: 1));
    await tracker.recordSkipEarly(song('second'));

    expect(firstRevision, greaterThan(0));
    expect(tracker.feedbackRevision, greaterThan(firstRevision));
  });
}
