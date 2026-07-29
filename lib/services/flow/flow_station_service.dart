import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

import '../../models/flow/flow_models.dart';
import '../../models/flow/flow_station.dart';
import '../../models/recommendation_item.dart';
import '../../models/taste_profile.dart';
import '../recommendation/lastfm_provider.dart';
import '../recommendation/taste_profile_service.dart';

class FlowStationService extends GetxService {
  TasteProfileService get _tasteProfileService =>
      Get.find<TasteProfileService>();
  LastFmProvider get _lastFmProvider => Get.find<LastFmProvider>();

  final stations = <FlowStation>[].obs;
  final isRefreshing = false.obs;

  Future<void> refreshStations() async {
    if (isRefreshing.isTrue) return;
    isRefreshing.value = true;
    try {
      final profile = await _tasteProfileService.buildProfile();
      final externalTags = await _loadExternalTags(profile);
      stations.assignAll(buildStations(profile, externalTags: externalTags));
    } finally {
      isRefreshing.value = false;
    }
  }

  List<FlowStation> buildStations(
    TasteProfile profile, {
    Iterable<String> externalTags = const [],
  }) {
    final signals = _ProfileSignals.from(
      profile,
      externalTags: externalTags,
    );
    final scored = <_ScoredStation>[];

    for (final template in _templates) {
      final score = _scoreTemplate(template, signals, profile);
      if (score.confidence < .24 && profile.hasSignals) continue;
      scored.add(score);
    }

    scored.sort((a, b) {
      final confidence = b.confidence.compareTo(a.confidence);
      if (confidence != 0) return confidence;
      return a.template.order.compareTo(b.template.order);
    });

    final result = <FlowStation>[];
    final usedPreviewIds = <String>{};
    final usedPreviewKeys = <String>{};
    final usedPreviewArtUrls = <String>{};
    for (final station in _dynamicTagStations(profile, externalTags).take(2)) {
      result.add(station.copyWith(
        previewSong: _bestPreviewForTerms(
          station.normalizedTerms,
          profile,
          usedPreviewIds: usedPreviewIds,
          usedPreviewKeys: usedPreviewKeys,
          usedPreviewArtUrls: usedPreviewArtUrls,
        ),
      ));
    }
    for (final item in scored) {
      if (result.length >= 7) break;
      result.add(item.toStation(
        previewSong: _bestPreviewSong(
          item.template,
          profile,
          item.matchedTerms,
          usedPreviewIds: usedPreviewIds,
          usedPreviewKeys: usedPreviewKeys,
          usedPreviewArtUrls: usedPreviewArtUrls,
        ),
      ));
    }

    if (result.length < 4) {
      for (final template in _templates.where((item) => item.fallback)) {
        if (result.any((station) => station.id == template.id)) continue;
        result.add(_ScoredStation(
          template: template,
          confidence: profile.hasSignals ? .34 : .46,
          matchedTerms: const [],
          reason: profile.hasSignals ? 'fallback' : 'cold start',
        ).toStation(
          previewSong: _bestPreviewSong(
            template,
            profile,
            const [],
            usedPreviewIds: usedPreviewIds,
            usedPreviewKeys: usedPreviewKeys,
            usedPreviewArtUrls: usedPreviewArtUrls,
          ),
        ));
        if (result.length >= 4) break;
      }
    }

    return result;
  }

  Future<List<String>> _loadExternalTags(TasteProfile profile) async {
    try {
      if (!_lastFmProvider.isConfigured || profile.recentSeeds.isEmpty) {
        return const [];
      }
      final tagLists = await Future.wait(
        profile.recentSeeds.take(6).map(
              (seed) => _lastFmProvider
                  .getTopTags(seed, limit: 6)
                  .timeout(const Duration(seconds: 5), onTimeout: () => []),
            ),
      );
      return tagLists.expand((tags) => tags).take(36).toList();
    } catch (_) {
      return const [];
    }
  }

