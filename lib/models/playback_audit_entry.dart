import 'package:audio_service/audio_service.dart';

import 'media_Item_builder.dart';
import 'recommendation_item.dart';

class PlaybackAuditEntry {
  const PlaybackAuditEntry({
    required this.song,
    required this.playedAt,
    required this.source,
    required this.inLibrary,
    required this.isFavorite,
    required this.isDownloaded,
    required this.isCached,
    required this.inPlaylist,
    this.recommendationSource,
    this.reasonCodes = const [],
    this.recommendationScore,
  });

  final MediaItem song;
  final DateTime playedAt;
  final String source;
  final bool inLibrary;
  final bool isFavorite;
  final bool isDownloaded;
  final bool isCached;
  final bool inPlaylist;
  final String? recommendationSource;
  final List<String> reasonCodes;
  final double? recommendationScore;

  factory PlaybackAuditEntry.fromJson(Map<dynamic, dynamic> json) {
    return PlaybackAuditEntry(
      song: MediaItemBuilder.fromJson(json['song']),
      playedAt: DateTime.fromMillisecondsSinceEpoch(json['playedAt'] as int),
      source: json['source'] as String? ?? 'unknown',
      inLibrary: json['inLibrary'] == true,
      isFavorite: json['isFavorite'] == true,
      isDownloaded: json['isDownloaded'] == true,
      isCached: json['isCached'] == true,
      inPlaylist: json['inPlaylist'] == true,
      recommendationSource: json['recommendationSource'] as String?,
      reasonCodes: List<String>.from(json['reasonCodes'] ?? const []),
      recommendationScore: (json['recommendationScore'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'song': RecommendationMediaJson.fromMediaItem(song),
      'playedAt': playedAt.millisecondsSinceEpoch,
      'source': source,
      'inLibrary': inLibrary,
      'isFavorite': isFavorite,
      'isDownloaded': isDownloaded,
      'isCached': isCached,
      'inPlaylist': inPlaylist,
      'recommendationSource': recommendationSource,
      'reasonCodes': reasonCodes,
      'recommendationScore': recommendationScore,
    };
  }
}
