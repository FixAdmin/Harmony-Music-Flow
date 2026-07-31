import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/media_Item_builder.dart';
import '../downloader.dart';
import '../recommendation/feedback_tracker.dart';
import 'blacklist_service.dart';

class LibraryAutomationResult {
  const LibraryAutomationResult({
    required this.success,
    this.conflict = false,
    this.message,
  });

  final bool success;
  final bool conflict;
  final String? message;
}

class LibraryAutomationService extends GetxService {
  final BlacklistService _blacklistService = Get.find<BlacklistService>();
  final FeedbackTracker _feedbackTracker = Get.find<FeedbackTracker>();

  Box get _prefsBox => Hive.box('AppPrefs');
  Box get _downloadsBox => Hive.box('SongDownloads');

  Future<LibraryAutomationResult> likeTrack(MediaItem song,
      {String source = 'manual'}) async {
    if (_blacklistService.isBlocked(song)) {
      return const LibraryAutomationResult(
        success: false,
        conflict: true,
        message: 'blocked',
      );
    }

    final favBox = await Hive.openBox('LIBFAV');
    await favBox.put(song.id, MediaItemBuilder.toJson(song));
    await _feedbackTracker.recordLike(song, source: source);

    final likedPlaylistId = _prefsBox.get('flowLikedPlaylistId') as String?;
    if (likedPlaylistId != null && likedPlaylistId.trim().isNotEmpty) {
      await _addToPlaylistIfAbsent(song, likedPlaylistId);
    }

    final autoDownload =
        _prefsBox.get('autoDownloadFavoriteSongEnabled') ?? false;
    if (autoDownload == true && !_downloadsBox.containsKey(song.id)) {
      unawaited(Get.find<Downloader>().download(song));
    }

    return const LibraryAutomationResult(success: true);
  }

  Future<void> unlikeTrack(MediaItem song) async {
    final favBox = await Hive.openBox('LIBFAV');
    await favBox.delete(song.id);
    final likedPlaylistId = _prefsBox.get('flowLikedPlaylistId') as String?;
    if (likedPlaylistId != null && likedPlaylistId.trim().isNotEmpty) {
      await _removeFromPlaylist(song, likedPlaylistId);
    }
    await _feedbackTracker.markMeaningfulChange();
  }

  Future<void> _addToPlaylistIfAbsent(MediaItem song, String playlistId) async {
    final playlistBox = await Hive.openBox(playlistId);
    final exists = playlistBox.values
        .whereType<Map>()
        .any((item) => item['videoId'] == song.id);
    if (!exists) {
      await playlistBox.add(MediaItemBuilder.toJson(song));
    }
  }

  Future<void> _removeFromPlaylist(MediaItem song, String playlistId) async {
    final playlistBox = await Hive.openBox(playlistId);
    final keys = playlistBox
        .toMap()
        .entries
        .where((entry) =>
            entry.value is Map && (entry.value as Map)['videoId'] == song.id)
        .map((entry) => entry.key)
        .toList();
    if (keys.isNotEmpty) await playlistBox.deleteAll(keys);
  }
}