  _ScoredStation _scoreTemplate(
    _StationTemplate template,
    _ProfileSignals signals,
    TasteProfile profile,
  ) {
    final hasSignals = profile.hasSignals;
    var score = hasSignals
        ? 0.0
        : template.fallback
            ? .38
            : .12;
    final matched = <String>{};

    for (final term in template.terms) {
      final normalized = RecommendationMediaJson.normalizedText(term);
      if (normalized.isEmpty) continue;

      final textHits = signals.termFrequency(normalized);
      if (textHits > 0) {
        score += (textHits.clamp(1, 5)) * .045;
        matched.add(term);
      }

      final seedHits = signals.seedMatches(normalized);
      if (seedHits > 0) {
        score += (seedHits.clamp(1, 4)) * .085;
        matched.add(term);
      }
    }

    if (matched.length >= 2) score += .12;
    if (matched.length >= 4) score += .10;
    if (signals.seedCount < 4 && !template.fallback) score *= .75;

    final confidence = score.clamp(0.0, .96).toDouble();
    final reason = matched.isEmpty
        ? hasSignals
            ? 'general fit'
            : 'cold start'
        : 'matched ${matched.take(3).join(', ')}';

    return _ScoredStation(
      template: template,
      confidence: confidence,
      matchedTerms: matched.toList(),
      reason: reason,
    );
  }

  MediaItem? _bestPreviewSong(_StationTemplate template, TasteProfile profile,
      Iterable<String> matchedTerms,
      {Set<String>? usedPreviewIds,
      Set<String>? usedPreviewKeys,
      Set<String>? usedPreviewArtUrls}) {
    final terms = {
      ...template.terms,
      ...matchedTerms,
    }
        .map(RecommendationMediaJson.normalizedText)
        .where((term) => term.length >= 3)
        .toList();
    return _bestPreviewForTerms(
      terms,
      profile,
      usedPreviewIds: usedPreviewIds,
      usedPreviewKeys: usedPreviewKeys,
      usedPreviewArtUrls: usedPreviewArtUrls,
    );
  }

  MediaItem? _bestPreviewForTerms(
    Iterable<String> terms,
    TasteProfile profile, {
    Set<String>? usedPreviewIds,
    Set<String>? usedPreviewKeys,
    Set<String>? usedPreviewArtUrls,
  }) {
    if (profile.recentSeeds.isEmpty) return null;
    final normalizedTerms = terms
        .map(RecommendationMediaJson.normalizedText)
        .where((term) => term.length >= 3)
        .toList();

    MediaItem? best;
    var bestScore = -1;
    for (final seed in profile.recentSeeds) {
      if (usedPreviewIds?.contains(seed.id) ?? false) continue;
      final songKey = RecommendationMediaJson.normalizedSongKey(seed);
      if (songKey.isNotEmpty && (usedPreviewKeys?.contains(songKey) ?? false)) {
        continue;
      }
      final artUrl = seed.artUri?.toString().trim();
      if (artUrl != null &&
          artUrl.isNotEmpty &&
          (usedPreviewArtUrls?.contains(artUrl) ?? false)) {
        continue;
      }
      final text = RecommendationMediaJson.normalizedText(
        '${seed.title} ${seed.artist ?? ''} ${seed.album ?? ''}',
      );
      final termMatches = normalizedTerms
          .where(
            (term) =>
                RecommendationMediaJson.containsNormalizedTerm(text, term),
          )
          .length;
      if (termMatches == 0) continue;
      final score = (termMatches * 4) + (seed.artUri == null ? 0 : 2);
      if (score > bestScore) {
        best = seed;
        bestScore = score;
      }
    }
    if (best != null) {
      usedPreviewIds?.add(best.id);
      final songKey = RecommendationMediaJson.normalizedSongKey(best);
      if (songKey.isNotEmpty) usedPreviewKeys?.add(songKey);
      final artUrl = best.artUri?.toString().trim();
      if (artUrl != null && artUrl.isNotEmpty) {
        usedPreviewArtUrls?.add(artUrl);
      }
    }
    return best;
  }

  List<FlowStation> _dynamicTagStations(
    TasteProfile profile,
    Iterable<String> externalTags,
  ) {
    if (!profile.hasSignals) return const [];
    final counts = <String, int>{};
    final labels = <String, String>{};
    for (final rawTag in externalTags) {
      final tag = RecommendationMediaJson.normalizedText(rawTag);
      if (tag.length < 3 ||
          tag.length > 32 ||
          _ignoredDynamicTags.contains(tag)) {
        continue;
      }
      counts[tag] = (counts[tag] ?? 0) + 1;
      labels.putIfAbsent(tag, () => rawTag.trim());
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final frequency = b.value.compareTo(a.value);
        if (frequency != 0) return frequency;
        return b.key.length.compareTo(a.key.length);
      });

