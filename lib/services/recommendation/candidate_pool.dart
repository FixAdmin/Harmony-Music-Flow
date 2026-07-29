import '../../models/recommendation_item.dart';

class CandidateBucket {
  const CandidateBucket({
    required this.items,
    required this.quota,
  });

  final List<RecommendationCandidate> items;
  final int quota;
}

class CandidatePool {
  static List<RecommendationCandidate> roundRobin(
    List<List<RecommendationCandidate>> pools, {
    required int limit,
    int rotation = 0,
  }) {
    if (limit <= 0 || pools.isEmpty) return [];
    final activePools = pools.where((pool) => pool.isNotEmpty).toList();
    if (activePools.isEmpty) return [];
    final orderedPools = _rotated(activePools, rotation);
    final cursors = List<int>.filled(orderedPools.length, 0);
    final result = <RecommendationCandidate>[];
    final seen = <String>{};
    final strongest = _strongestByKey(orderedPools.expand((pool) => pool));

    while (result.length < limit) {
      var progressed = false;
      for (var poolIndex = 0;
          poolIndex < orderedPools.length && result.length < limit;
          poolIndex++) {
        final pool = orderedPools[poolIndex];
        while (cursors[poolIndex] < pool.length) {
          final candidate = pool[cursors[poolIndex]++];
          final key = _key(candidate);
          if (!identical(candidate, strongest[key])) continue;
          if (!seen.add(key)) continue;
          result.add(candidate);
          progressed = true;
          break;
        }
      }
      if (!progressed) break;
    }
    return result;
  }

  static List<RecommendationCandidate> mergeBuckets(
    List<CandidateBucket> buckets, {
    required int limit,
    int rotation = 0,
  }) {
    if (limit <= 0 || buckets.isEmpty) return [];
    final active = buckets
        .where((bucket) => bucket.quota > 0 && bucket.items.isNotEmpty)
        .toList();
    if (active.isEmpty) return [];
    final ordered = _rotated(active, rotation);
    final cursors = List<int>.filled(ordered.length, 0);
    final used = List<int>.filled(ordered.length, 0);
    final seen = <String>{};
    final result = <RecommendationCandidate>[];
    final strongest = _strongestByKey(
      ordered.expand((bucket) => bucket.items),
    );

    while (result.length < limit) {
      var progressed = false;
      for (var index = 0;
          index < ordered.length && result.length < limit;
          index++) {
        final bucket = ordered[index];
        if (used[index] >= bucket.quota) continue;
        while (cursors[index] < bucket.items.length) {
          final candidate = bucket.items[cursors[index]++];
          final key = _key(candidate);
          if (!identical(candidate, strongest[key])) continue;
          if (!seen.add(key)) continue;
          result.add(candidate);
          used[index]++;
          progressed = true;
          break;
        }
      }
      if (!progressed) break;
    }

    if (result.length >= limit) return result;
    while (result.length < limit) {
      var progressed = false;
      for (var index = 0;
          index < ordered.length && result.length < limit;
          index++) {
        final items = ordered[index].items;
        while (cursors[index] < items.length) {
          final candidate = items[cursors[index]++];
          final key = _key(candidate);
          if (!identical(candidate, strongest[key])) continue;
          if (!seen.add(key)) continue;
          result.add(candidate);
          progressed = true;
          break;
        }
      }
      if (!progressed) break;
    }
    return result.take(limit).toList();
  }

  static List<T> _rotated<T>(List<T> values, int rotation) {
    if (values.length < 2) return values;
    final offset = rotation.abs() % values.length;
    if (offset == 0) return values;
    return [...values.skip(offset), ...values.take(offset)];
  }

  static String _key(RecommendationCandidate candidate) {
    final normalized =
        RecommendationMediaJson.normalizedSongKey(candidate.item);
    return normalized.isEmpty ? candidate.item.id : normalized;
  }

  static Map<String, RecommendationCandidate> _strongestByKey(
    Iterable<RecommendationCandidate> candidates,
  ) {
    final strongest = <String, RecommendationCandidate>{};
    for (final candidate in candidates) {
      final key = _key(candidate);
      final existing = strongest[key];
      if (existing == null || candidate.sourceScore > existing.sourceScore) {
        strongest[key] = candidate;
      }
    }
    return strongest;
  }
}
