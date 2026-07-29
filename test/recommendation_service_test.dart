import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/recommendation_item.dart';
import 'package:harmonymusic/models/taste_profile.dart';
import 'package:harmonymusic/services/library/blacklist_service.dart';
import 'package:harmonymusic/services/recommendation/candidate_provider.dart';
import 'package:harmonymusic/services/recommendation/feedback_tracker.dart';
import 'package:harmonymusic/services/recommendation/recommendation_service.dart';
import 'package:harmonymusic/services/recommendation/taste_profile_service.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late TasteProfile profile;

  MediaItem song(String id, String title) {
    return MediaItem(id: id, title: title, artist: 'Nova');
  }

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('recommendation_service_test');
    Hive.init(tempDir.path);
    await Hive.openBox('AppPrefs');
    await Hive.openBox('RecommendationCache');
    await Hive.openBox('RecommendationSettings');
    await Hive.openBox('ListeningEvents');
    await Hive.openBox('TasteProfile');
    await Hive.openBox('TrackBlacklist');
    await Hive.openBox('ArtistBlacklist');
    await Hive.box('AppPrefs').put('recommendationsEnabled', true);
    profile = TasteProfile(
      recentSeeds: [song('seed', 'Seed')],
      topArtists: const {'nova': 2},
      skippedArtists: const {},
      playedSongIds: const {},
      likedSongIds: const {},
      dismissedSongIds: const {},
    );
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('meaningful feedback invalidates an otherwise fresh cache', () async {
    final cachedAt = DateTime.now().millisecondsSinceEpoch;
    await Hive.box('RecommendationCache').put('forYou', {
      'updatedAt': cachedAt,
      'songs': [
        RecommendationMediaJson.fromMediaItem(song('cached', 'Cached'))
      ],
    });
    await Hive.box('RecommendationSettings').put(
      FeedbackTracker.lastMeaningfulFeedbackAtKey,
      cachedAt + 1,
    );
    final provider = _FakeCandidateProvider([
      RecommendationCandidate(
        item: song('fresh', 'Fresh'),
        source: 'youtube_radio',
        sourceScore: .9,
      ),
    ]);
    final service = RecommendationService(
      tasteProfileService: _FakeTasteProfileService(profile),
      candidateProvider: provider,
      feedbackTracker: FeedbackTracker(),
      blacklistService: BlacklistService(),
    );

    await service.refreshForYou();

    expect(provider.calls, 1);
    expect(service.forYou.value.songList.single.id, 'fresh');
    expect(
      service.forYou.value.songList.single.extras?['recommendationSource'],
      'youtube_radio',
    );
    expect(
      service.forYou.value.songList.single.extras?['recommendationScore'],
      greaterThan(.9),
    );
    expect(
      service.forYou.value.songList.single.extras?['recommendationReasonCodes'],
      ['youtube_radio'],
    );
    final cached = Hive.box('RecommendationCache').get('forYou') as Map;
    expect(
      (cached['songs'] as List).single['recommendationReasonCodes'],
      ['youtube_radio'],
    );
  });

  test('loads a fresh cache without another provider request', () async {
    final cachedAt = DateTime.now().millisecondsSinceEpoch;
    await Hive.box('RecommendationCache').put('forYou', {
      'updatedAt': cachedAt,
      'songs': [
        RecommendationMediaJson.fromMediaItem(song('cached', 'Cached'))
      ],
    });
    final provider = _FakeCandidateProvider(const []);
    final service = RecommendationService(
      tasteProfileService: _FakeTasteProfileService(profile),
      candidateProvider: provider,
      feedbackTracker: FeedbackTracker(),
      blacklistService: BlacklistService(),
    );

    await service.refreshForYou();

    expect(provider.calls, 0);
    expect(service.forYou.value.songList.single.id, 'cached');
  });

  test('dismiss during provider wait cannot restore the track', () async {
    final dismissed = song('dismissed', 'Dismissed');
    final retained = song('retained', 'Retained');
    final provider = _CompleterCandidateProvider();
    final service = RecommendationService(
      tasteProfileService: _FakeTasteProfileService(profile),
      candidateProvider: provider,
      feedbackTracker: FeedbackTracker(),
      blacklistService: BlacklistService(),
    );

    final refresh = service.refreshForYou(force: true);
    await provider.called;
    await service.dismissTrack(dismissed);
    provider.complete([
      RecommendationCandidate(item: dismissed, source: 'youtube_radio'),
      RecommendationCandidate(item: retained, source: 'youtube_related'),
    ]);
    await refresh;

    expect(
      service.forYou.value.songList.map((item) => item.id),
      isNot(contains(dismissed.id)),
    );
    final cached = Hive.box('RecommendationCache').get('forYou') as Map?;
    final cachedSongs = cached?['songs'] as List? ?? const [];
    expect(
      cachedSongs.map((item) => (item as Map)['videoId']),
      isNot(contains(dismissed.id)),
    );
  });

  test('clear during provider wait cannot repopulate recommendations',
      () async {
    final provider = _CompleterCandidateProvider();
    final service = RecommendationService(
      tasteProfileService: _FakeTasteProfileService(profile),
      candidateProvider: provider,
      feedbackTracker: FeedbackTracker(),
      blacklistService: BlacklistService(),
    );

    final refresh = service.refreshForYou(force: true);
    await provider.called;
    await service.clearRecommendationData();
    provider.complete([
      RecommendationCandidate(
        item: song('late', 'Late'),
        source: 'youtube_radio',
      ),
    ]);
    await refresh;

    expect(service.forYou.value.songList, isEmpty);
    expect(Hive.box('RecommendationCache').containsKey('forYou'), isFalse);
  });

  test('empty provider result retains usable cached recommendations', () async {
    await Hive.box('RecommendationCache').put('forYou', {
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'songs': [
        RecommendationMediaJson.fromMediaItem(song('cached', 'Cached')),
      ],
    });
    final service = RecommendationService(
      tasteProfileService: _FakeTasteProfileService(profile),
      candidateProvider: _FakeCandidateProvider(const []),
      feedbackTracker: FeedbackTracker(),
      blacklistService: BlacklistService(),
    );

    await service.refreshForYou(force: true);

    expect(service.forYou.value.songList.single.id, 'cached');
    final cached = Hive.box('RecommendationCache').get('forYou') as Map;
    expect((cached['songs'] as List).single['videoId'], 'cached');
  });

  test('empty provider result does not retain dismissed cached items',
      () async {
    final dismissed = song('dismissed', 'Dismissed');
    await Hive.box('RecommendationCache').put('forYou', {
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'songs': [RecommendationMediaJson.fromMediaItem(dismissed)],
    });
    await Hive.box('RecommendationCache').put(
      'dismissedSongIds',
      [dismissed.id],
    );
    final service = RecommendationService(
      tasteProfileService: _FakeTasteProfileService(profile),
      candidateProvider: _FakeCandidateProvider(const []),
      feedbackTracker: FeedbackTracker(),
      blacklistService: BlacklistService(),
    );
    service.forYou.value.songList = [dismissed];

    await service.refreshForYou(force: true);

    expect(service.forYou.value.songList, isEmpty);
  });

  test('feedback during provider wait forces a revision-aware rerun', () async {
    final firstResult = Completer<List<RecommendationCandidate>>();
    final provider = _SequencedCandidateProvider([
      firstResult.future,
      Future.value([
        RecommendationCandidate(
          item: song('fresh', 'Fresh'),
          source: 'youtube_related',
        ),
      ]),
    ]);
    final tracker = FeedbackTracker();
    final service = RecommendationService(
      tasteProfileService: _FakeTasteProfileService(profile),
      candidateProvider: provider,
      feedbackTracker: tracker,
      blacklistService: BlacklistService(),
    );

    final refresh = service.refreshForYou(force: true);
    await provider.firstCalled;
    await tracker.recordSkipEarly(song('feedback', 'Feedback'));
    firstResult.complete([
      RecommendationCandidate(
        item: song('stale', 'Stale'),
        source: 'youtube_radio',
      ),
    ]);
    await refresh;

    expect(provider.calls, 2);
    expect(service.forYou.value.songList.single.id, 'fresh');
    final cached = Hive.box('RecommendationCache').get('forYou') as Map;
    expect(cached['feedbackRevision'], tracker.feedbackRevision);
  });
}

