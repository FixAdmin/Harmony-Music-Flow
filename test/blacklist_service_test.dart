import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/flow/blacklist_entry.dart';
import 'package:harmonymusic/models/recommendation_item.dart';
import 'package:harmonymusic/services/library/blacklist_service.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;

  MediaItem song(String id, String title, String artist) {
    return MediaItem(id: id, title: title, artist: artist);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('blacklist_test');
    Hive.init(tempDir.path);
    await Hive.openBox('TrackBlacklist');
    await Hive.openBox('ArtistBlacklist');
    await Hive.openBox('RecommendationCache');
    await Hive.openBox('RecommendationSettings');
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('blocks tracks by normalized artist and title', () async {
    final service = BlacklistService();
    await service.blockTrack(song('a', 'Song (Official Video)', 'Artist'));

    expect(service.isBlocked(song('b', 'Song', 'Artist')), isTrue);
  });

  test('blocks and unblocks artists by normalized key', () async {
    final service = BlacklistService();
    await service.blockArtist('Known Artist');

    expect(service.isBlocked(song('a', 'Any Song', 'Known Artist')), isTrue);

    await service.unblockArtist('Known Artist');
    expect(service.isBlocked(song('a', 'Any Song', 'Known Artist')), isFalse);
  });

  test('uses shared artist normalization for feat and ampersand credits',
      () async {
    final service = BlacklistService();
    await service.blockArtist('Known Artist feat. Guest');

    expect(
      service.artistKey('Known Artist feat. Guest'),
      RecommendationMediaJson.normalizedArtist('Known Artist feat. Guest'),
    );
    expect(service.isArtistBlocked('Known Artist & Another Guest'), isTrue);
  });

  test('recognizes and unblocks legacy ampersand artist keys', () async {
    final service = BlacklistService();
    const artist = 'Known Artist & Guest';
    final legacyKey = RecommendationMediaJson.normalizedText(artist);
    await Hive.box('ArtistBlacklist').put(
      legacyKey,
      BlacklistEntry(
        key: legacyKey,
        type: 'artist',
        label: artist,
        createdAt: DateTime.now(),
      ).toJson(),
    );

    expect(service.isArtistBlocked(artist), isTrue);

    await service.unblockArtist(artist);
    expect(service.isArtistBlocked(artist), isFalse);
  });

  test('unblocking a track also removes its recommendation dismissal',
      () async {
    final service = BlacklistService();
    final item = song('a', 'Signal', 'Nova');
    await service.blockTrack(item);
    final key = service.trackKey(item);

    await service.unblockTrack(key);

    expect(service.isBlocked(item), isFalse);
    expect(
      Hive.box('RecommendationCache').get('dismissedSongIds'),
      isNot(contains('a')),
    );
    expect(
      Hive.box('RecommendationCache').get('dismissedSongKeys'),
      isNot(contains(key)),
    );
  });

  test('unblocking preserves an independent pre-existing dismissal', () async {
    final service = BlacklistService();
    final item = song('shared', 'Signal', 'Nova');
    final key = service.trackKey(item);
    await Hive.box('RecommendationCache').putAll({
      'dismissedSongIds': [item.id],
      'dismissedSongKeys': [key],
    });

    await service.blockTrack(item);
    await service.unblockTrack(key);

    expect(
      Hive.box('RecommendationCache').get('dismissedSongIds'),
      contains(item.id),
    );
    expect(
      Hive.box('RecommendationCache').get('dismissedSongKeys'),
      contains(key),
    );
  });

  test('repeated blacklist blocks retain dismissal ownership', () async {
    final service = BlacklistService();
    final item = song('owned', 'Owned Signal', 'Nova');
    final key = service.trackKey(item);

    await service.blockTrack(item);
    await service.blockTrack(item);
    await service.unblockTrack(key);

    expect(
      Hive.box('RecommendationCache').get('dismissedSongIds'),
      isNot(contains(item.id)),
    );
    expect(
      Hive.box('RecommendationCache').get('dismissedSongKeys'),
      isNot(contains(key)),
    );
  });

  test('legacy blocks preserve dismissals with unknown ownership', () async {
    final service = BlacklistService();
    final item = song('legacy', 'Legacy Signal', 'Nova');
    final key = service.trackKey(item);
    await Hive.box('RecommendationCache').putAll({
      'dismissedSongIds': [item.id],
      'dismissedSongKeys': [key],
    });
    await Hive.box('TrackBlacklist').put(
      key,
      BlacklistEntry(
        key: key,
        type: 'track',
        label: 'Nova - Legacy Signal',
        createdAt: DateTime.now(),
        sourceSongId: item.id,
      ).toJson(),
    );

    await service.unblockTrack(key);

    expect(
      Hive.box('RecommendationCache').get('dismissedSongIds'),
      contains(item.id),
    );
    expect(
      Hive.box('RecommendationCache').get('dismissedSongKeys'),
      contains(key),
    );
  });
}
