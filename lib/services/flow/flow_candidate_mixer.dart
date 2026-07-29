import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/flow/flow_models.dart';
import '../../models/flow/flow_station.dart';
import '../../models/media_Item_builder.dart';
import '../../models/recommendation_item.dart';
import '../../models/taste_profile.dart';
import '../recommendation/candidate_pool.dart';
import '../recommendation/candidate_provider.dart';

class FlowCandidateMixer extends GetxService {
  FlowCandidateMixer({
    CandidateProvider? candidateProvider,
    Duration providerTimeout = const Duration(seconds: 6),
  })  : _candidateProvider = candidateProvider ?? Get.find<CandidateProvider>(),
        _providerTimeout = providerTimeout;

  final CandidateProvider _candidateProvider;
  final Duration _providerTimeout;

  Future<List<RecommendationCandidate>> getCandidates(
    TasteProfile profile,
    FlowSession session,
    FlowTunerSettings tuner, {
    int limit = 80,
    MediaItem? currentSong,
  }) async {
    final station = session.station;
    final seeds = _seeds(profile, currentSong, station);
    final quotas = _sourceQuotas(limit, tuner, station);
    final rotation = session.id.hashCode;
    final radioSeeds = seeds.take(4).toList();
    final relatedSeeds = seeds.take(5).toList();
    final lastFmSeeds = seeds.take(3).toList();

    final searchFuture = _searchCandidates(
      station,
      tuner,
      limit: quotas.search * 2,
      rotation: rotation,
    );
    final radioFuture = Future.wait(
      radioSeeds.map(
        (seed) => _providerCandidates(
          () => _candidateProvider.getYouTubeRadioCandidates(
            seed,
            limit: _perSeedLimit(
              quotas.radio,
              radioSeeds.length,
              max: 12,
            ),
          ),
        ),
      ),
    );
    final relatedFuture = Future.wait(
      relatedSeeds.map(
        (seed) => _providerCandidates(
          () => _candidateProvider.getYouTubeRelatedCandidates(
            seed,
            limit: _perSeedLimit(
              quotas.related,
              relatedSeeds.length,
              max: 10,
            ),
          ),
        ),
      ),
    );
    final lastFmFuture = Future.wait(
      lastFmSeeds.map(
        (seed) => _providerCandidates(
          () => _candidateProvider.getLastFmCandidates(
            seed,
            limit: _perSeedLimit(
              quotas.lastFm,
              lastFmSeeds.length,
              max: 6,
            ),
          ),
        ),
      ),
    );
    final localFuture = _localCandidates(
      station: station,
      tuner: tuner,
      limit: quotas.local * 2,
      rotation: rotation,
    );

    final search = await searchFuture;
    final radio = CandidatePool.roundRobin(
      await radioFuture,
      limit: quotas.radio * 2,
      rotation: rotation,
    );
    final related = CandidatePool.roundRobin(
      await relatedFuture,
      limit: quotas.related * 2,
      rotation: rotation + 1,
    );
    final lastFm = CandidatePool.roundRobin(
      await lastFmFuture,
      limit: quotas.lastFm * 2,
      rotation: rotation + 2,
    );
    final local = await localFuture;
    final exploration = _explorationCandidates(
      profile,
      station: station,
      tuner: tuner,
      limit: quotas.exploration * 2,
      rotation: rotation,
    );

    return CandidatePool.mergeBuckets([
      CandidateBucket(items: search, quota: quotas.search),
      CandidateBucket(items: radio, quota: quotas.radio),
      CandidateBucket(items: related, quota: quotas.related),
      CandidateBucket(items: lastFm, quota: quotas.lastFm),
      CandidateBucket(items: local, quota: quotas.local),
      CandidateBucket(items: exploration, quota: quotas.exploration),
    ], limit: limit, rotation: rotation);
  }

