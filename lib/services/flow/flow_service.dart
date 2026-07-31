import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/flow/flow_models.dart';
import '../../models/flow/flow_station.dart';
import '../../models/recommendation_item.dart';
import '../../models/taste_profile.dart';
import '../library/blacklist_service.dart';
import '../recommendation/feedback_tracker.dart';
import '../recommendation/taste_profile_service.dart';
import 'flow_candidate_mixer.dart';
import 'flow_debug_logger.dart';
import 'flow_feedback_policy.dart';
import 'flow_queue_planner.dart';
import 'flow_tuner.dart';

class FlowService extends GetxService {
  FlowService({
    FlowTuner? tuner,
    TasteProfileService? tasteProfileService,
    FlowCandidateMixer? candidateMixer,
    FlowQueuePlanner? queuePlanner,
    BlacklistService? blacklistService,
    FlowFeedbackPolicy? feedbackPolicy,
    FlowDebugLogger? debugLogger,
    FeedbackTracker? feedbackTracker,
  })  : _tuner = tuner ?? Get.find<FlowTuner>(),
        _tasteProfileService =
            tasteProfileService ?? Get.find<TasteProfileService>(),
        _candidateMixer = candidateMixer ?? Get.find<FlowCandidateMixer>(),
        _queuePlanner = queuePlanner ?? Get.find<FlowQueuePlanner>(),
        _blacklistService = blacklistService ?? Get.find<BlacklistService>(),
        _feedbackPolicy = feedbackPolicy ?? Get.find<FlowFeedbackPolicy>(),
        _debugLogger = debugLogger ?? Get.find<FlowDebugLogger>(),
        _feedbackTracker = feedbackTracker ?? Get.find<FeedbackTracker>();

  final FlowTuner _tuner;
  final TasteProfileService _tasteProfileService;
  final FlowCandidateMixer _candidateMixer;
  final FlowQueuePlanner _queuePlanner;
  final BlacklistService _blacklistService;
  final FlowFeedbackPolicy _feedbackPolicy;
  final FlowDebugLogger _debugLogger;
  final FeedbackTracker _feedbackTracker;

  final isActive = false.obs;
  final isRefilling = false.obs;
  final session = Rxn<FlowSession>();

  int _generation = 0;
  int _activePlans = 0;
  bool _refillInProgress = false;

  Box get _sessionBox => Hive.box('FlowSessions');
  Box get _queueBox => Hive.box('FlowQueueState');
  Box get _prefsBox => Hive.box('AppPrefs');

  bool get isEnabled => _prefsBox.get('flowEnabled') ?? true;

  @override
  void onInit() {
    _restorePersistedSession();
    super.onInit();
  }

