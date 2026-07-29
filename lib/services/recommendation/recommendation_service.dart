import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/media_Item_builder.dart';
import '../../models/quick_picks.dart';
import '../../models/recommendation_item.dart';
import '../library/blacklist_service.dart';
import 'candidate_provider.dart';
import 'feedback_tracker.dart';
import 'ranker.dart';
import 'taste_profile_service.dart';

class RecommendationService extends GetxService {
  static const _cacheKey = 'forYou';
  static const _dismissedKey = 'dismissedSongIds';
  static const _dismissedSongKeysKey = 'dismissedSongKeys';
  static const _cacheMaxAge = Duration(hours: 6);
  static const _cacheFeedbackRevisionKey = 'feedbackRevision';

  RecommendationService({
    TasteProfileService? tasteProfileService,
    CandidateProvider? candidateProvider,
    FeedbackTracker? feedbackTracker,
    BlacklistService? blacklistService,
    RecommendationRanker? ranker,
  })  : _tasteProfileService =
            tasteProfileService ?? Get.find<TasteProfileService>(),
        _candidateProvider = candidateProvider ?? Get.find<CandidateProvider>(),
        _feedbackTracker = feedbackTracker ?? Get.find<FeedbackTracker>(),
        _blacklistService = blacklistService ?? Get.find<BlacklistService>(),
        _ranker = ranker ?? RecommendationRanker();

  final TasteProfileService _tasteProfileService;
  final CandidateProvider _candidateProvider;
  final FeedbackTracker _feedbackTracker;
  final BlacklistService _blacklistService;
  final RecommendationRanker _ranker;

  final forYou = QuickPicks([], title: 'For You').obs;
  final isRefreshing = false.obs;
  bool _forceRefreshQueued = false;
  int _mutationRevision = 0;

  Box get _cacheBox => Hive.box('RecommendationCache');
  Box get _prefsBox => Hive.box('AppPrefs');
  Box get _settingsBox => Hive.box('RecommendationSettings');

  bool get isEnabled => _prefsBox.get('recommendationsEnabled') ?? true;

  @override
  void onInit() {
    loadCachedForYou();
    super.onInit();
  }

  Future<void> loadCachedForYou() async {
    final items = _readUsableCachedItems();
    if (items == null) return;
    forYou.value = QuickPicks(items, title: 'For You');
  }

  Future<void> refreshForYou({bool force = false}) async {
    if (!isEnabled) return;
    if (isRefreshing.isTrue) {
      if (force) _forceRefreshQueued = true;
      return;
    }
    if (!force && _isCacheFresh()) {
      await loadCachedForYou();
      return;
    }

    final mutationRevision = _mutationRevision;
    final feedbackRevision = _feedbackTracker.feedbackRevision;
    isRefreshing.value = true;
    try {
      final profile = await _tasteProfileService.buildProfile();
      if (_mutationRevision != mutationRevision) return;
      if (_feedbackTracker.feedbackRevision != feedbackRevision) {
        _forceRefreshQueued = true;
        return;
      }
      if (!profile.hasSignals) {
        forYou.value = QuickPicks([], title: 'For You');
        await _cacheBox.delete(_cacheKey);
        return;
      }

      final candidates = await _candidateProvider.getCandidates(profile);
      if (_mutationRevision != mutationRevision) return;
      if (_feedbackTracker.feedbackRevision != feedbackRevision) {
        _forceRefreshQueued = true;
        return;
      }
      if (candidates.isEmpty) {
        _retainUsableCachedRecommendations();
        return;
      }

      final ranked = _annotateRecommendations(
        _ranker.rank(
          candidates,
          profile,
          isBlocked: _blacklistService.isBlocked,
        ),
        candidates,
      );
      final usable = _filterUsable(ranked);
      if (_mutationRevision != mutationRevision) return;
      if (_feedbackTracker.feedbackRevision != feedbackRevision) {
        _forceRefreshQueued = true;
        return;
      }

      forYou.value = QuickPicks(usable, title: 'For You');
      await _writeCache(usable, feedbackRevision: feedbackRevision);
    } finally {
      isRefreshing.value = false;
      if (_forceRefreshQueued) {
        _forceRefreshQueued = false;
        await refreshForYou(force: true);
      }
    }
  }

  Future<void> dismissTrack(MediaItem item) async {
    _mutationRevision++;
    final dismissed =
        Set<String>.from(_cacheBox.get(_dismissedKey) ?? const []);
    final dismissedKeys =
        Set<String>.from(_cacheBox.get(_dismissedSongKeysKey) ?? const []);
    dismissed.add(item.id);
    dismissedKeys.add(RecommendationMediaJson.normalizedSongKey(item));
    await _cacheBox.put(_dismissedKey, _bounded(dismissed));
    await _cacheBox.put(_dismissedSongKeysKey, _bounded(dismissedKeys));
    await _feedbackTracker.recordDismissRecommendation(item);
    forYou.value = QuickPicks(
      forYou.value.songList
          .where((song) => !RecommendationMediaJson.sameSong(song, item))
          .toList(),
      title: 'For You',
    );
    await _writeCache(
      forYou.value.songList,
      feedbackRevision: _feedbackTracker.feedbackRevision,
    );
  }