  List<MediaItem> _seeds(
    TasteProfile profile,
    MediaItem? currentSong,
    FlowStation? station,
  ) {
    final seeds = <MediaItem>[];
    final seen = <String>{};

    bool add(MediaItem item) {
      final key = RecommendationMediaJson.normalizedSongKey(item);
      if (item.id.trim().isEmpty || !seen.add(key)) return false;
      seeds.add(item);
      return true;
    }

    if (station != null) {
      if (currentSong != null && _matchesStation(currentSong, station)) {
        add(currentSong);
      }
      for (final seed in profile.recentSeeds) {
        if (!_matchesStation(seed, station)) continue;
        add(seed);
        if (seeds.length >= 5) break;
      }
      return seeds;
    }

    if (currentSong != null) add(currentSong);
    for (final seed in profile.recentSeeds) {
      add(seed);
      if (seeds.length >= 8) break;
    }
    return seeds;
  }

  Future<List<RecommendationCandidate>> _searchCandidates(
    FlowStation? station,
    FlowTunerSettings tuner, {
    required int limit,
    required int rotation,
  }) async {
    if (limit <= 0) return [];
    final queries = station == null
        ? _modeQueries(tuner)
        : station.searchQueries
            .where((query) => query.trim().isNotEmpty)
            .toList();
    if (queries.isEmpty) return [];
    final orderedQueries = _rotated(queries, rotation).take(4).toList();
    final perQuery =
        (limit / orderedQueries.length).ceil().clamp(4, 12).toInt();
    final futures = orderedQueries.map(
      (query) => _providerCandidates(
        () => _candidateProvider.getSearchCandidates(
          query,
          limit: perQuery,
          source: station == null ? 'mode_search' : 'station_search',
          seedId: station?.id ?? tuner.mode.name,
          sourceScore: station == null ? .72 : .72 + (station.confidence * .2),
        ),
      ),
    );
    return CandidatePool.roundRobin(
      await Future.wait(futures),
      limit: limit,
      rotation: rotation,
    );
  }

  List<String> _modeQueries(FlowTunerSettings tuner) {
    final qualifiers = tuner.genres
        .map(RecommendationMediaJson.normalizedText)
        .where((value) => value.isNotEmpty)
        .take(3)
        .join(' ');
    if (tuner.mode == FlowMode.auto && qualifiers.isEmpty) return const [];
    final mode = tuner.mode == FlowMode.auto ? '' : tuner.mode.name;
    final base = '$qualifiers $mode'.trim();
    return [
      '$base music'.trim(),
      '$base songs'.trim(),
    ];
  }

  Future<List<RecommendationCandidate>> _localCandidates({
    required FlowStation? station,
    required FlowTunerSettings tuner,
    required int limit,
    required int rotation,
  }) async {
    if (limit <= 0) return [];
    final perSource = (limit / 3).ceil();
    final favorites = await _boxCandidates(
      'LIBFAV',
      'local_favorite',
      .82,
      station: station,
      tuner: tuner,
      limit: perSource,
    );
    final downloads = await _boxCandidates(
      'SongDownloads',
      'local_download',
      .74,
      station: station,
      tuner: tuner,
      limit: perSource,
    );
    final recent = await _boxCandidates(
      'LIBRP',
      'local_recent',
      .58,
      station: station,
      tuner: tuner,
      limit: perSource,
    );
    return CandidatePool.mergeBuckets([
      CandidateBucket(items: favorites, quota: (limit * .45).ceil()),
      CandidateBucket(items: downloads, quota: (limit * .3).ceil()),
      CandidateBucket(items: recent, quota: (limit * .25).ceil()),
    ], limit: limit, rotation: rotation);
  }

