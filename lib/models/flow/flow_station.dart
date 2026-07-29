import 'package:audio_service/audio_service.dart';

import '../media_Item_builder.dart';
import '../recommendation_item.dart';

class FlowStation {
  const FlowStation({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.seedTerms,
    required this.searchQueries,
    required this.modeName,
    required this.familiarity,
    required this.variety,
    required this.deepCuts,
    required this.localWeight,
    required this.externalWeight,
    required this.confidence,
    required this.reason,
    this.previewSong,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<String> tags;
  final List<String> seedTerms;
  final List<String> searchQueries;
  final String modeName;
  final double familiarity;
  final double variety;
  final double deepCuts;
  final double localWeight;
  final double externalWeight;
  final double confidence;
  final String reason;
  final MediaItem? previewSong;

  List<String> get normalizedTerms {
    final terms = <String>{
      ...tags,
      ...seedTerms,
    };
    return terms
        .map(RecommendationMediaJson.normalizedText)
        .where(
            (term) => term.length >= 3 && !_genericStationTerms.contains(term))
        .toList();
  }

  FlowStation copyWith({
    String? id,
    String? title,
    String? subtitle,
    List<String>? tags,
    List<String>? seedTerms,
    List<String>? searchQueries,
    String? modeName,
    double? familiarity,
    double? variety,
    double? deepCuts,
    double? localWeight,
    double? externalWeight,
    double? confidence,
    String? reason,
    MediaItem? previewSong,
  }) {
    return FlowStation(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      tags: tags ?? this.tags,
      seedTerms: seedTerms ?? this.seedTerms,
      searchQueries: searchQueries ?? this.searchQueries,
      modeName: modeName ?? this.modeName,
      familiarity: _clamp(familiarity ?? this.familiarity),
      variety: _clamp(variety ?? this.variety),
      deepCuts: _clamp(deepCuts ?? this.deepCuts),
      localWeight: _clamp(localWeight ?? this.localWeight),
      externalWeight: _clamp(externalWeight ?? this.externalWeight),
      confidence: _clamp(confidence ?? this.confidence),
      reason: reason ?? this.reason,
      previewSong: previewSong ?? this.previewSong,
    );
  }

  factory FlowStation.fromJson(Map<dynamic, dynamic> json) {
    return FlowStation(
      id: json['id']?.toString() ?? 'station',
      title: json['title']?.toString() ?? 'Flow',
      subtitle: json['subtitle']?.toString() ?? '',
      tags: List<String>.from(json['tags'] ?? const []),
      seedTerms: List<String>.from(json['seedTerms'] ?? const []),
      searchQueries: List<String>.from(json['searchQueries'] ?? const []),
      modeName: json['modeName']?.toString() ?? 'auto',
      familiarity: _number(json['familiarity'], .55),
      variety: _number(json['variety'], .55),
      deepCuts: _number(json['deepCuts'], .35),
      localWeight: _number(json['localWeight'], .45),
      externalWeight: _number(json['externalWeight'], .55),
      confidence: _number(json['confidence'], .5),
      reason: json['reason']?.toString() ?? '',
      previewSong: json['previewSong'] is Map
          ? MediaItemBuilder.fromJson(json['previewSong'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'tags': tags,
      'seedTerms': seedTerms,
      'searchQueries': searchQueries,
      'modeName': modeName,
      'familiarity': familiarity,
      'variety': variety,
      'deepCuts': deepCuts,
      'localWeight': localWeight,
      'externalWeight': externalWeight,
      'confidence': confidence,
      'reason': reason,
      if (previewSong != null)
        'previewSong': RecommendationMediaJson.fromMediaItem(previewSong!),
    };
  }

  static double _clamp(double value) => value.clamp(0.0, 1.0).toDouble();

  static double _number(dynamic value, double fallback) {
    if (value is num) return _clamp(value.toDouble());
    return fallback;
  }
}

const _genericStationTerms = {
  'music',
  'song',
  'songs',
  'mix',
  'playlist',
  'new',
  'fresh',
};