  Future<void> recordRecommendationClick(MediaItem item) {
    return _feedbackTracker.recordRecommendationClick(item);
  }

  Future<void> clearRecommendationData() async {
    _mutationRevision++;
    await _feedbackTracker.clearHistory();
    await Hive.box('TasteProfile').clear();
    await _cacheBox.clear();
    forYou.value = QuickPicks([], title: 'For You');
  }

  bool _isCacheFresh() {
    final raw = _cacheBox.get(_cacheKey);
    if (raw is! Map) return false;
    final updatedAt = raw['updatedAt'];
    if (updatedAt is! int) return false;
    final cachedFeedbackRevision = raw[_cacheFeedbackRevisionKey];
    final currentFeedbackRevision = _feedbackTracker.feedbackRevision;
    if (currentFeedbackRevision > 0 &&
        (cachedFeedbackRevision is! int ||
            cachedFeedbackRevision < currentFeedbackRevision)) {
      return false;
    }
    final lastFeedbackAt = _settingsBox
        .get(FeedbackTracker.lastMeaningfulFeedbackAtKey, defaultValue: 0);
    if (lastFeedbackAt is int && lastFeedbackAt > updatedAt) return false;
    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(updatedAt));
    return age < _cacheMaxAge;
  }

  List<String> _bounded(Set<String> values) {
    final items = values.toList();
    if (items.length <= 2000) return items;
    return items.sublist(items.length - 2000);
  }

  List<MediaItem>? _readUsableCachedItems() {
    final raw = _cacheBox.get(_cacheKey);
    if (raw is! Map) return null;
    final songs = raw['songs'];
    if (songs is! List) return null;
    final items = <MediaItem>[];
    for (final song in songs) {
      try {
        var item = MediaItemBuilder.fromJson(song);
        if (song is Map) {
          final source = song['recommendationSource'];
          final score = song['recommendationScore'];
          final reasonCodes = song['recommendationReasonCodes'];
          if (source is String || score is num || reasonCodes is List) {
            item = item.copyWith(extras: {
              ...?item.extras,
              if (source is String) 'recommendationSource': source,
              if (score is num) 'recommendationScore': score.toDouble(),
              if (reasonCodes is List)
                'recommendationReasonCodes':
                    reasonCodes.map((reason) => reason.toString()).toList(),
            });
          }
        }
        items.add(item);
      } catch (_) {}
    }
    return _filterUsable(items);
  }

  List<MediaItem> _filterUsable(Iterable<MediaItem> items) {
    final dismissedIds =
        Set<String>.from(_cacheBox.get(_dismissedKey) ?? const []);
    final dismissedKeys =
        Set<String>.from(_cacheBox.get(_dismissedSongKeysKey) ?? const []);
    return items.where((item) {
      return !dismissedIds.contains(item.id) &&
          !dismissedKeys
              .contains(RecommendationMediaJson.normalizedSongKey(item)) &&
          !_blacklistService.isBlocked(item);
    }).toList();
  }

  void _retainUsableCachedRecommendations() {
    final cached = _readUsableCachedItems();
    if (cached != null && cached.isNotEmpty) {
      forYou.value = QuickPicks(cached, title: 'For You');
      return;
    }

    final current = _filterUsable(forYou.value.songList);
    forYou.value = QuickPicks(current, title: 'For You');
  }

  List<MediaItem> _annotateRecommendations(
    List<MediaItem> ranked,
    List<RecommendationCandidate> candidates,
  ) {
    final strongestByKey = <String, RecommendationCandidate>{};
    for (final candidate in candidates) {
      final key = _candidateKey(candidate.item);
      final existing = strongestByKey[key];
      if (existing == null || candidate.sourceScore > existing.sourceScore) {
        strongestByKey[key] = candidate;
      }
    }

    return ranked.map((item) {
      final candidate = strongestByKey[_candidateKey(item)];
      if (candidate == null) return item;
      return item.copyWith(extras: {
        ...?item.extras,
        if (item.extras?['recommendationSource'] is! String)
          'recommendationSource': candidate.source,
        if (item.extras?['recommendationScore'] is! num)
          'recommendationScore': candidate.sourceScore,
      });
    }).toList();
  }

  String _candidateKey(MediaItem item) {
    final normalized = RecommendationMediaJson.normalizedSongKey(item);
    return normalized.isEmpty ? item.id : normalized;
  }

  Future<void> _writeCache(
    Iterable<MediaItem> items, {
    required int feedbackRevision,
  }) {
    return _cacheBox.put(_cacheKey, {
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      _cacheFeedbackRevisionKey: feedbackRevision,
      'songs': items.map(RecommendationMediaJson.fromMediaItem).toList(),
    });
  }
}