class _FakeTasteProfileService extends TasteProfileService {
  _FakeTasteProfileService(this.profile);

  final TasteProfile profile;

  @override
  Future<TasteProfile> buildProfile() async => profile;
}

class _FakeCandidateProvider implements CandidateProvider {
  _FakeCandidateProvider(this.candidates);

  final List<RecommendationCandidate> candidates;
  int calls = 0;

  @override
  Future<List<RecommendationCandidate>> getCandidates(
    TasteProfile profile, {
    int limit = 60,
  }) async {
    calls++;
    return candidates;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CompleterCandidateProvider implements CandidateProvider {
  final _result = Completer<List<RecommendationCandidate>>();
  final _called = Completer<void>();

  Future<void> get called => _called.future;

  void complete(List<RecommendationCandidate> candidates) {
    _result.complete(candidates);
  }

  @override
  Future<List<RecommendationCandidate>> getCandidates(
    TasteProfile profile, {
    int limit = 60,
  }) {
    if (!_called.isCompleted) _called.complete();
    return _result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SequencedCandidateProvider implements CandidateProvider {
  _SequencedCandidateProvider(this.results);

  final List<Future<List<RecommendationCandidate>>> results;
  final _firstCalled = Completer<void>();
  int calls = 0;

  Future<void> get firstCalled => _firstCalled.future;

  @override
  Future<List<RecommendationCandidate>> getCandidates(
    TasteProfile profile, {
    int limit = 60,
  }) {
    if (!_firstCalled.isCompleted) _firstCalled.complete();
    return results[calls++];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
