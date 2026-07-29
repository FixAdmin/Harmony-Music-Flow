import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/library/blacklist_service.dart';
import 'package:harmonymusic/services/library/library_automation_service.dart';
import 'package:harmonymusic/services/recommendation/feedback_tracker.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;

  MediaItem song(String id, String title, String artist) {
    return MediaItem(
      id: id,
      title: title,
      artist: artist,
      artUri: Uri.parse('https://example.com/$id.jpg'),
      extras: {
        'artists': [
          {'name': artist}
        ],
      },
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library_auto_test');
    Hive.init(tempDir.path);
    await Hive.openBox('AppPrefs');
    await Hive.openBox('LIBFAV');
    await Hive.openBox('ListeningEvents');
    await Hive.openBox('RecommendationSettings');
    await Hive.openBox('TrackBlacklist');
    await Hive.openBox('ArtistBlacklist');
    await Hive.openBox('SongDownloads');
    Hive.box('AppPrefs').put('recommendationsEnabled', true);
    Hive.box('AppPrefs').put('autoDownloadFavoriteSongEnabled', false);
    Get.put(BlacklistService());
    Get.put(FeedbackTracker());
  });

  tearDown(() async {
    Get.reset();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('likeTrack adds a favorite without duplicates', () async {
    final service = LibraryAutomationService();
    final item = song('a', 'Track', 'Artist');

    await service.likeTrack(item);
    await service.likeTrack(item);

    expect(Hive.box('LIBFAV').containsKey('a'), isTrue);
    expect(Hive.box('LIBFAV').length, 1);
  });

  test('likeTrack refuses a blacklisted track', () async {
    final blocked = song('blocked', 'Blocked', 'Artist');
    await Get.find<BlacklistService>().blockTrack(blocked);
    final service = LibraryAutomationService();

    final result = await service.likeTrack(blocked);

    expect(result.success, isFalse);
    expect(result.conflict, isTrue);
    expect(Hive.box('LIBFAV').containsKey('blocked'), isFalse);
  });

  test('likeTrack can add to configured local playlist', () async {
    await Hive.openBox('FlowLiked');
    Hive.box('AppPrefs').put('flowLikedPlaylistId', 'FlowLiked');
    final service = LibraryAutomationService();

    await service.likeTrack(song('a', 'Track', 'Artist'));
    await service.likeTrack(song('a', 'Track', 'Artist'));

    expect(Hive.box('FlowLiked').length, 1);
  });
}