  Future<List<RecommendationCandidate>> _boxCandidates(
    String boxName,
    String source,
    double score, {
    required FlowStation? station,
    required FlowTunerSettings tuner,
    required int limit,
  }) async {
    final box = await Hive.openBox(boxName);
    final candidates = <RecommendationCandidate>[];
    var sourceRank = 0;
    for (final raw in box.values.toList().reversed) {
      if (raw is! Map) continue;
      try {
        final item = MediaItemBuilder.fromJson(raw);
        if (station != null && !_matchesStation(item, station)) continue;
        if (station == null &&
            tuner.genres.isNotEmpty &&
            !_matchesTerms(item, tuner.genres)) {
          continue;
        }
        candidates.add(RecommendationCandidate(
          item: item,
          source: source,
          sourceScore: score,
          sourceRank: sourceRank++,
        ));
        if (candidates.length >= limit) break;
      } catch (_) {}
    }
    return candidates;
  }

  List<RecommendationCandidate> _explorationCandidates(
    TasteProfile profile, {
    required FlowStation? station,
    required FlowTunerSettings tuner,
    required int limit,
    required int rotation,
  }) {
    final matching = profile.recentSeeds.where((seed) {
      if (station != null) return _matchesStation(seed, station);
      if (tuner.genres.isNotEmpty) return _matchesTerms(seed, tuner.genres);
      return true;
    }).toList();
    final rotated = _rotated(matching.reversed.toList(), rotation);
    return rotated.take(limit).toList().asMap().entries.map((entry) {
      final seed = entry.value;
      return RecommendationCandidate(
        item: seed,
        source: station == null ? 'explore' : 'station_local_seed',
        seedId: seed.id,
        sourceScore: station == null ? .45 : .5,
        sourceRank: entry.key,
      );
    }).toList();
  }

  _SourceQuotas _sourceQuotas(
    int limit,
    FlowTunerSettings tuner,
    FlowStation? station,
  ) {
    final weights = <double>[
      station != null
          ? .30 + (station.externalWeight * .08)
          : tuner.mode == FlowMode.auto && tuner.genres.isEmpty
              ? 0
              : .16,
      station == null ? .40 : .25,
      station == null ? .22 : .15,
      .08,
      station == null ? .22 : .10 + (station.localWeight * .18),
      station == null ? .08 : .06,
    ];
    final total = weights.fold<double>(0, (sum, value) => sum + value);
    final quotas =
        weights.map((weight) => (limit * weight / total).floor()).toList();
    var remaining = limit - quotas.fold<int>(0, (sum, value) => sum + value);
    var index = 0;
    while (remaining > 0) {
      quotas[index % quotas.length]++;
      index++;
      remaining--;
    }
    return _SourceQuotas(
      search: quotas[0],
      radio: quotas[1],
      related: quotas[2],
      lastFm: quotas[3],
      local: quotas[4],
      exploration: quotas[5],
    );
  }

  int _perSeedLimit(int quota, int seedCount, {required int max}) {
    if (quota <= 0 || seedCount <= 0) return 0;
    return (quota / seedCount.clamp(1, 5)).ceil().clamp(2, max).toInt();
  }

  Future<List<RecommendationCandidate>> _providerCandidates(
    Future<List<RecommendationCandidate>> Function() load,
  ) async {
    try {
      return await load().timeout(_providerTimeout);
    } catch (_) {
      return const [];
    }
  }

  bool _matchesStation(MediaItem item, FlowStation station) {
    return _matchesTerms(item, station.normalizedTerms);
  }

  bool _matchesTerms(MediaItem item, Iterable<String> terms) {
    final text = RecommendationMediaJson.normalizedText(
      '${item.title} ${item.artist ?? ''} ${item.album ?? ''}',
    );
    return terms.any(
      (term) => RecommendationMediaJson.containsNormalizedTerm(text, term),
    );
  }

  List<T> _rotated<T>(List<T> values, int rotation) {
    if (values.length < 2) return values;
    final offset = rotation.abs() % values.length;
    return [...values.skip(offset), ...values.take(offset)];
  }
}

class _SourceQuotas {
  const _SourceQuotas({
    required this.search,
    required this.radio,
    required this.related,
    required this.lastFm,
    required this.local,
    required this.exploration,
  });

  final int search;
  final int radio;
  final int related;
  final int lastFm;
  final int local;
  final int exploration;
}
