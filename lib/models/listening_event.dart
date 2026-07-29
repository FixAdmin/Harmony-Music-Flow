import 'package:audio_service/audio_service.dart';

import 'media_Item_builder.dart';
import 'recommendation_item.dart';

class ListeningEventType {
  static const playStart = 'play_start';
  static const completed70 = 'completed_70';
  static const skipEarly = 'skip_early';
  static const like = 'like';
  static const recommendationClick = 'recommendation_click';
  static const dismissRecommendation = 'dismiss_recommendation';
  static const flowMoreLikeThis = 'flow_more_like_this';
  static const flowPlayLessLikeThis = 'flow_play_less_like_this';
  static const flowBlockTrack = 'flow_block_track';
  static const flowBlockArtist = 'flow_block_artist';
}

class ListeningEvent {
  ListeningEvent({
    required this.type,
    required this.song,
    required this.timestamp,
    this.positionSeconds,
    this.durationSeconds,
    this.source,
    this.sessionId,
  });

  final String type;
  final MediaItem song;
  final DateTime timestamp;
  final int? positionSeconds;
  final int? durationSeconds;
  final String? source;
  final String? sessionId;

  factory ListeningEvent.fromJson(Map<dynamic, dynamic> json) {
    return ListeningEvent(
      type: json['type'] as String,
      song: MediaItemBuilder.fromJson(json['song']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      positionSeconds: json['positionSeconds'] as int?,
      durationSeconds: json['durationSeconds'] as int?,
      source: json['source'] as String?,
      sessionId: json['sessionId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'song': RecommendationMediaJson.fromMediaItem(song),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'positionSeconds': positionSeconds,
      'durationSeconds': durationSeconds,
      'source': source,
      'sessionId': sessionId,
    };
  }
}
