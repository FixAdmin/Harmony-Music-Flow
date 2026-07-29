import 'package:audio_service/audio_service.dart';

import '../../models/recommendation_item.dart';
import '../../models/taste_profile.dart';

class RecommendationRanker {
  List<MediaItem> rank(
    List<RecommendationCandidate> candidates,
    TasteProfile profile, {
    int limit = 24,
    bool Function(MediaItem item)? isBlocked,
  }) {
    final byKey = <String, _ScoredCandidate>{};
    for (final candidate in candidates) {
      final item = candidate.item;
      if (item.title.trim().isEmpty || item.artist?.trim().isEmpty == true) {
        continue;
      }
      if (isBlocked?.call(item) ?? false) continue;
      if (profile.isDismissed(item)) continue;
      if (RecommendationMediaJson.hasNoisyVersionMarker(item)) continue;

      final normalizedKey = RecommendationMediaJson.normalizedSongKey(item);
      final key = normalizedKey.isEmpty ? item.id : normalizedKey;
      final score = _score(candidate, profile);
      final existing = byKey[key];
      if (existing == null || existing.score < score) {
        byKey[key] = _ScoredCandidate(candidate, score);
      }
    }

    final scored = byKey.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final result = <MediaItem>[];
    final artistCounts = <String, int>{};
    final sourceCounts = <String, int>{};
    final sourceCaps = _sourceCaps(scored, limit);
    final deferred = <_ScoredCandidate>[];
    for (final scoredCandidate in scored) {
      final source = scoredCandidate.candidate.source;
      if ((sourceCounts[source] ?? 0) >= (sourceCaps[source] ?? limit)) {
        deferred.add(scoredCandidate);
        continue;
      }
      if (!_tryAdd(scoredCandidate, result, artistCounts)) continue;
      sourceCounts[source] = (sourceCounts[source] ?? 0) + 1;
      if (result.length >= limit) break;
    }
    for (final scoredCandidate in deferred) {
      if (result.length >= limit) break;
      _tryAdd(scoredCandidate, result, artistCounts);
    }
    return result;
  }

  bool _tryAdd(
    _ScoredCandidate scoredCandidate,
    List<MediaItem> result,
    Map<String, int> artistCounts,
  ) {
    final item = scoredCandidate.candidate.item;
    final artist = RecommendationMediaJson.normalizedPrimaryArtist(item);
    final count = artistCounts[artist] ?? 0;
    if (artist.isNotEmpty && count >= 2) return false;
    artistCounts[artist] = count + 1;
    result.add(item.copyWith(extras: {
      ...?item.extras,
      'recommendationSource': scoredCandidate.candidate.source,
      'recommendationScore': scoredCandidate.score,
      'recommendationReasonCodes': [scoredCandidate.candidate.source],
    }));
    return true;
  }

  Map<String, int> _sourceCaps(
    List<_ScoredCandidate> candidates,
    int limit,
  ) {
    final sources = candidates.map((item) => item.candidate.source).toSet();
    if (sources.length < 2) return {for (final source in sources) source: limit};
    return {
      for (final source in sources)
        source: switch (source) {
          'youtube_radio' => (limit * .62).ceil(),
          'youtube_related' => (limit * .38).ceil(),
          'lastfm' => (limit * .22).ceil(),
          _ => (limit * .5).ceil(),
        },
    };
  }

  double _score(RecommendationCandidate candidate, TasteProfile profile) {
    final item = candidate.item;
    var score = candidate.sourceScore;

    final artistPreference = profile.artistPreference(item);
    if (artistPreference > 0) {
      score += artistPreference.clamp(0, 8) * .12;
    }
    if (profile.isLiked(item)) {
      score += .8;
    }
    if (!profile.hasPlayed(item)) {
      score += .45;
    } else {
      final lastPlayedAt = profile.lastPlayedAt(item);
      final recentlyPlayed = lastPlayedAt != null &&
          DateTime.now().difference(lastPlayedAt) < const Duration(days: 14);
      score -= recentlyPlayed ? 1.15 : .65;
    }
    if (profile.wasSkipped(item)) {
      score -= 1.1;
    }
    final skippedArtistScore = profile.artistSkipScore(item);
    if (skippedArtistScore > 0) {
      score -= skippedArtistScore.clamp(0, 4) * .2;
    }
    if (candidate.source == 'lastfm') {
      score += .2;
    }
    if (candidate.source == 'youtube_radio') {
      score += .15;
    }
    score -= candidate.sourceRank.clamp(0, 20) * .005;
    return score;
  }
}

class _ScoredCandidate {
  _ScoredCandidate(this.candidate, this.score);

  final RecommendationCandidate candidate;
  final double score;
}
