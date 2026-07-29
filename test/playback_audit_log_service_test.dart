import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/playback_audit_log_service.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late PlaybackAuditLogService service;

  MediaItem song(String id) {
    return MediaItem(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      artUri: Uri.parse('https://example.com/$id.jpg'),
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('playback_audit_log_test');
    Hive.init(tempDir.path);
    await Hive.openBox('PlaybackAuditLog');
    await Hive.openBox('SongDownloads');
    await Hive.openBox('SongsCache');
    await Hive.openBox('LIBFAV');
    await Hive.openBox('LibraryPlaylists');
    service = PlaybackAuditLogService();
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('records library flags and external status', () async {
    final favoriteSong = song('favorite');
    await Hive.box('LIBFAV').put(
      favoriteSong.id,
      {'videoId': favoriteSong.id},
    );
    final playlist = Playlist(
      title: 'Local',
      playlistId: 'local_playlist',
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    );
    await Hive.box('LibraryPlaylists').add(playlist.toJson());
    final playlistBox = await Hive.openBox('local_playlist');
    await playlistBox.add({'videoId': 'playlist'});

    await service.record(favoriteSong, source: 'flow');
    await service.record(song('playlist'), source: 'flow');
    await service.record(song('external'), source: 'flow');

    final entries = service.recentEntries();
    expect(entries[2].isFavorite, isTrue);
    expect(entries[2].inLibrary, isTrue);
    expect(entries[1].inPlaylist, isTrue);
    expect(entries[1].inLibrary, isTrue);
    expect(entries.first.inLibrary, isFalse);
  });

  test('cached-only songs remain external library items', () async {
    final cachedSong = song('cached');
    await Hive.box('SongsCache').put(cachedSong.id, {'cached': true});

    await service.record(cachedSong, source: 'manual');

    final entry = service.recentEntries().single;
    expect(entry.isCached, isTrue);
    expect(entry.inLibrary, isFalse);
  });

  test('ignores malformed audit and playlist rows', () async {
    await Hive.box('PlaybackAuditLog').add({'broken': true});
    await Hive.box('LibraryPlaylists').add({'broken': true});

    await service.record(song('valid'), source: 'manual');

    final entries = service.recentEntries();
    expect(entries, hasLength(1));
    expect(entries.single.song.id, 'valid');
  });

  test('keeps only last 500 entries', () async {
    for (var i = 0; i < 505; i++) {
      await service.record(song('$i'), source: 'flow');
    }

    final entries = service.recentEntries();
    expect(entries.length, 500);
    expect(entries.first.song.id, '504');
    expect(entries.last.song.id, '5');
  });

  test('persists Flow source score and reason codes', () async {
    final item = song('decision').copyWith(extras: {
      'flowSource': 'station_search',
      'flowScore': 2.4,
      'flowReasonCodes': ['station_match', 'new_track'],
    });

    await service.record(item, source: 'flow: Energy');

    final entry = service.recentEntries().single;
    expect(entry.recommendationSource, 'station_search');
    expect(entry.recommendationScore, 2.4);
    expect(entry.reasonCodes, contains('station_match'));
  });

  test('persists generic recommendation metadata', () async {
    final item = song('for-you').copyWith(extras: {
      'recommendationSource': 'lastfm',
      'recommendationScore': .92,
      'recommendationReasonCodes': ['similar_artist'],
    });

    await service.record(item, source: 'for_you');

    final entry = service.recentEntries().single;
    expect(entry.recommendationSource, 'lastfm');
    expect(entry.recommendationScore, .92);
    expect(entry.reasonCodes, ['similar_artist']);
  });
}
