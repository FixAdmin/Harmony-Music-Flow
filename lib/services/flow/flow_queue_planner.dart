import 'package:audio_service/audio_service.dart';

import '../../models/flow/flow_models.dart';
import '../../models/flow/flow_station.dart';
import '../../models/recommendation_item.dart';
import '../../models/taste_profile.dart';
import '../library/blacklist_service.dart';

class FlowQueuePlanner {
  FlowQueuePlanner({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  List<FlowQueueItem> planNext({
    required List<RecommendationCandidate> candidates,
    required TasteProfile profile,
    required FlowSession session,
    required FlowTunerSettings tuner,
    required BlacklistService blacklist,
    List<MediaItem> recentQueue = const [],
    List<MediaItem> existingQueue = const [],
    List<FlowQueueItem> locked = const [],
    int limit = 12,
  }) {
    final selected = <FlowQueueItem>[...locked];
    final excludedIds = <String>{
      ...selected.map((item) => item.item.id),
      ...existingQueue.map((item) => item.id),
    };
    final excludedKeys = <String>{
      ...selected.map((item) => _songKey(item.item)),
      ...existingQueue.map(_songKey),
    };
    final bestBySong = <String, FlowCandidateScore>{};

    for (final candidate in candidates) {
      final item = candidate.item;
      if (item.title.trim().isEmpty || item.artist?.trim().isEmpty == true) {
        continue;
      }
      if (blacklist.isBlocked(item) || profile.isDismissed(item)) continue;
      if (RecommendationMediaJson.hasNoisyVersionMarker(item)) continue;
      final key = _songKey(item);
      if (excludedIds.contains(item.id) || excludedKeys.contains(key)) continue;

      final scored = _score(candidate, profile, tuner, session, recentQueue);
      final existing = bestBySong[key];
      if (existing == null || scored.score > existing.score) {
        bestBySong[key] = scored;
      }
    }

    final scored = bestBySong.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final diversityWeight = _diversityWeight(tuner);
    final sourceBlend = _sourceBlend(
      scored,
      selected,
      limit,
      session.station?.localWeight ?? tuner.familiarity,
    );

    while (selected.length < limit && scored.isNotEmpty) {
      scored.sort((a, b) {
        final aScore = _mmrScore(a, selected, recentQueue, diversityWeight);
        final bScore = _mmrScore(b, selected, recentQueue, diversityWeight);
        return bScore.compareTo(aScore);
      });

      final preferredLocal = _preferredLocalSource(
        sourceBlend,
        selected,
        scored,
        limit,
      );
      var nextIndex = _nextIndex(
        scored,
        selected,
        recentQueue,
        tuner,
        preferredLocal: preferredLocal,
        strictAlbum: true,
      );
      if (nextIndex < 0 && preferredLocal != null) {
        nextIndex = _nextIndex(
          scored,
          selected,
          recentQueue,
          tuner,
          strictAlbum: true,
        );
      }
      if (nextIndex < 0) {
        nextIndex = _nextIndex(
          scored,
          selected,
          recentQueue,
          tuner,
          preferredLocal: preferredLocal,
          strictAlbum: false,
        );
      }
      if (nextIndex < 0 && preferredLocal != null) {
        nextIndex = _nextIndex(
          scored,
          selected,
          recentQueue,
          tuner,
          strictAlbum: false,
        );
      }
      if (nextIndex < 0) nextIndex = 0;

      final next = scored.removeAt(nextIndex);
      selected.add(FlowQueueItem(
        item: next.item,
        sessionId: session.id,
        score: next.score,
        locked: false,
        reasonCodes: next.reasonCodes,
        source: next.source,
      ));
    }

    return selected.take(limit).toList();
  }

  int _nextIndex(
    List<FlowCandidateScore> scored,
    List<FlowQueueItem> selected,
    List<MediaItem> recentQueue,
    FlowTunerSettings tuner, {
    bool? preferredLocal,
    required bool strictAlbum,
  }) {
    return scored.indexWhere(
      (candidate) =>
          (preferredLocal == null ||
              _isLocalSource(candidate.source) == preferredLocal) &&
          _fitsDiversity(
            candidate,
            selected,
            recentQueue,
            tuner,
            strictAlbum: strictAlbum,
            strictArtist: true,
          ),
    );
  }

  _SourceBlend? _sourceBlend(
    List<FlowCandidateScore> scored,
    List<FlowQueueItem> selected,
    int limit,
    double localWeight,
  ) {
    final localAvailable =
        scored.where((item) => _isLocalSource(item.source)).length;
    final externalAvailable = scored.length - localAvailable;
    if (localAvailable == 0 || externalAvailable == 0) return null;

    final selectedLocal =
        selected.where((item) => _isLocalSource(item.source)).length;
    final selectedExternal = selected.length - selectedLocal;
    final minimumFromCapacity = limit - (selectedExternal + externalAvailable);
    final minimumLocal = minimumFromCapacity > selectedLocal
        ? minimumFromCapacity
        : selectedLocal;
    final maximumFromCapacity = selectedLocal + localAvailable;
    final maximumLocal =
        maximumFromCapacity < limit ? maximumFromCapacity : limit;
    if (minimumLocal > maximumLocal) return null;

    final desiredLocal = (limit * localWeight).round();
    return _SourceBlend(
      localTarget: desiredLocal.clamp(minimumLocal, maximumLocal).toInt(),
    );
  }

  bool? _preferredLocalSource(
    _SourceBlend? blend,
    List<FlowQueueItem> selected,
    List<FlowCandidateScore> remaining,
    int limit,
  ) {
    if (blend == null) return null;
    final remainingSlots = limit - selected.length;
    if (remainingSlots <= 0) return null;

    final localSelected =
        selected.where((item) => _isLocalSource(item.source)).length;
    final externalSelected = selected.length - localSelected;
    final localNeeded = blend.localTarget - localSelected;
    final externalNeeded = (limit - blend.localTarget) - externalSelected;
    final hasLocal = remaining.any((item) => _isLocalSource(item.source));
    final hasExternal = remaining.any((item) => !_isLocalSource(item.source));
    if (hasLocal && localNeeded >= remainingSlots) return true;
    if (hasExternal && externalNeeded >= remainingSlots) return false;
    return null;
  }

  FlowCandidateScore _score(
    RecommendationCandidate candidate,
    TasteProfile profile,
    FlowTunerSettings tuner,
    FlowSession session,
    List<MediaItem> recentQueue,
  ) {
    final item = candidate.item;
    final reasons = <String>[candidate.source];
    var score = candidate.sourceScore;

    final artistPreference = profile.artistPreference(item);
    if (artistPreference > 0) {
      score += artistPreference.clamp(0, 8) * .12;
      reasons.add('liked_artist');
    }

    if (profile.isLiked(item)) {
      score += .8 * tuner.familiarity;
      reasons.add('liked_revisit');
    }

    if (!profile.hasPlayed(item)) {
      score += .6 * (1 - tuner.familiarity);
      reasons.add('new_track');
    } else {
      score -= .55 * (1 - tuner.familiarity);
      reasons.add('played_penalty');
    }

    if (profile.wasSkipped(item)) {
      score -= 1.25;
      reasons.add('skipped_track_penalty');
    }
    final skippedArtist = profile.artistSkipScore(item);
    if (skippedArtist > 0) {
      score -= skippedArtist.clamp(0, 4) * .22;
      reasons.add('skip_artist_penalty');
    }

    score -= _recentPlayPenalty(item, profile, tuner, reasons);
    score += _modeBonus(tuner.mode, item, candidate.source, reasons);
    score += _genreBonus(tuner, item, reasons);
    score += _deepCutsBonus(candidate, profile, tuner, reasons);
    score += _stationBonus(session.station, item, candidate.source, reasons);
    score += _sourceExplorationBonus(candidate.source, tuner);
    score -= _recentQueuePenalty(item, recentQueue, reasons);

    if (session.skipStreak >= 2) {
      score -= .3 * (1 - tuner.familiarity);
      reasons.add('skip_streak_conservative');
    }

    score += _sessionJitter(session.id, item, tuner.variety);
    return FlowCandidateScore(
      item: item,
      source: candidate.source,
      score: score,
      reasonCodes: reasons,
    );
  }

  double _recentPlayPenalty(
    MediaItem item,
    TasteProfile profile,
    FlowTunerSettings tuner,
    List<String> reasons,
  ) {
    final lastPlayedAt = profile.lastPlayedAt(item);
    if (lastPlayedAt == null) return 0;
    final age = _now().difference(lastPlayedAt);
    if (age >= const Duration(days: 14)) return 0;
    final freshness = 1 - (age.inHours.clamp(0, 336) / 336);
    final familiarityRelief =
        profile.isLiked(item) ? tuner.familiarity * .7 : 0;
    final penalty = freshness * (1.35 - familiarityRelief);
    reasons.add('recent_play_cooldown');
    return penalty.clamp(.15, 1.35).toDouble();
  }

  double _modeBonus(
    FlowMode mode,
    MediaItem item,
    String source,
    List<String> reasons,
  ) {
    if (mode == FlowMode.auto) return 0;
    final text = _songText(item);
    final terms = switch (mode) {
      FlowMode.chill => const [
          'chill',
          'lofi',
          'ambient',
          'acoustic',
          'calm',
          'soft'
        ],
      FlowMode.energy => const [
          'dance',
          'party',
          'club',
          'rock',
          'energy',
          'workout',
          'edm'
        ],
      FlowMode.melancholy => const [
          'sad',
          'slow',
          'rain',
          'dark',
          'melancholy',
          'emotional'
        ],
      FlowMode.discover => const <String>[],
      FlowMode.auto => const <String>[],
    };
    if (mode == FlowMode.discover) {
      if (!source.startsWith('local')) {
        reasons.add('discover_boost');
        return .5;
      }
      return -.18;
    }
    if (_containsAnyTerm(text, terms)) {
      reasons.add('${mode.name}_match');
      return .55;
    }
    if (source == 'mode_search') {
      reasons.add('${mode.name}_search');
      return .32;
    }
    reasons.add('${mode.name}_mismatch');
    return -.14;
  }

  double _genreBonus(
    FlowTunerSettings tuner,
    MediaItem item,
    List<String> reasons,
  ) {
    if (tuner.genres.isEmpty) return 0;
    final text = _songText(item);
    if (_containsAnyTerm(text, tuner.genres)) {
      reasons.add('genre_match');
      return .42;
    }
    reasons.add('genre_mismatch');
    return -.22;
  }

  double _deepCutsBonus(
    RecommendationCandidate candidate,
    TasteProfile profile,
    FlowTunerSettings tuner,
    List<String> reasons,
  ) {
    final rank = candidate.sourceRank.clamp(0, 12) / 12;
    if (tuner.deepCuts >= .5) {
      final depth = (tuner.deepCuts - .5) * 2;
      var bonus = rank * .5 * depth;
      if (!profile.hasPlayed(candidate.item) &&
          profile.artistPreference(candidate.item) == 0) {
        bonus += .2 * depth;
      }
      if (bonus > .05) reasons.add('deep_cut_boost');
      return bonus;
    }
    final hits = (.5 - tuner.deepCuts) * 2;
    final bonus = (1 - rank) * .35 * hits;
    if (bonus > .05) reasons.add('hit_rank_boost');
    return bonus;
  }

  double _sourceExplorationBonus(String source, FlowTunerSettings tuner) {
    if (source == 'lastfm') return .2 + ((1 - tuner.familiarity) * .15);
    if (source == 'youtube_radio') return .15;
    if (source == 'youtube_related') return .08;
    if (source == 'explore') return .3 * tuner.variety;
    if (source == 'local_favorite') return .25 * tuner.familiarity;
    if (source == 'local_download') return .18 * tuner.familiarity;
    return 0;
  }

  double _stationBonus(
    FlowStation? station,
    MediaItem item,
    String source,
    List<String> reasons,
  ) {
    if (station == null) return 0;
    var score = 0.0;
    final text = _songText(item);
    final matches = station.normalizedTerms
        .where(
          (term) => RecommendationMediaJson.containsNormalizedTerm(text, term),
        )
        .take(5)
        .length;

    if (matches > 0) {
      score += (.18 * matches) + (.2 * station.confidence);
      reasons.add('station_match');
    }
    if (source == 'station_search') {
      score += .48 + (.22 * station.confidence);
      reasons.add('station_search');
    }
    if (source.startsWith('local') && station.localWeight >= .45) {
      score += .14 * station.localWeight;
      reasons.add('station_local_blend');
    } else if (!source.startsWith('local') && station.externalWeight >= .6) {
      score += .12 * station.externalWeight;
      reasons.add('station_external_blend');
    }

    if (matches == 0 && source == 'station_search') {
      score -= .08;
      reasons.add('weak_station_text_match');
    } else if (matches == 0) {
      score -= source.startsWith('local') ? .38 : .5;
      reasons.add('station_mismatch_penalty');
    }
    return score.clamp(-.55, 1.25).toDouble();
  }

  double _recentQueuePenalty(
    MediaItem item,
    List<MediaItem> recentQueue,
    List<String> reasons,
  ) {
    var penalty = 0.0;
    final artist = _artist(item);
    final album = _album(item);
    for (final recent in recentQueue.take(8)) {
      if (RecommendationMediaJson.sameSong(item, recent)) {
        reasons.add('queue_duplicate_penalty');
        penalty += 2;
      }
      if (artist.isNotEmpty && artist == _artist(recent)) penalty += .32;
      if (album.isNotEmpty && album == _album(recent)) penalty += .22;
    }
    return penalty;
  }

  bool _fitsDiversity(
    FlowCandidateScore candidate,
    List<FlowQueueItem> selected,
    List<MediaItem> recentQueue,
    FlowTunerSettings tuner, {
    required bool strictAlbum,
    required bool strictArtist,
  }) {
    final context = <MediaItem>[
      ...selected.reversed.map((item) => item.item),
      ...recentQueue,
    ];
    final artist = _artist(candidate.item);
    final album = _album(candidate.item);
    if (strictArtist &&
        artist.isNotEmpty &&
        context.take(2).any((item) => _artist(item) == artist)) {
      return false;
    }
    if (strictAlbum &&
        album.isNotEmpty &&
        context.take(5).any((item) => _album(item) == album)) {
      return false;
    }
    if (tuner.variety >= .55 && selected.length >= 3) {
      final recentSources =
          selected.reversed.take(3).map((item) => item.source);
      if (recentSources.every((source) => source == candidate.source)) {
        return false;
      }
    }
    return true;
  }

  double _mmrScore(
    FlowCandidateScore candidate,
    List<FlowQueueItem> selected,
    List<MediaItem> recentQueue,
    double diversityWeight,
  ) {
    var similarity = 0.0;
    for (final item in [
      ...selected.map((item) => item.item),
      ...recentQueue.take(6),
    ]) {
      final current = _similarity(candidate.item, item);
      if (current > similarity) similarity = current;
    }
    return candidate.score - (diversityWeight * similarity);
  }

  double _similarity(MediaItem a, MediaItem b) {
    if (RecommendationMediaJson.sameSong(a, b)) return 1;
    var score = 0.0;
    if (_artist(a).isNotEmpty && _artist(a) == _artist(b)) score += .75;
    if (_album(a).isNotEmpty && _album(a) == _album(b)) score += .35;
    return score.clamp(0.0, 1.0).toDouble();
  }

  double _diversityWeight(FlowTunerSettings tuner) {
    if (tuner.mode == FlowMode.discover) return .45;
    if (tuner.familiarity > .75 && tuner.variety < .35) return .1;
    return .22 + (.2 * tuner.variety);
  }

  double _sessionJitter(String sessionId, MediaItem item, double variety) {
    var hash = 2166136261;
    for (final codeUnit in '$sessionId|${_songKey(item)}'.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    final centered = (hash % 1000) / 999 - .5;
    return centered * (.05 + (.12 * variety));
  }

  String _songKey(MediaItem item) {
    final key = RecommendationMediaJson.normalizedSongKey(item);
    return key.isEmpty ? item.id : key;
  }

  String _songText(MediaItem item) {
    return RecommendationMediaJson.normalizedText(
      '${item.title} ${item.artist ?? ''} ${item.album ?? ''}',
    );
  }

  String _artist(MediaItem item) {
    return RecommendationMediaJson.normalizedPrimaryArtist(item);
  }

  String _album(MediaItem item) {
    return RecommendationMediaJson.normalizedText(item.album ?? '');
  }

  bool _containsAnyTerm(String text, Iterable<String> terms) {
    return terms.any(
      (term) => RecommendationMediaJson.containsNormalizedTerm(text, term),
    );
  }
}

class _SourceBlend {
  const _SourceBlend({required this.localTarget});

  final int localTarget;
}

bool _isLocalSource(String source) {
  return source.startsWith('local') || source == 'explore';
}
