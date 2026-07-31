import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/listening_event.dart';
import 'package:harmonymusic/models/recommendation_item.dart';
import 'package:harmonymusic/services/recommendation/taste_profile_service.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  final now = DateTime.utc(2026, 7, 14, 12);

  MediaItem song(String id, String title, String artist) {
    return MediaItem(id: id, title: title, artist: artist);
  }

  Future<void> addEvent(
    String type,
    MediaItem item,
    DateTime timestamp,
  ) {
    return Hive.box('ListeningEvents').add(
      ListeningEvent(type: type, song: item, timestamp: timestamp).toJson(),
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('taste_profile_test');
    Hive.init(tempDir.path);
    await Hive.openBox('ListeningEvents');
    await Hive.openBox('TasteProfile');
    await Hive.openBox('RecommendationCache');
    await Hive.openBox('LIBFAV');
    await Hive.openBox('LIBRP');
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('an early skip suppresses the earlier play-start seed', () async {
    final item = song('a', 'Signal', 'Nova, Guest');
    await addEvent(
      ListeningEventType.playStart,
      item,
      now.subtract(const Duration(minutes: 2)),
    );
    await addEvent(
      ListeningEventType.skipEarly,
      item,
      now.subtract(const Duration(minutes: 1)),
    );

    final profile = await TasteProfileService(now: () => now).buildProfile();

    expect(profile.recentSeeds, isEmpty);
    expect(profile.skippedArtists['nova'], greaterThan(1));
    expect(profile.wasSkipped(item), isTrue);
  });

  test('recent positive feedback outweighs old history', () async {
    await addEvent(
      ListeningEventType.completed70,
      song('old', 'Old Track', 'Old Artist'),
      now.subtract(const Duration(days: 90)),
    );
    await addEvent(
      ListeningEventType.completed70,
      song('new', 'New Track', 'Recent Artist'),
      now.subtract(const Duration(days: 1)),
    );

    final profile = await TasteProfileService(now: () => now).buildProfile();

    expect(
      profile.topArtists['recent artist']!,
      greaterThan(profile.topArtists['old artist']!),
    );
  });

  test('current favorites are authoritative after unlike', () async {
    final item = song('liked', 'Liked Track', 'Nova');
    await addEvent(ListeningEventType.like, item, now);
    final service = TasteProfileService(now: () => now);

    expect((await service.buildProfile()).isLiked(item), isFalse);

    await Hive.box('LIBFAV')
        .put(item.id, RecommendationMediaJson.fromMediaItem(item));
    expect((await service.buildProfile()).isLiked(item), isTrue);
  });

  test('LIBRP is not treated as verified playback after valid events',
      () async {
    final attempted = song('attempted', 'Attempted Track', 'Attempted Artist');
    await Hive.box('LIBRP').put(
      attempted.id,
      RecommendationMediaJson.fromMediaItem(attempted),
    );
    await addEvent(
      ListeningEventType.completed70,
      song('verified', 'Verified Track', 'Verified Artist'),
      now,
    );

    final profile = await TasteProfileService(now: () => now).buildProfile();

    expect(profile.hasPlayed(attempted), isFalse);
    expect(
      profile.recentSeeds.map((item) => item.id),
      isNot(contains(attempted.id)),
    );
  });

  test('LIBRP cold-start fallback is bounded', () async {
    for (var index = 0; index < 20; index++) {
      final item = song('$index', 'Track $index', 'Artist $index');
      await Hive.box('LIBRP').put(
        item.id,
        RecommendationMediaJson.fromMediaItem(item),
      );
    }

    final profile = await TasteProfileService(now: () => now).buildProfile();

    expect(profile.playedSongIds, hasLength(12));
    expect(profile.recentSeeds, hasLength(12));
  });

  test('later decisive positive feedback recovers an older skip', () async {
    final item = song('recovered', 'Recovered Track', 'Nova');
    await addEvent(
      ListeningEventType.skipEarly,
      item,
      now.subtract(const Duration(minutes: 2)),
    );
    await addEvent(
      ListeningEventType.completed70,
      item,
      now.subtract(const Duration(minutes: 1)),
    );

    final profile = await TasteProfileService(now: () => now).buildProfile();

    expect(profile.wasSkipped(item), isFalse);
    expect(profile.recentSeeds.map((seed) => seed.id), contains(item.id));
  });

  test('a historical Flow block does not survive an explicit unblock',
      () async {
    final item = song('restored', 'Restored Track', 'Nova');
    await addEvent(
      ListeningEventType.completed70,
      item,
      now.subtract(const Duration(minutes: 2)),
    );
    await addEvent(
      ListeningEventType.flowBlockTrack,
      item,
      now.subtract(const Duration(minutes: 1)),
    );

    final profile = await TasteProfileService(now: () => now).buildProfile();

    expect(profile.recentSeeds.map((seed) => seed.id), contains(item.id));
  });
}
