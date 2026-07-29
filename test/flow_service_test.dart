import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/flow/flow_models.dart';
import 'package:harmonymusic/models/flow/flow_station.dart';
import 'package:harmonymusic/models/recommendation_item.dart';
import 'package:harmonymusic/models/taste_profile.dart';
import 'package:harmonymusic/services/flow/flow_candidate_mixer.dart';
import 'package:harmonymusic/services/flow/flow_debug_logger.dart';
import 'package:harmonymusic/services/flow/flow_feedback_policy.dart';
import 'package:harmonymusic/services/flow/flow_queue_planner.dart';
import 'package:harmonymusic/services/flow/flow_service.dart';
import 'package:harmonymusic/services/flow/flow_tuner.dart';
import 'package:harmonymusic/services/library/blacklist_service.dart';
import 'package:harmonymusic/services/recommendation/feedback_tracker.dart';
import 'package:harmonymusic/services/recommendation/taste_profile_service.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flow_service_test');
    Hive.init(tempDir.path);
    for (final box in [
      'AppPrefs',
      'FlowSessions',
      'FlowQueueState',
      'FlowTunerPresets',
      'FlowDebugLog',
      'FlowStats',
      'TrackBlacklist',
      'ArtistBlacklist',
      'ListeningEvents',
      'RecommendationSettings',
    ]) {
      await Hive.openBox(box);
    }
    await Hive.box('AppPrefs').putAll({
      'flowEnabled': true,
      'recommendationsEnabled': true,
      'showFlowDebugEnabled': false,
    });
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('a stale station plan cannot overwrite a newer station', () async {
    final firstStarted = Completer<void>();
    final firstResult = Completer<List<RecommendationCandidate>>();
    final mixer = _RaceCandidateMixer(firstStarted, firstResult);
    final profile = TasteProfile(
      recentSeeds: const [],
      topArtists: const {'nova': 2},
      skippedArtists: const {},
      playedSongIds: const {},
      likedSongIds: const {},
      dismissedSongIds: const {},
    );
    final service = FlowService(
      tuner: FlowTuner(),
      tasteProfileService: _FakeTasteProfileService(profile),
      candidateMixer: mixer,
      queuePlanner: FlowQueuePlanner(),
      blacklistService: BlacklistService(),
      feedbackPolicy: FlowFeedbackPolicy(),
      debugLogger: FlowDebugLogger(),
      feedbackTracker: FeedbackTracker(),
    );

    final first = service.start(station: station('alpha'));
    await firstStarted.future;
    final second = await service.start(station: station('beta'));
    firstResult.complete([
      candidate('alpha-track', 'Alpha Focus', 'alpha'),
    ]);
    final stale = await first;

    expect(stale, isEmpty);
    expect(second.single.id, 'beta-track');
    expect(service.session.value?.station?.id, 'beta');
  });

  test('a plan that becomes stale during debug persistence returns nothing',
      () async {
    final logger = _DelayedDebugLogger();
    final tuner = FlowTuner();
    final service = FlowService(
      tuner: tuner,
      tasteProfileService: _FakeTasteProfileService(emptyProfile()),
      candidateMixer: _StationCandidateMixer(),
      queuePlanner: FlowQueuePlanner(),
      blacklistService: BlacklistService(),
      feedbackPolicy: FlowFeedbackPolicy(),
      debugLogger: logger,
      feedbackTracker: FeedbackTracker(),
    );

    final first = service.start(station: station('alpha'));
    await logger.firstStarted.future;
    final second = await service.start(station: station('beta'));
    logger.releaseFirst.complete();
    final stale = await first;

    expect(second.single.id, 'beta-track');
    expect(stale, isEmpty);
    expect(service.session.value?.station?.id, 'beta');
    expect(tuner.current.value.familiarity, station('beta').familiarity);
  });

  test('delayed feedback cannot mutate a newer session or its stats', () async {
    final tracker = _DelayedFeedbackTracker();
    final service = FlowService(
      tuner: FlowTuner(),
      tasteProfileService: _FakeTasteProfileService(emptyProfile()),
      candidateMixer: _StationCandidateMixer(),
      queuePlanner: FlowQueuePlanner(),
      blacklistService: BlacklistService(),
      feedbackPolicy: FlowFeedbackPolicy(),
      debugLogger: FlowDebugLogger(),
      feedbackTracker: tracker,
    );
    await service.start(station: station('alpha'));
    final capturedSessionId = service.session.value!.id;
    const feedbackSong = MediaItem(
      id: 'feedback-song',
      title: 'Feedback Song',
      artist: 'Nova',
    );

    final feedback = service.onFeedback(
      FlowFeedbackAction.moreLikeThis,
      feedbackSong,
    );
    await tracker.started.future;
    await service.start(station: station('beta'));
    tracker.release.complete();
    await feedback;

    expect(tracker.sessionId, capturedSessionId);
    expect(service.session.value?.station?.id, 'beta');
    expect(
        service.session.value?.seedSongIds, isNot(contains('feedback-song')));
    expect(Hive.box('FlowStats').values, isEmpty);
  });

  test('feedback stats are attributed to the captured active session',
      () async {
    final service = FlowService(
      tuner: FlowTuner(),
      tasteProfileService: _FakeTasteProfileService(emptyProfile()),
      candidateMixer: _StationCandidateMixer(),
      queuePlanner: FlowQueuePlanner(),
      blacklistService: BlacklistService(),
      feedbackPolicy: FlowFeedbackPolicy(),
      debugLogger: FlowDebugLogger(),
      feedbackTracker: FeedbackTracker(),
    );
    await service.start(station: station('alpha'));
    final capturedSessionId = service.session.value!.id;

    await service.onFeedback(
      FlowFeedbackAction.like,
      const MediaItem(id: 'liked', title: 'Liked', artist: 'Nova'),
    );

    final stats = Hive.box('FlowStats').values.single as Map;
    expect(stats['sessionId'], capturedSessionId);
  });

  test('station launch and tuning synchronize tuner without losing station',
      () async {
    final tuner = FlowTuner();
    final service = FlowService(
      tuner: tuner,
      tasteProfileService: _FakeTasteProfileService(emptyProfile()),
      candidateMixer: _StationCandidateMixer(),
      queuePlanner: FlowQueuePlanner(),
      blacklistService: BlacklistService(),
      feedbackPolicy: FlowFeedbackPolicy(),
      debugLogger: FlowDebugLogger(),
      feedbackTracker: FeedbackTracker(),
    );

    await service.start(station: station('alpha'));
    expect(tuner.current.value.mode, FlowMode.discover);
    expect(tuner.current.value.variety, station('alpha').variety);

    final updated = tuner.current.value.copyWith(
      familiarity: .9,
      genres: {'Electronic'},
    );
    await service.updateTuner(updated);

    expect(tuner.current.value.familiarity, .9);
    expect(service.session.value?.tuner.familiarity, .9);
    expect(service.session.value?.station?.id, 'alpha');
  });

  test('restores a valid active session and its tuner state on init', () async {
    final restoredTuner = FlowTunerSettings.defaults().copyWith(
      mode: FlowMode.energy,
      familiarity: .8,
      genres: {'Rock'},
    );
    final persisted = FlowSession(
      id: 'persisted-session',
      startedAt: DateTime.now(),
      tuner: restoredTuner,
      seedSongIds: const ['seed'],
      skipStreak: 2,
      isActive: true,
      station: station('alpha'),
    );
    await Hive.box('FlowSessions').put('current', persisted.toJson());
    final tuner = FlowTuner();
    final service = FlowService(
      tuner: tuner,
      tasteProfileService: _FakeTasteProfileService(emptyProfile()),
      candidateMixer: _StationCandidateMixer(),
      queuePlanner: FlowQueuePlanner(),
      blacklistService: BlacklistService(),
      feedbackPolicy: FlowFeedbackPolicy(),
      debugLogger: FlowDebugLogger(),
      feedbackTracker: FeedbackTracker(),
    );

    service.onInit();

    expect(service.isActive.value, isTrue);
    expect(service.session.value?.id, 'persisted-session');
    expect(service.session.value?.station?.id, 'alpha');
    expect(tuner.current.value.mode, FlowMode.energy);
    expect(tuner.current.value.genres, contains('Rock'));
  });

  test('fallback candidates use active flow policy and decision metadata',
      () async {
    final blacklist = BlacklistService();
    final service = FlowService(
      tuner: FlowTuner(),
      tasteProfileService: _FakeTasteProfileService(emptyProfile()),
      candidateMixer: _EmptyCandidateMixer(),
      queuePlanner: FlowQueuePlanner(),
      blacklistService: blacklist,
      feedbackPolicy: FlowFeedbackPolicy(),
      debugLogger: FlowDebugLogger(),
      feedbackTracker: FeedbackTracker(),
    );
    await service.start(station: station('alpha'));
    const current =
        MediaItem(id: 'current', title: 'Alpha Current', artist: 'A');
    const blocked =
        MediaItem(id: 'blocked', title: 'Alpha Blocked', artist: 'B');
    await blacklist.blockTrack(blocked);

    final planned = await service.planFallbackCandidates(
      candidates: [
        RecommendationCandidate(item: current, source: 'youtube_related'),
        RecommendationCandidate(item: blocked, source: 'youtube_related'),
        RecommendationCandidate(
          item: const MediaItem(
            id: 'good',
            title: 'Alpha Focus',
            artist: 'C',
          ),
          source: 'youtube_related',
        ),
      ],
      currentQueue: const [current],
      currentIndex: 0,
      currentSong: current,
    );

    expect(planned.map((item) => item.id), ['good']);
    expect(planned.single.extras?['flowSource'], 'youtube_related');
    expect(
      planned.single.extras?['flowSessionId'],
      service.session.value?.id,
    );
  });

  test('fallback planning returns nothing after the active session changes',
      () async {
    final profileService = _DelayedSecondTasteProfileService(emptyProfile());
    final service = FlowService(
      tuner: FlowTuner(),
      tasteProfileService: profileService,
      candidateMixer: _StationCandidateMixer(),
      queuePlanner: FlowQueuePlanner(),
      blacklistService: BlacklistService(),
      feedbackPolicy: FlowFeedbackPolicy(),
      debugLogger: FlowDebugLogger(),
      feedbackTracker: FeedbackTracker(),
    );
    await service.start(station: station('alpha'));

    final fallback = service.planFallbackCandidates(
      candidates: [candidate('fallback', 'Alpha Focus', 'alpha')],
      currentQueue: const [],
      currentIndex: -1,
    );
    await profileService.secondStarted.future;
    await service.start(station: station('beta'));
    profileService.releaseSecond.complete();

    expect(await fallback, isEmpty);
    expect(service.session.value?.station?.id, 'beta');
  });

  test('failed replacement restores the previous session and tuner', () async {
    final mixer = _FailingSecondCandidateMixer();
    final tuner = FlowTuner();
    final service = FlowService(
      tuner: tuner,
      tasteProfileService: _FakeTasteProfileService(emptyProfile()),
      candidateMixer: mixer,
      queuePlanner: FlowQueuePlanner(),
      blacklistService: BlacklistService(),
      feedbackPolicy: FlowFeedbackPolicy(),
      debugLogger: FlowDebugLogger(),
      feedbackTracker: FeedbackTracker(),
    );

    await service.start(station: station('alpha'));
    final previousSession = service.session.value!;
    final previousTuner = tuner.current.value;

    await expectLater(
      service.start(station: station('beta')),
      throwsStateError,
    );

    expect(service.isActive.value, isTrue);
    expect(service.session.value?.id, previousSession.id);
    expect(service.session.value?.station?.id, 'alpha');
    expect(tuner.current.value.mode, previousTuner.mode);
    expect(tuner.current.value.familiarity, previousTuner.familiarity);
    final persisted = Hive.box('FlowSessions').get('current') as Map;
    expect(persisted['id'], previousSession.id);
  });

  test('fallback can be planned while the primary plan is still pending',
      () async {
    final primaryStarted = Completer<void>();
    final primaryResult = Completer<List<RecommendationCandidate>>();
    final service = FlowService(
      tuner: FlowTuner(),
      tasteProfileService: _FakeTasteProfileService(emptyProfile()),
      candidateMixer: _RaceCandidateMixer(primaryStarted, primaryResult),
      queuePlanner: FlowQueuePlanner(),
      blacklistService: BlacklistService(),
      feedbackPolicy: FlowFeedbackPolicy(),
      debugLogger: FlowDebugLogger(),
      feedbackTracker: FeedbackTracker(),
    );

    final primary = service.start(station: station('alpha'));
    await primaryStarted.future;
    const current = MediaItem(id: 'current', title: 'Current', artist: 'Nova');

    final fallback = await service.planFallbackCandidates(
      candidates: [candidate('fallback', 'Alpha Focus', 'alpha')],
      currentQueue: const [current],
      currentIndex: 0,
      currentSong: current,
    );

    expect(fallback.map((item) => item.id), ['fallback']);
    primaryResult.complete([candidate('primary', 'Alpha Main', 'alpha')]);
    await primary;
  });

  test('restores a captured active session after an unsuccessful launch',
      () async {
    final tuner = FlowTuner();
    final service = FlowService(
      tuner: tuner,
      tasteProfileService: _FakeTasteProfileService(emptyProfile()),
      candidateMixer: _StationCandidateMixer(),
      queuePlanner: FlowQueuePlanner(),
      blacklistService: BlacklistService(),
      feedbackPolicy: FlowFeedbackPolicy(),
      debugLogger: FlowDebugLogger(),
      feedbackTracker: FeedbackTracker(),
    );

    await service.start(station: station('alpha'));
    final captured = service.session.value!;
    await service.start(station: station('beta'));

    await service.restoreActiveSession(captured);

    expect(service.isActive.value, isTrue);
    expect(service.session.value?.id, captured.id);
    expect(service.session.value?.station?.id, 'alpha');
    expect(tuner.current.value.familiarity, captured.tuner.familiarity);
    final persisted = Hive.box('FlowSessions').get('current') as Map;
    expect(persisted['id'], captured.id);
  });
}

