import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../models/playback_audit_entry.dart';
import '../models/playlist.dart';

class PlaybackAuditLogService extends GetxService {
  static const int maxEntries = 500;

  Box get _box => Hive.box('PlaybackAuditLog');

  Future<void> record(MediaItem song, {required String source}) async {
    final favorite = await _containsSong('LIBFAV', song.id);
    final downloaded = Hive.box('SongDownloads').containsKey(song.id);
    final cached = Hive.box('SongsCache').containsKey(song.id);
    final playlist = await _isInLocalPlaylist(song.id);
    final recommendationSource =
        song.extras?['flowSource'] ?? song.extras?['recommendationSource'];
    final recommendationReasons = song.extras?['flowReasonCodes'] ??
        song.extras?['recommendationReasonCodes'];
    final recommendationScore =
        song.extras?['flowScore'] ?? song.extras?['recommendationScore'];
    final entry = PlaybackAuditEntry(
      song: song,
      playedAt: DateTime.now(),
      source: source,
      inLibrary: favorite || downloaded || playlist,
      isFavorite: favorite,
      isDownloaded: downloaded,
      isCached: cached,
      inPlaylist: playlist,
      recommendationSource:
          recommendationSource is String ? recommendationSource : null,
      reasonCodes: recommendationReasons is List
          ? recommendationReasons.map((reason) => reason.toString()).toList()
          : const [],
      recommendationScore:
          recommendationScore is num ? recommendationScore.toDouble() : null,
    );

    await _box.add(entry.toJson());
    await _trim();
  }

  List<PlaybackAuditEntry> recentEntries() {
    final entries = <PlaybackAuditEntry>[];
    for (final raw in _box.values.whereType<Map>()) {
      try {
        entries.add(PlaybackAuditEntry.fromJson(raw));
      } catch (_) {}
    }
    return entries.reversed.toList();
  }

  Future<void> clear() async {
    await _box.clear();
  }

  Future<bool> _containsSong(String boxName, String songId) async {
    final box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await Hive.openBox(boxName);
    return box.containsKey(songId) ||
        box.values.whereType<Map>().any((item) => item['videoId'] == songId);
  }

  Future<bool> _isInLocalPlaylist(String songId) async {
    final playlistsBox = Hive.isBoxOpen('LibraryPlaylists')
        ? Hive.box('LibraryPlaylists')
        : await Hive.openBox('LibraryPlaylists');
    for (final raw in playlistsBox.values.whereType<Map>()) {
      try {
        final playlist = Playlist.fromJson(raw);
        if (playlist.isCloudPlaylist || playlist.isPipedPlaylist) continue;
        if (await _containsSong(playlist.playlistId, songId)) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Future<void> _trim() async {
    final overflow = _box.length - maxEntries;
    if (overflow <= 0) return;
    for (var i = 0; i < overflow; i++) {
      await _box.deleteAt(0);
    }
  }
}
