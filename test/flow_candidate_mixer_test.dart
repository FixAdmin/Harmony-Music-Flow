import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/flow/flow_models.dart';
import 'package:harmonymusic/models/recommendation_item.dart';
import 'package:harmonymusic/models/taste_profile.dart';
import 'package:harmonymusic/services/flow/flow_candidate_mixer.dart';
import 'package:harmonymusic/services/recommendation/candidate_provider.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;

  MediaItem song(String id) {
    return MediaItem(id: id, title: 'Track $id', artist: 'Artist $id');
  }

  TasteProfile profile(int seedCount) {
    return TasteProfile(
      recentSeeds: [
        for (var index = 0; index < seedCount; index++) song('$index')
      ],
      topArtists: const {},
      skippedArtists: const {},
      playedSongIds: const {},
      likedSongIds: const {},
      dismissedSongIds: const {},
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flow_mixer_test');
    Hive.init(tempDir.path);
    for (final box in ['LIBFAV', 'SongDownloads', 'LIBRP']) {
      await Hive.openBox(box);
    }
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('returns partial candidates when another provider hangs or fails',
      () async {
    final provider = _RecordingCandidateProvider(
      hangSearch: true,
      failRelated: true,
    );
    final mixer = FlowCandidateMixer(
      candidateProvider: provider,
      providerTimeout: const Duration(milliseconds: 25),
    );
    final tuner = FlowTunerSettings.defaults().copyWith(mode: FlowMode.energy);
    final watch = Stopwatch()..start();

    final candidates = await mixer.getCandidates(
      profile(1),
      FlowSession.start(tuner: tuner),
      tuner,
    );

    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    expect(candidates.map((item) => item.item.id), contains('radio-0'));
  });

  test('per-seed limits use the actual provider seed subsets', () async {
    final provider = _RecordingCandidateProvider();
    final mixer = FlowCandidateMixer(
      candidateProvider: provider,
      providerTimeout: const Duration(seconds: 1),
    );
    final tuner = FlowTunerSettings.defaults();

    await mixer.getCandidates(
      profile(8),
      FlowSession.start(tuner: tuner),
      tuner,
    );

    expect(provider.radioLimits, everyElement(9));
    expect(provider.relatedLimits, everyElement(4));
    expect(provider.radioLimits, hasLength(4));
    expect(provider.relatedLimits, hasLength(5));
    expect(provider.lastFmLimits, hasLength(3));
  });
}

class _RecordingCandidateProvider implements CandidateProvider {
  _RecordingCandidateProvider(
      {this.hangSearch = false, this.failRelated = false});

  final bool hangSearch;
  final bool failRelated;
  final radioLimits = <int>[];
  final relatedLimits = <int>[];
  final lastFmLimits = <int>[];

  @override
  Future<List<RecommendationCandidate>> getSearchCandidates(
    String query, {
    int limit = 12,
    String source = 'station_search',
    String? seedId,
    double sourceScore = .64,
  }) {
    if (hangSearch) return Completer<List<RecommendationCandidate>>().future;
    return Future.value(const []);
  }

  @override
  Future<List<RecommendationCandidate>> getYouTubeRadioCandidates(
    MediaItem seed, {
    int limit = 14,
  }) {
    radioLimits.add(limit);
    return Future.value([
      RecommendationCandidate(
        item: MediaItem(
          id: 'radio-${seed.id}',
          title: 'Radio ${seed.id}',
          artist: 'Radio Artist ${seed.id}',
        ),
        source: 'youtube_radio',
      ),
    ]);
  }

  @override
  Future<List<RecommendationCandidate>> getYouTubeRelatedCandidates(
    MediaItem seed, {
    int limit = 14,
  }) {
    relatedLimits.add(limit);
    if (failRelated) return Future.error(StateError('related failed'));
    return Future.value(const []);
  }

  @override
  Future<List<RecommendationCandidate>> getLastFmCandidates(
    MediaItem seed, {
    int limit = 8,
  }) {
    lastFmLimits.add(limit);
    return Future.value(const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
