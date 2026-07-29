import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/flow/blacklist_entry.dart';
import '../../models/recommendation_item.dart';
import '../recommendation/feedback_tracker.dart';

class BlacklistService extends GetxService {
  static const _ownsDismissedIdKey = 'blacklistOwnsDismissedSongId';
  static const _ownsDismissedKeyKey = 'blacklistOwnsDismissedSongKey';

  Box get _trackBox => Hive.box('TrackBlacklist');
  Box get _artistBox => Hive.box('ArtistBlacklist');

  String trackKey(MediaItem song) {
    return RecommendationMediaJson.normalizedSongKey(song);
  }

  String artistKey(String artist) {
    return RecommendationMediaJson.normalizedArtist(artist);
  }

  Future<void> blockTrack(MediaItem song, {String? reason}) async {
    final key = trackKey(song);
    final previousRaw = _trackBox.get(key);
    final previousIsActive = _activeEntry(previousRaw) != null;
    var ownsDismissedId =
        previousIsActive && _ownsDismissal(previousRaw, _ownsDismissedIdKey);
    var ownsDismissedKey =
        previousIsActive && _ownsDismissal(previousRaw, _ownsDismissedKeyKey);
    Box? cacheBox;
    Set<String>? dismissedIds;
    Set<String>? dismissedKeys;
    try {
      cacheBox = Hive.box('RecommendationCache');
      dismissedIds =
          Set<String>.from(cacheBox.get('dismissedSongIds') ?? const []);
      dismissedKeys =
          Set<String>.from(cacheBox.get('dismissedSongKeys') ?? const []);
      ownsDismissedId = ownsDismissedId || !dismissedIds.contains(song.id);
      ownsDismissedKey = ownsDismissedKey || !dismissedKeys.contains(key);
      dismissedIds.add(song.id);
      dismissedKeys.add(key);
    } catch (_) {}
    final entry = BlacklistEntry(
      key: key,
      type: 'track',
      label: '${song.artist ?? ''} - ${song.title}'.trim(),
      createdAt: DateTime.now(),
      reason: reason,
      sourceSongId: song.id,
    );
    await _trackBox.put(key, {
      ...entry.toJson(),
      _ownsDismissedIdKey: ownsDismissedId,
      _ownsDismissedKeyKey: ownsDismissedKey,
    });
    if (cacheBox != null && dismissedIds != null && dismissedKeys != null) {
      await cacheBox.put('dismissedSongIds', dismissedIds.toList());
      await cacheBox.put('dismissedSongKeys', dismissedKeys.toList());
    }
    await _markRecommendationsStale();
  }

  Future<void> blockArtist(String artist, {String? reason}) async {
    final key = artistKey(artist);
    if (key.isEmpty) return;
    final entry = BlacklistEntry(
      key: key,
      type: 'artist',
      label: artist.trim(),
      createdAt: DateTime.now(),
      reason: reason,
    );
    await _artistBox.put(key, entry.toJson());
    await _markRecommendationsStale();
  }

  bool isBlocked(MediaItem song) {
    return isTrackBlocked(song) || isArtistBlocked(song.artist ?? '');
  }

  bool isTrackBlocked(MediaItem song) {
    return _activeEntry(_trackBox.get(trackKey(song))) != null;
  }

  bool isArtistBlocked(String artist) {
    return _artistKeys(artist).any(
      (key) => _activeEntry(_artistBox.get(key)) != null,
    );
  }

  Future<void> unblockTrack(String blacklistKey) async {
    final raw = _trackBox.get(blacklistKey);
    final entry = _entry(raw);
    await _unblock(_trackBox, blacklistKey);
    if (entry != null) await _removeRecommendationDismissal(entry, raw);
  }

  Future<void> unblockArtist(String artistOrKey) async {
    final keys = _artistKeys(artistOrKey);
    if (keys.isEmpty && artistOrKey.isNotEmpty) keys.add(artistOrKey);
    for (final key in keys) {
      await _unblock(_artistBox, key);
    }
  }

  Future<void> clear() async {
    final trackEntries =
        _trackBox.values.where((raw) => _activeEntry(raw) != null).toList();
    await _trackBox.clear();
    await _artistBox.clear();
    for (final raw in trackEntries) {
      final entry = _entry(raw);
      if (entry != null) await _removeRecommendationDismissal(entry, raw);
    }
    await _markRecommendationsStale();
  }

  List<BlacklistEntry> activeTrackEntries() => _activeEntries(_trackBox);

  List<BlacklistEntry> activeArtistEntries() => _activeEntries(_artistBox);

  Set<String> _artistKeys(String artist) {
    return {
      artistKey(artist),
      RecommendationMediaJson.normalizedText(artist.split(',').first),
    }..removeWhere((key) => key.isEmpty);
  }

  List<BlacklistEntry> _activeEntries(Box box) {
    return box.values.map(_activeEntry).whereType<BlacklistEntry>().toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _unblock(Box box, String key) async {
    final entry = _entry(box.get(key));
    if (entry == null) return;
    await box.put(key, entry.copyWith(unblockedAt: DateTime.now()).toJson());
    await _markRecommendationsStale();
  }

  Future<void> _markRecommendationsStale() async {
    if (!Hive.isBoxOpen('RecommendationSettings')) return;
    await Hive.box('RecommendationSettings').put(
      FeedbackTracker.lastMeaningfulFeedbackAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _removeRecommendationDismissal(
    BlacklistEntry entry,
    dynamic raw,
  ) async {
    if (!Hive.isBoxOpen('RecommendationCache')) return;
    final cacheBox = Hive.box('RecommendationCache');
    final dismissedIds =
        Set<String>.from(cacheBox.get('dismissedSongIds') ?? const []);
    final dismissedKeys =
        Set<String>.from(cacheBox.get('dismissedSongKeys') ?? const []);
    if (_ownsDismissal(raw, _ownsDismissedIdKey) &&
        entry.sourceSongId != null) {
      dismissedIds.remove(entry.sourceSongId);
    }
    if (_ownsDismissal(raw, _ownsDismissedKeyKey)) {
      dismissedKeys.remove(entry.key);
    }
    await cacheBox.put('dismissedSongIds', dismissedIds.toList());
    await cacheBox.put('dismissedSongKeys', dismissedKeys.toList());
  }

  BlacklistEntry? _activeEntry(dynamic raw) {
    final entry = _entry(raw);
    if (entry == null || !entry.isActive) return null;
    return entry;
  }

  bool _ownsDismissal(dynamic raw, String key) {
    return raw is Map && raw[key] == true;
  }

  BlacklistEntry? _entry(dynamic raw) {
    if (raw is! Map) return null;
    try {
      return BlacklistEntry.fromJson(raw);
    } catch (_) {
      return null;
    }
  }
}
