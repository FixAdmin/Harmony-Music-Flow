import 'package:audio_service/audio_service.dart';

import '../../models/recommendation_item.dart';

class FlowQueuePolicy {
  const FlowQueuePolicy._();

  static bool canRequestNext({
    required bool hasCurrentSong,
    required bool hasQueue,
    required bool isAtQueueEnd,
    required bool isFlowActive,
    required bool isRadioActive,
  }) {
    if (!hasCurrentSong || !hasQueue) return false;
    return !isAtQueueEnd || isFlowActive || isRadioActive;
  }

  static List<MediaItem> mergeUpcoming({
    required List<MediaItem> queue,
    required MediaItem currentSong,
    required Iterable<MediaItem> planned,
    bool replaceUpcoming = false,
    MediaItem? removeSong,
    String? removeArtist,
    bool Function(MediaItem item)? isEligible,
  }) {
    final currentIndex = queue.indexWhere((item) => item.id == currentSong.id);
    final prefix = currentIndex < 0
        ? <MediaItem>[currentSong]
        : queue.take(currentIndex + 1).toList();
    final existingUpcoming =
        currentIndex < 0 ? const <MediaItem>[] : queue.skip(currentIndex + 1);
    final normalizedArtist = RecommendationMediaJson.normalizedArtist(
      removeArtist ?? '',
    );

    bool keep(MediaItem item) {
      if (removeSong != null &&
          RecommendationMediaJson.sameSong(item, removeSong)) {
        return false;
      }
      if (normalizedArtist.isNotEmpty &&
          RecommendationMediaJson.normalizedPrimaryArtist(item) ==
              normalizedArtist) {
        return false;
      }
      return isEligible?.call(item) ?? true;
    }

    final seenIds = prefix.map((item) => item.id).toSet();
    final seenKeys = prefix.map(_songKey).toSet();
    final upcoming = <MediaItem>[];
    final candidates = <MediaItem>[
      if (!replaceUpcoming) ...existingUpcoming.where(keep),
      ...planned.where(keep),
    ];
    for (final item in candidates) {
      if (item.id.trim().isEmpty) continue;
      if (!seenIds.add(item.id) || !seenKeys.add(_songKey(item))) continue;
      upcoming.add(item);
    }
    return [...prefix, ...upcoming];
  }

  static String _songKey(MediaItem item) {
    final key = RecommendationMediaJson.normalizedSongKey(item);
    return key.isEmpty ? item.id : key;
  }
}