TasteProfile emptyProfile() {
  return TasteProfile(
    recentSeeds: const [],
    topArtists: const {},
    skippedArtists: const {},
    playedSongIds: const {},
    likedSongIds: const {},
    dismissedSongIds: const {},
  );
}

FlowStation station(String id) {
  return FlowStation(
    id: id,
    title: id,
    subtitle: id,
    tags: [id],
    seedTerms: [id],
    searchQueries: ['$id music'],
    modeName: 'discover',
    familiarity: .4,
    variety: .7,
    deepCuts: .5,
    localWeight: .3,
    externalWeight: .7,
    confidence: .8,
    reason: 'test',
  );
}

RecommendationCandidate candidate(String id, String title, String stationId) {
  return RecommendationCandidate(
    item: MediaItem(id: id, title: title, artist: 'Nova'),
    source: 'station_search',
    seedId: stationId,
  );
}

class _FakeTasteProfileService extends TasteProfileService {
  _FakeTasteProfileService(this.profile);

  final TasteProfile profile;

  @override
  Future<TasteProfile> buildProfile() async => profile;
}

class _DelayedSecondTasteProfileService extends TasteProfileService {
  _DelayedSecondTasteProfileService(this.profile);

  final TasteProfile profile;
  final secondStarted = Completer<void>();
  final releaseSecond = Completer<void>();
  int calls = 0;