    return ranked.take(4).map((entry) {
      final tag = labels[entry.key] ?? entry.key;
      final mode = _modeForTag(entry.key);
      return FlowStation(
        id: 'tag_${entry.key.replaceAll(' ', '_')}',
        title: _titleCase(tag),
        subtitle: 'Adaptive lane from your recent listening',
        tags: [tag],
        seedTerms: [tag],
        searchQueries: ['$tag music', '$tag songs', '$tag mix'],
        modeName: mode.name,
        familiarity: .4,
        variety: .72,
        deepCuts: .56,
        localWeight: .3,
        externalWeight: .7,
        confidence:
            (.42 + (entry.value.clamp(1, 4) * .1)).clamp(0.0, .86).toDouble(),
        reason: 'Last.fm tag seen ${entry.value} times',
      );
    }).toList();
  }

  FlowMode _modeForTag(String tag) {
    if (const ['chill', 'ambient', 'lofi', 'calm', 'acoustic']
        .any(tag.contains)) {
      return FlowMode.chill;
    }
    if (const ['dance', 'rock', 'metal', 'edm', 'punk', 'energy']
        .any(tag.contains)) {
      return FlowMode.energy;
    }
    if (const ['sad', 'dark', 'melancholy', 'slow', 'emotional']
        .any(tag.contains)) {
      return FlowMode.melancholy;
    }
    return FlowMode.discover;
  }

  String _titleCase(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

const _ignoredDynamicTags = {
  'music',
  'favorites',
  'favourite',
  'seen live',
  'albums i own',
  'under 2000 listeners',
};

class _ProfileSignals {
  _ProfileSignals({
    required this.seedTexts,
    required this.signalTexts,
  });

  final List<String> seedTexts;
  final List<String> signalTexts;

  int get seedCount => seedTexts.length;

  factory _ProfileSignals.from(
    TasteProfile profile, {
    Iterable<String> externalTags = const [],
  }) {
    final seedTexts = profile.recentSeeds.map(_songText).toList();
    return _ProfileSignals(
      seedTexts: seedTexts,
      signalTexts: [
        ...seedTexts,
        ...profile.topArtists.keys.map(RecommendationMediaJson.normalizedText),
        ...externalTags.map(RecommendationMediaJson.normalizedText),
      ],
    );
  }

  int termFrequency(String term) {
    if (term.isEmpty) return 0;
    return signalTexts
        .where(
          (text) => RecommendationMediaJson.containsNormalizedTerm(text, term),
        )
        .length;
  }

  int seedMatches(String term) {
    if (term.isEmpty) return 0;
    return seedTexts
        .where(
          (text) => RecommendationMediaJson.containsNormalizedTerm(text, term),
        )
        .length;
  }

  static String _songText(MediaItem item) {
    return RecommendationMediaJson.normalizedText(
      '${item.title} ${item.artist ?? ''} ${item.album ?? ''}',
    );
  }
}

class _ScoredStation {
  const _ScoredStation({
    required this.template,
    required this.confidence,
    required this.matchedTerms,
    required this.reason,
  });

  final _StationTemplate template;
  final double confidence;
  final List<String> matchedTerms;
  final String reason;

  FlowStation toStation({MediaItem? previewSong}) {
    final seedTerms = <String>{
      ...template.terms.take(10),
      ...matchedTerms.take(6),
    }.toList();
    return FlowStation(
      id: template.id,
      title: template.title,
      subtitle: template.subtitle,
      tags: template.tags,
      seedTerms: seedTerms,
      searchQueries: template.queries,
      modeName: template.modeName,
      familiarity: template.familiarity,
      variety: template.variety,
      deepCuts: template.deepCuts,
      localWeight: template.localWeight,
      externalWeight: template.externalWeight,
      confidence: confidence,
      reason: reason,
      previewSong: previewSong,
    );
  }
}

class _StationTemplate {
  const _StationTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.terms,
    required this.queries,
    required this.modeName,
    required this.familiarity,
    required this.variety,
    required this.deepCuts,
    required this.localWeight,
    required this.externalWeight,
    required this.order,
    this.fallback = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<String> tags;
  final List<String> terms;
  final List<String> queries;
  final String modeName;
  final double familiarity;
  final double variety;
  final double deepCuts;
  final double localWeight;
  final double externalWeight;
  final int order;
  final bool fallback;
}

const _templates = <_StationTemplate>[
  _StationTemplate(
    id: 'cinematic',
    title: 'Cinematic',
    subtitle: 'Scores, strings, epic instrumentals',
    tags: ['soundtrack', 'orchestral', 'epic'],
    terms: [
      'soundtrack',
      'score',
      'ost',
      'orchestral',
      'orchestra',
      'symphony',
      'epic',
      'trailer',
      'violin',
      'strings',
      'piano',
      'classical',
      'vivaldi',
      'bach',
      'mozart',
      'beethoven',
      'presto',
    ],
    queries: [
      'cinematic orchestral music',
      'epic soundtrack music',
      'modern classical strings',
    ],
    modeName: 'discover',
    familiarity: .42,
    variety: .68,
    deepCuts: .52,
    localWeight: .34,
    externalWeight: .66,
    order: 0,
    fallback: true,
  ),
  _StationTemplate(
    id: 'gaming_focus',
    title: 'Gaming Focus',
    subtitle: 'Instrumental momentum for long sessions',
    tags: ['gaming', 'focus', 'instrumental'],
    terms: [
      'gaming',
      'game',
      'video game',
      'focus',
      'instrumental',
      'synthwave',
      'electronic',
      'battle',
      'cyberpunk',
      'ambient',
      'lofi',
      'drum and bass',
    ],
    queries: [
      'gaming focus music',
      'video game soundtrack mix',
      'instrumental electronic focus',
    ],
    modeName: 'discover',
    familiarity: .36,
    variety: .74,
    deepCuts: .56,
    localWeight: .28,
    externalWeight: .72,
    order: 1,
    fallback: true,
  ),
  _StationTemplate(
    id: 'anime_ost',
    title: 'Anime / OST',
    subtitle: 'Openings, endings, J-pop and scores',
    tags: ['anime', 'ost', 'j-pop'],
    terms: [
      'anime',
      'ost',
      'opening',
      'ending',
      'j-pop',
      'jpop',
      'japanese',
      'vocaloid',
      'utaite',
      'soundtrack',
    ],
    queries: [
      'anime ost songs',
      'anime opening music',
      'j-pop anime soundtrack',
    ],
    modeName: 'discover',
    familiarity: .34,
    variety: .76,
    deepCuts: .6,
    localWeight: .24,
    externalWeight: .76,
    order: 2,
  ),
  _StationTemplate(
    id: 'night',
    title: 'Night',
    subtitle: 'Dark, slow and late mood',
    tags: ['dark', 'slow', 'night'],
    terms: [
      'night',
      'dark',
      'sad',
      'slow',
      'rain',
      'melancholy',
      'melancholic',
      'emotional',
      'ambient',
      'piano',
      'sleep',
    ],
    queries: [
      'dark slow music',
      'melancholy night music',
      'sad ambient piano',
    ],
    modeName: 'melancholy',
    familiarity: .52,
    variety: .48,
    deepCuts: .38,
    localWeight: .46,
    externalWeight: .54,
    order: 3,
    fallback: true,
  ),
  _StationTemplate(
    id: 'energy',
    title: 'Energy',
    subtitle: 'Fast, bright and high-pressure',
    tags: ['energy', 'dance', 'drive'],
    terms: [
      'energy',
      'dance',
      'party',
      'club',
      'rock',
      'metal',
      'phonk',
      'workout',
      'edm',
      'drum',
      'bass',
      'speed',
    ],
    queries: [
      'high energy music',
      'workout electronic music',
      'energetic rock songs',
    ],
    modeName: 'energy',
    familiarity: .46,
    variety: .62,
    deepCuts: .42,
    localWeight: .38,
    externalWeight: .62,
    order: 4,
    fallback: true,
  ),
  _StationTemplate(
    id: 'chill_focus',
    title: 'Chill Focus',
    subtitle: 'Calm, clean background flow',
    tags: ['chill', 'focus', 'calm'],
    terms: [
      'chill',
      'lofi',
      'lo-fi',
      'ambient',
      'acoustic',
      'calm',
      'study',
      'focus',
      'relax',
      'soft',
    ],
    queries: [
      'chill focus music',
      'lofi study music',
      'ambient acoustic focus',
    ],
    modeName: 'chill',
    familiarity: .58,
    variety: .42,
    deepCuts: .34,
    localWeight: .48,
    externalWeight: .52,
    order: 5,
    fallback: true,
  ),
  _StationTemplate(
    id: 'discover',
    title: 'Discover',
    subtitle: 'More outside the usual lane',
    tags: ['new', 'deep cuts', 'variety'],
    terms: [
      'new',
      'fresh',
      'indie',
      'alternative',
      'underground',
      'deep cuts',
      'rare',
      'mix',
    ],
    queries: [
      'new music discovery',
      'underground music mix',
      'fresh alternative songs',
    ],
    modeName: 'discover',
    familiarity: .22,
    variety: .88,
    deepCuts: .78,
    localWeight: .18,
    externalWeight: .82,
    order: 6,
    fallback: true,
  ),
];