  Future<List<MediaItem>> start({
    MediaItem? seed,
    FlowMode mode = FlowMode.auto,
    FlowStation? station,
  }) async {
    if (!isEnabled) return [];
    final generation = ++_generation;
    final previousSession = session.value;
    final previousActive = isActive.value;
    final previousTuner = _tuner.current.value;
    try {
      final tuner = station == null
          ? await _settingsForMode(mode)
          : await _settingsForStation(station);
      if (generation != _generation) return [];

      final newSession = FlowSession.start(
        tuner: tuner,
        seedSongIds: seed == null ? const [] : [seed.id],
        station: station,
      );
      session.value = newSession;
      isActive.value = true;
      await _sessionBox.put('current', newSession.toJson());
      if (!_isCurrent(generation, newSession.id)) return [];
      return await _planQueue(
        expectedSession: newSession,
        generation: generation,
        seed: seed,
        currentQueue: seed == null ? const [] : [seed],
        currentIndex: seed == null ? -1 : 0,
      );
    } catch (error, stackTrace) {
      if (generation == _generation) {
        session.value = previousSession;
        isActive.value = previousActive;
        _tuner.restoreSettings(previousTuner);
        try {
          await _tuner.applySettings(previousTuner);
          if (previousSession == null) {
            await _sessionBox.delete('current');
          } else {
            await _sessionBox.put('current', previousSession.toJson());
          }
        } catch (_) {
          _tuner.restoreSettings(previousTuner);
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> stop() async {
    _generation++;
    _refillInProgress = false;
    final current = session.value;
    isActive.value = false;
    if (current != null) {
      final stopped = current.copyWith(isActive: false);
      session.value = stopped;
      await _sessionBox.put('current', stopped.toJson());
    }
  }

  Future<void> restoreActiveSession(FlowSession snapshot) async {
    final generation = ++_generation;
    _refillInProgress = false;
    final restored = snapshot.copyWith(isActive: true);
    await _tuner.applySettings(restored.tuner);
    if (generation != _generation) return;
    session.value = restored;
    isActive.value = true;
    await _sessionBox.put('current', restored.toJson());
  }

  Future<List<MediaItem>> refillIfNeeded(
    List<MediaItem> currentQueue,
    int currentIndex, {
    MediaItem? currentSong,
  }) async {
    if (!isEnabled ||
        !isActive.value ||
        _refillInProgress ||
        _activePlans > 0) {
      return [];
    }
    final remaining = currentQueue.length - currentIndex - 1;
    if (remaining >= 4) return [];
    return replan(
      currentQueue,
      currentIndex,
      currentSong: currentSong,
    );
  }

  Future<List<MediaItem>> replan(
    List<MediaItem> currentQueue,
    int currentIndex, {
    MediaItem? currentSong,
  }) async {
    final currentSession = session.value;
    if (!isEnabled ||
        !isActive.value ||
        currentSession == null ||
        _refillInProgress ||
        _activePlans > 0) {
      return [];
    }
    _refillInProgress = true;
    final generation = _generation;
    try {
      return await _planQueue(
        expectedSession: currentSession,
        generation: generation,
        seed: currentSong,
        currentQueue: currentQueue,
        currentIndex: currentIndex,
      );
    } finally {
      _refillInProgress = false;
    }
  }

  Future<void> updateTuner(FlowTunerSettings tuner) async {
    final current = session.value;
    if (current == null || !current.isActive) return;
    final generation = _generation;
    await _tuner.applySettings(tuner);
    if (!_isCurrent(generation, current.id)) return;
    final updated = current.copyWith(tuner: tuner);
    session.value = updated;
    await _sessionBox.put('current', updated.toJson());
  }

  Future<void> onFeedback(
    FlowFeedbackAction action,
    MediaItem song, {
    String? artist,
  }) async {
    final generation = _generation;
    final current = session.value;
    final sessionId = current?.id;
    switch (action) {
      case FlowFeedbackAction.blockTrack:
        await _blacklistService.blockTrack(song, reason: 'flow');
        await _feedbackTracker.recordFlowBlockTrack(
          song,
          sessionId: sessionId,
        );
        break;
      case FlowFeedbackAction.blockArtist:
        await _blacklistService.blockArtist(
          artist ?? song.artist ?? '',
          reason: 'flow',
        );
        await _feedbackTracker.recordFlowBlockArtist(
          song,
          sessionId: sessionId,
        );
        break;
      case FlowFeedbackAction.playLessLikeThis:
        await _feedbackTracker.recordFlowPlayLessLikeThis(
          song,
          sessionId: sessionId,
        );
        break;
      case FlowFeedbackAction.notNow:
        await _feedbackTracker.recordDismissRecommendation(song);
        break;
      case FlowFeedbackAction.moreLikeThis:
        await _feedbackTracker.recordFlowMoreLikeThis(
          song,
          sessionId: sessionId,
        );
        break;
      case FlowFeedbackAction.like:
      case FlowFeedbackAction.completion:
      case FlowFeedbackAction.earlySkip:
        break;
    }

    if (current == null ||
        sessionId == null ||
        !_isCurrent(generation, sessionId)) {
      return;
    }
    final nextSkipStreak = _feedbackPolicy.increasesSkipStreak(action)
        ? current.skipStreak + 1
        : _feedbackPolicy.clearsSkipStreak(action)
            ? 0
            : current.skipStreak;
    final nextSeedIds = [...current.seedSongIds];
    if (action == FlowFeedbackAction.moreLikeThis ||
        action == FlowFeedbackAction.like ||
        action == FlowFeedbackAction.completion) {
      nextSeedIds.remove(song.id);
      nextSeedIds.insert(0, song.id);
    } else if (action == FlowFeedbackAction.playLessLikeThis ||
        action == FlowFeedbackAction.blockTrack ||
        action == FlowFeedbackAction.earlySkip) {
      nextSeedIds.remove(song.id);
    }
    final next = current.copyWith(
      skipStreak: nextSkipStreak,
      seedSongIds: nextSeedIds.take(12).toList(),
    );
    session.value = next;
    await _sessionBox.put('current', next.toJson());
    if (!_isCurrent(generation, sessionId)) return;
    await _recordFeedback(action, song, sessionId);
  }

  Future<void> undoTrackBlock(
    MediaItem song, {
    bool restoreSeed = true,
  }) async {
    await _blacklistService.unblockTrack(_blacklistService.trackKey(song));
    final current = session.value;
    if (!restoreSeed || current == null || !current.isActive) return;
    final generation = _generation;
    final seedIds = [
      song.id,
      ...current.seedSongIds.where((id) => id != song.id),
    ].take(12).toList();
    if (!_isCurrent(generation, current.id)) return;
    final restored = current.copyWith(seedSongIds: seedIds);
    session.value = restored;
    await _sessionBox.put('current', restored.toJson());
  }

  Future<List<MediaItem>> planFallbackCandidates({
    required List<RecommendationCandidate> candidates,
    required List<MediaItem> currentQueue,
    required int currentIndex,
    MediaItem? currentSong,
  }) async {
    final currentSession = session.value;
    if (!isEnabled || !isActive.value || currentSession == null) {
      return [];
    }

    final generation = _generation;
    _beginPlan();
    try {
      final profile = await _tasteProfileService.buildProfile();
      if (!_isCurrent(generation, currentSession.id)) return [];
      return await _planCandidates(
        candidates: candidates,
        profile: profile,
        expectedSession: currentSession,
        generation: generation,
        currentQueue: currentQueue,
        currentIndex: currentIndex,
        currentSong: currentSong,
      );
    } finally {
      _endPlan();
    }
  }

  Future<void> clearFlowData() async {
    _generation++;
    _refillInProgress = false;
    await _sessionBox.clear();
    await _queueBox.clear();
    await Hive.box('FlowStats').clear();
    await _debugLogger.clear();
    session.value = null;
    isActive.value = false;
  }

  Future<List<MediaItem>> _planQueue({
    required FlowSession expectedSession,
    required int generation,
    required List<MediaItem> currentQueue,
    required int currentIndex,
    MediaItem? seed,
  }) async {
    _beginPlan();
    try {
      final profile = await _tasteProfileService.buildProfile();
      if (!_isCurrent(generation, expectedSession.id)) return [];
      final candidates = await _candidateMixer.getCandidates(
        profile,
        expectedSession,
        expectedSession.tuner,
        currentSong: seed,
      );
      if (!_isCurrent(generation, expectedSession.id)) return [];
      return await _planCandidates(
        candidates: candidates,
        profile: profile,
        expectedSession: expectedSession,
        generation: generation,
        currentQueue: currentQueue,
        currentIndex: currentIndex,
        currentSong: seed,
      );
    } finally {
      _endPlan();
    }
  }

  Future<List<MediaItem>> _planCandidates({
    required List<RecommendationCandidate> candidates,
    required TasteProfile profile,
    required FlowSession expectedSession,
    required int generation,
    required List<MediaItem> currentQueue,
    required int currentIndex,
    MediaItem? currentSong,
  }) async {
    final planningQueue = [...currentQueue];
    if (currentSong != null &&
        !planningQueue.any(
          (item) => RecommendationMediaJson.sameSong(item, currentSong),
        )) {
      planningQueue.add(currentSong);
    }
    final recentQueue = currentIndex < 0
        ? <MediaItem>[]
        : currentQueue
            .take(
              (currentIndex + 1).clamp(0, currentQueue.length).toInt(),
            )
            .toList()
            .reversed
            .toList();
    if (currentSong != null) {
      recentQueue.removeWhere(
        (item) => RecommendationMediaJson.sameSong(item, currentSong),
      );
      recentQueue.insert(0, currentSong);
    }

    final planned = _queuePlanner.planNext(
      candidates: candidates,
      profile: profile,
      session: expectedSession,
      tuner: expectedSession.tuner,
      blacklist: _blacklistService,
      recentQueue: recentQueue,
      existingQueue: planningQueue,
      limit: 8,
    );
    if (!_isCurrent(generation, expectedSession.id)) return [];

    final existingIds = planningQueue.map((item) => item.id).toSet();
    final existingKeys =
        planningQueue.map(RecommendationMediaJson.normalizedSongKey).toSet();
    final selected = planned.where((item) {
      final song = item.item;
      return !existingIds.contains(song.id) &&
          !existingKeys.contains(
            RecommendationMediaJson.normalizedSongKey(song),
          );
    }).toList();
    await _queueBox.put('lastPlan', {
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'sessionId': expectedSession.id,
      'items': selected.map((item) => item.toJson()).toList(),
    });
    if (!_isCurrent(generation, expectedSession.id)) return [];
    await _debugLogger.logDecisions(selected);
    if (!_isCurrent(generation, expectedSession.id)) return [];
    return selected.map(_withDecisionMetadata).toList();
  }

  bool _isCurrent(int generation, String sessionId) {
    return generation == _generation &&
        isActive.value &&
        session.value?.id == sessionId;
  }

  void _beginPlan() {
    _activePlans++;
    isRefilling.value = true;
  }

  void _endPlan() {
    if (_activePlans > 0) _activePlans--;
    isRefilling.value = _activePlans > 0;
  }

  MediaItem _withDecisionMetadata(FlowQueueItem decision) {
    return decision.item.copyWith(extras: {
      ...?decision.item.extras,
      'flowSource': decision.source,
      'flowReasonCodes': decision.reasonCodes,
      'flowScore': decision.score,
      'flowSessionId': decision.sessionId,
    });
  }

  Future<FlowTunerSettings> _settingsForMode(FlowMode mode) async {
    await _tuner.setMode(mode);
    return _tuner.current.value;
  }

  Future<FlowTunerSettings> _settingsForStation(FlowStation station) async {
    final settings = FlowTunerSettings.defaults().copyWith(
      mode: _modeFromName(station.modeName),
      familiarity: station.familiarity,
      variety: station.variety,
      deepCuts: station.deepCuts,
      genres: station.tags.toSet(),
    );
    await _tuner.applySettings(settings);
    return settings;
  }

  FlowMode _modeFromName(String value) {
    return FlowMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => FlowMode.auto,
    );
  }

  Future<void> _recordFeedback(
    FlowFeedbackAction action,
    MediaItem song,
    String sessionId,
  ) async {
    final box = Hive.box('FlowStats');
    await box.add({
      'sessionId': sessionId,
      'song': RecommendationMediaJson.fromMediaItem(song),
      'action': action.name,
      'reward': _feedbackPolicy.rewardFor(action),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    final overflow = box.length - 2000;
    for (var index = 0; index < overflow; index++) {
      await box.deleteAt(0);
    }
  }

  void _restorePersistedSession() {
    final raw = _sessionBox.get('current');
    if (raw is! Map) return;
    try {
      final restored = FlowSession.fromJson(raw);
      if (!restored.isActive || restored.id.trim().isEmpty) return;
      session.value = restored;
      isActive.value = true;
      _tuner.restoreSettings(restored.tuner);
    } catch (_) {}
  }
}