  @override
  Future<TasteProfile> buildProfile() async {
    calls++;
    if (calls == 2) {
      secondStarted.complete();
      await releaseSecond.future;
    }
    return profile;
  }
}

class _RaceCandidateMixer implements FlowCandidateMixer {
  _RaceCandidateMixer(this.firstStarted, this.firstResult);

  final Completer<void> firstStarted;
  final Completer<List<RecommendationCandidate>> firstResult;
  int calls = 0;

  @override
  Future<List<RecommendationCandidate>> getCandidates(
    TasteProfile profile,
    FlowSession session,
    FlowTunerSettings tuner, {
    int limit = 80,
    MediaItem? currentSong,
  }) {
    calls++;
    if (calls == 1) {
      firstStarted.complete();
      return firstResult.future;
    }
    return Future.value([
      candidate('beta-track', 'Beta Focus', 'beta'),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StationCandidateMixer implements FlowCandidateMixer {
  @override
  Future<List<RecommendationCandidate>> getCandidates(
    TasteProfile profile,
    FlowSession session,
    FlowTunerSettings tuner, {
    int limit = 80,
    MediaItem? currentSong,
  }) async {
    final stationId = session.station?.id ?? 'auto';
    return [candidate('$stationId-track', '$stationId Focus', stationId)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyCandidateMixer implements FlowCandidateMixer {
  @override
  Future<List<RecommendationCandidate>> getCandidates(
    TasteProfile profile,
    FlowSession session,
    FlowTunerSettings tuner, {
    int limit = 80,
    MediaItem? currentSong,
  }) async {
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingSecondCandidateMixer implements FlowCandidateMixer {
  int calls = 0;

  @override
  Future<List<RecommendationCandidate>> getCandidates(
    TasteProfile profile,
    FlowSession session,
    FlowTunerSettings tuner, {
    int limit = 80,
    MediaItem? currentSong,
  }) async {
    calls++;
    if (calls == 2) throw StateError('planning failed');
    final stationId = session.station?.id ?? 'auto';
    return [candidate('$stationId-track', '$stationId Focus', stationId)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedDebugLogger implements FlowDebugLogger {
  final firstStarted = Completer<void>();
  final releaseFirst = Completer<void>();
  int calls = 0;

  @override
  Future<void> logDecisions(List<FlowQueueItem> items) async {
    calls++;
    if (calls != 1) return;
    firstStarted.complete();
    await releaseFirst.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedFeedbackTracker extends FeedbackTracker {
  final started = Completer<void>();
  final release = Completer<void>();
  String? sessionId;

  @override
  Future<void> recordFlowMoreLikeThis(
    MediaItem song, {
    String? sessionId,
  }) async {
    this.sessionId = sessionId;
    started.complete();
    await release.future;
  }
}
