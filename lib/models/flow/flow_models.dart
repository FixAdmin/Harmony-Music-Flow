import 'package:audio_service/audio_service.dart';

import '../media_Item_builder.dart';
import '../recommendation_item.dart';
import 'flow_station.dart';

enum FlowMode { auto, chill, energy, melancholy, discover }

enum FlowFeedbackAction {
  moreLikeThis,
  playLessLikeThis,
  notNow,
  blockTrack,
  blockArtist,
  like,
  completion,
  earlySkip,
}

class FlowTunerSettings {
  const FlowTunerSettings({
    required this.mode,
    required this.familiarity,
    required this.variety,
    required this.deepCuts,
    required this.genres,
  });

  final FlowMode mode;
  final double familiarity;
  final double variety;
  final double deepCuts;
  final Set<String> genres;

  factory FlowTunerSettings.defaults() {
    return const FlowTunerSettings(
      mode: FlowMode.auto,
      familiarity: .55,
      variety: .55,
      deepCuts: .35,
      genres: {},
    );
  }

  FlowTunerSettings copyWith({
    FlowMode? mode,
    double? familiarity,
    double? variety,
    double? deepCuts,
    Set<String>? genres,
  }) {
    return FlowTunerSettings(
      mode: mode ?? this.mode,
      familiarity: _clamp(familiarity ?? this.familiarity),
      variety: _clamp(variety ?? this.variety),
      deepCuts: _clamp(deepCuts ?? this.deepCuts),
      genres: genres ?? this.genres,
    );
  }

  factory FlowTunerSettings.fromJson(Map<dynamic, dynamic> json) {
    return FlowTunerSettings(
      mode: FlowMode.values.firstWhere(
        (mode) => mode.name == json['mode'],
        orElse: () => FlowMode.auto,
      ),
      familiarity: _number(json['familiarity'], .55),
      variety: _number(json['variety'], .55),
      deepCuts: _number(json['deepCuts'], .35),
      genres: Set<String>.from(json['genres'] ?? const []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.name,
      'familiarity': familiarity,
      'variety': variety,
      'deepCuts': deepCuts,
      'genres': genres.toList()..sort(),
    };
  }

  static double _clamp(double value) => value.clamp(0.0, 1.0).toDouble();

  static double _number(dynamic value, double fallback) {
    if (value is num) return _clamp(value.toDouble());
    return fallback;
  }
}

class FlowSession {
  const FlowSession({
    required this.id,
    required this.startedAt,
    required this.tuner,
    required this.seedSongIds,
    required this.skipStreak,
    required this.isActive,
    this.station,
  });

  final String id;
  final DateTime startedAt;
  final FlowTunerSettings tuner;
  final List<String> seedSongIds;
  final int skipStreak;
  final bool isActive;
  final FlowStation? station;

  factory FlowSession.start({
    required FlowTunerSettings tuner,
    List<String> seedSongIds = const [],
    FlowStation? station,
  }) {
    final now = DateTime.now();
    return FlowSession(
      id: 'flow_${now.microsecondsSinceEpoch}',
      startedAt: now,
      tuner: tuner,
      seedSongIds: seedSongIds,
      skipStreak: 0,
      isActive: true,
      station: station,
    );
  }

  FlowSession copyWith({
    FlowTunerSettings? tuner,
    List<String>? seedSongIds,
    int? skipStreak,
    bool? isActive,
    FlowStation? station,
  }) {
    return FlowSession(
      id: id,
      startedAt: startedAt,
      tuner: tuner ?? this.tuner,
      seedSongIds: seedSongIds ?? this.seedSongIds,
      skipStreak: skipStreak ?? this.skipStreak,
      isActive: isActive ?? this.isActive,
      station: station ?? this.station,
    );
  }

  factory FlowSession.fromJson(Map<dynamic, dynamic> json) {
    return FlowSession(
      id: json['id'] as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int),
      tuner: FlowTunerSettings.fromJson(json['tuner'] ?? const {}),
      seedSongIds: List<String>.from(json['seedSongIds'] ?? const []),
      skipStreak: json['skipStreak'] as int? ?? 0,
      isActive: json['isActive'] as bool? ?? false,
      station: json['station'] is Map
          ? FlowStation.fromJson(json['station'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startedAt': startedAt.millisecondsSinceEpoch,
      'tuner': tuner.toJson(),
      'seedSongIds': seedSongIds,
      'skipStreak': skipStreak,
      'isActive': isActive,
      if (station != null) 'station': station!.toJson(),
    };
  }
}

class FlowQueueItem {
  const FlowQueueItem({
    required this.item,
    required this.sessionId,
    required this.score,
    required this.locked,
    required this.reasonCodes,
    required this.source,
  });

  final MediaItem item;
  final String sessionId;
  final double score;
  final bool locked;
  final List<String> reasonCodes;
  final String source;

  factory FlowQueueItem.fromJson(Map<dynamic, dynamic> json) {
    return FlowQueueItem(
      item: MediaItemBuilder.fromJson(json['item']),
      sessionId: json['sessionId'] as String,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      locked: json['locked'] as bool? ?? false,
      reasonCodes: List<String>.from(json['reasonCodes'] ?? const []),
      source: json['source'] as String? ?? 'unknown',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item': RecommendationMediaJson.fromMediaItem(item),
      'sessionId': sessionId,
      'score': score,
      'locked': locked,
      'reasonCodes': reasonCodes,
      'source': source,
    };
  }
}

class FlowCandidateScore {
  const FlowCandidateScore({
    required this.item,
    required this.source,
    required this.score,
    required this.reasonCodes,
  });

  final MediaItem item;
  final String source;
  final double score;
  final List<String> reasonCodes;
}
