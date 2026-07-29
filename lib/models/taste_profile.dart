import 'package:audio_service/audio_service.dart';

import 'recommendation_item.dart';

class TasteProfile {
  TasteProfile({
    required this.recentSeeds,
    required this.topArtists,
    required this.skippedArtists,
    required this.playedSongIds,
    required this.likedSongIds,
    required this.dismissedSongIds,
    this.playedSongKeys = const {},
    this.likedSongKeys = const {},
    this.dismissedSongKeys = const {},
    this.skippedSongKeys = const {},
    this.lastPlayedAtBySongKey = const {},
  });

  final List<MediaItem> recentSeeds;
  final Map<String, double> topArtists;
  final Map<String, double> skippedArtists;
  final Set<String> playedSongIds;
  final Set<String> likedSongIds;
  final Set<String> dismissedSongIds;
  final Set<String> playedSongKeys;
  final Set<String> likedSongKeys;
  final Set<String> dismissedSongKeys;
  final Set<String> skippedSongKeys;
  final Map<String, int> lastPlayedAtBySongKey;

  bool get hasSignals =>
      recentSeeds.isNotEmpty ||
      topArtists.isNotEmpty ||
      likedSongIds.isNotEmpty;

  double artistPreference(MediaItem item) {
    final normalized = RecommendationMediaJson.normalizedPrimaryArtist(item);
    final display = (item.artist ?? '').split(',').first.trim();
    return topArtists[normalized] ?? topArtists[display] ?? 0;
  }

  double artistSkipScore(MediaItem item) {
    final normalized = RecommendationMediaJson.normalizedPrimaryArtist(item);
    final display = (item.artist ?? '').split(',').first.trim();
    return skippedArtists[normalized] ?? skippedArtists[display] ?? 0;
  }

  bool hasPlayed(MediaItem item) {
    return playedSongIds.contains(item.id) ||
        playedSongKeys
            .contains(RecommendationMediaJson.normalizedSongKey(item));
  }

  bool isLiked(MediaItem item) {
    return likedSongIds.contains(item.id) ||
        likedSongKeys.contains(RecommendationMediaJson.normalizedSongKey(item));
  }

  bool isDismissed(MediaItem item) {
    return dismissedSongIds.contains(item.id) ||
        dismissedSongKeys
            .contains(RecommendationMediaJson.normalizedSongKey(item));
  }

  bool wasSkipped(MediaItem item) {
    return skippedSongKeys
        .contains(RecommendationMediaJson.normalizedSongKey(item));
  }

  DateTime? lastPlayedAt(MediaItem item) {
    final timestamp =
        lastPlayedAtBySongKey[RecommendationMediaJson.normalizedSongKey(item)];
    return timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Map<String, dynamic> toSummaryJson() {
    return {
      'topArtists': topArtists,
      'skippedArtists': skippedArtists,
      'playedSongIds': playedSongIds.take(100).toList(),
      'likedSongIds': likedSongIds.take(100).toList(),
      'playedSongKeys': playedSongKeys.take(100).toList(),
      'likedSongKeys': likedSongKeys.take(100).toList(),
      'dismissedSongKeys': dismissedSongKeys.take(100).toList(),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
  }
}
