import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/flow/flow_models.dart';
import 'package:harmonymusic/models/flow/flow_station.dart';
import 'package:harmonymusic/models/recommendation_item.dart';
import 'package:harmonymusic/models/taste_profile.dart';
import 'package:harmonymusic/services/flow/flow_queue_planner.dart';
import 'package:harmonymusic/services/library/blacklist_service.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late BlacklistService blacklist;

  MediaItem song(String id, String title, String artist, {String? album}) {
    return MediaItem(id: id, title: title, artist: artist, album: album);
  }

  TasteProfile profile({
    Map<String, double> topArtists = const {},
    Set<String> playedSongIds = const {},
    Set<String> dismissedSongIds = const {},
  }) {
    return TasteProfile(
      recentSeeds: [song('seed', 'Seed', 'Known Artist')],
      topArtists: topArtists,
      skippedArtists: const {},
      playedSongIds: playedSongIds,
      likedSongIds: const {},
      dismissedSongIds: dismissedSongIds,
    );
  }

  FlowStation blendStation(double localWeight) {
    return FlowStation(
      id: 'focus',
      title: 'Focus',
      subtitle: 'Focus',
      tags: const ['focus'],
      seedTerms: const ['focus'],
      searchQueries: const ['focus music'],
      modeName: 'auto',
      familiarity: .5,
      variety: .7,
      deepCuts: .5,
      localWeight: localWeight,
      externalWeight: 1 - localWeight,
      confidence: .8,
      reason: 'test',
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flow_planner_test');
    Hive.init(tempDir.path);
    await Hive.openBox('TrackBlacklist');
    await Hive.openBox('ArtistBlacklist');
    blacklist = BlacklistService();
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('filters blacklisted tracks before ranking', () async {
    final blocked = song('blocked', 'Bad Song', 'Bad Artist');
    await blacklist.blockTrack(blocked);

    final planned = FlowQueuePlanner().planNext(
      candidates: [
        RecommendationCandidate(item: blocked, source: 'youtube_radio'),
        RecommendationCandidate(
            item: song('good', 'Good Song', 'Good Artist'),
            source: 'youtube_radio'),
      ],
      profile: profile(),
      session: FlowSession.start(tuner: FlowTunerSettings.defaults()),
      tuner: FlowTunerSettings.defaults(),
      blacklist: blacklist,
      limit: 4,
    );

    expect(planned.map((item) => item.item.id), isNot(contains('blocked')));
    expect(planned.map((item) => item.item.id), contains('good'));
  });

  test('prefers fresh tracks from preferred artists', () {
    final planned = FlowQueuePlanner().planNext(
      candidates: [
        RecommendationCandidate(
            item: song('played', 'Old', 'Known Artist'),
            source: 'youtube_radio'),
        RecommendationCandidate(
            item: song('fresh', 'Fresh', 'Known Artist'),
            source: 'youtube_radio'),
      ],
      profile: profile(
        topArtists: {'Known Artist': 5},
        playedSongIds: {'played'},
      ),
      session: FlowSession.start(tuner: FlowTunerSettings.defaults()),
      tuner: FlowTunerSettings.defaults(),
      blacklist: blacklist,
      limit: 2,
    );

    expect(planned.first.item.id, 'fresh');
  });

  test('discover mode boosts non-local sources', () {
    final planned = FlowQueuePlanner().planNext(
      candidates: [
        RecommendationCandidate(
            item: song('local', 'Local', 'Known Artist'),
            source: 'local_favorite',
            sourceScore: .7),
        RecommendationCandidate(
            item: song('new', 'New', 'New Artist'),
            source: 'youtube_radio',
            sourceScore: .7),
      ],
      profile: profile(),
      session: FlowSession.start(tuner: FlowTunerSettings.defaults()),
      tuner: FlowTunerSettings.defaults().copyWith(mode: FlowMode.discover),
      blacklist: blacklist,
      limit: 2,
    );

    expect(planned.first.item.id, 'new');
  });

  test('station terms boost matching candidates', () {
    const station = FlowStation(
      id: 'cinematic',
      title: 'Cinematic',
      subtitle: 'Scores and strings',
      tags: ['orchestral', 'soundtrack'],
      seedTerms: ['cinematic', 'epic', 'strings'],
      searchQueries: ['cinematic orchestral music'],
      modeName: 'discover',
      familiarity: .4,
      variety: .7,
      deepCuts: .5,
      localWeight: .3,
      externalWeight: .7,
      confidence: .8,
      reason: 'test',
    );

    final planned = FlowQueuePlanner().planNext(
      candidates: [
        RecommendationCandidate(
          item: song('pop', 'Bright Dance Hit', 'Pop Artist'),
          source: 'youtube_radio',
          sourceScore: .8,
        ),
        RecommendationCandidate(
          item: song('score', 'Epic Orchestral Strings', 'Score Artist'),
          source: 'youtube_radio',
          sourceScore: .8,
        ),
      ],
      profile: profile(),
      session: FlowSession.start(
        tuner: FlowTunerSettings.defaults(),
        station: station,
      ),
      tuner: FlowTunerSettings.defaults(),
      blacklist: blacklist,
      limit: 2,
    );

    expect(planned.first.item.id, 'score');
    expect(planned.first.reasonCodes, contains('station_match'));
  });

  test('station search beats generic radio when station is active', () {
    const station = FlowStation(
      id: 'gaming_focus',
      title: 'Gaming Focus',
      subtitle: 'Focus',
      tags: ['gaming', 'focus', 'instrumental'],
      seedTerms: ['gaming', 'focus', 'electronic'],
      searchQueries: ['gaming focus music'],
      modeName: 'discover',
      familiarity: .35,
      variety: .75,
      deepCuts: .55,
      localWeight: .25,
      externalWeight: .75,
      confidence: .7,
      reason: 'test',
    );

    final planned = FlowQueuePlanner().planNext(
      candidates: [
        RecommendationCandidate(
          item: song('generic', 'Epic Orchestral Strings', 'Known Artist'),
          source: 'youtube_radio',
          sourceScore: 1.0,
        ),
        RecommendationCandidate(
          item: song('station', 'Gaming Focus Electronic', 'New Artist'),
          source: 'station_search',
          sourceScore: .78,
        ),
      ],
      profile: profile(topArtists: {'Known Artist': 5}),
      session: FlowSession.start(
        tuner: FlowTunerSettings.defaults(),
        station: station,
      ),
      tuner: FlowTunerSettings.defaults().copyWith(mode: FlowMode.discover),
      blacklist: blacklist,
      limit: 2,
    );

    expect(planned.first.item.id, 'station');
    expect(planned.first.reasonCodes, contains('station_search'));
  });

  test('deduplicates alternate uploads by normalized song identity', () {
    final planned = FlowQueuePlanner().planNext(
      candidates: [
        RecommendationCandidate(
          item: song('video-a', 'Signal', 'Nova'),
          source: 'youtube_radio',
        ),
        RecommendationCandidate(
          item: song('video-b', 'Signal (Official Audio)', 'Nova'),
          source: 'youtube_related',
        ),
      ],
      profile: profile(),
      session: FlowSession.start(tuner: FlowTunerSettings.defaults()),
      tuner: FlowTunerSettings.defaults(),
      blacklist: blacklist,
      limit: 4,
    );

    expect(planned, hasLength(1));
  });

  test('keeps the same artist out of every three-track window', () {
    final planned = FlowQueuePlanner().planNext(
      candidates: [
        for (var index = 0; index < 3; index++)
          RecommendationCandidate(
            item: song('nova-$index', 'Nova $index', 'Nova'),
            source: 'youtube_radio',
          ),
        for (var index = 0; index < 4; index++)
          RecommendationCandidate(
            item: song('other-$index', 'Other $index', 'Artist $index'),
            source: 'youtube_related',
          ),
      ],
      profile: profile(topArtists: {'nova': 5}),
      session: FlowSession.start(tuner: FlowTunerSettings.defaults()),
      tuner: FlowTunerSettings.defaults(),
      blacklist: blacklist,
      limit: 7,
    );

    for (var index = 0; index <= planned.length - 3; index++) {
      final artists =
          planned.skip(index).take(3).map((item) => item.item.artist).toList();
      expect(artists.where((artist) => artist == 'Nova').length, lessThan(2));
    }
  });

  test('final eight honors station local weight when both pools exist', () {
    final station = blendStation(.75);
    final tuner = FlowTunerSettings.defaults().copyWith(variety: .8);
    final planned = FlowQueuePlanner().planNext(
      candidates: [
        for (var index = 0; index < 8; index++)
          RecommendationCandidate(
            item: song('local-$index', 'Focus Local $index', 'Local $index'),
            source: 'local_favorite',
          ),
        for (var index = 0; index < 8; index++)
          RecommendationCandidate(
            item: song(
              'external-$index',
              'Focus External $index',
              'External $index',
            ),
            source: 'youtube_radio',
          ),
      ],
      profile: profile(),
      session: FlowSession.start(tuner: tuner, station: station),
      tuner: tuner,
      blacklist: blacklist,
      limit: 8,
    );

    expect(planned, hasLength(8));
    expect(
      planned.where((item) => item.source.startsWith('local')),
      hasLength(6),
    );
    for (var index = 0; index <= planned.length - 3; index++) {
      final artists =
          planned.skip(index).take(3).map((item) => item.item.artist).toSet();
      expect(artists, hasLength(3));
    }
  });

  test('final eight derives non-station local blend from familiarity', () {
    final tuner = FlowTunerSettings.defaults().copyWith(familiarity: .25);
    final planned = FlowQueuePlanner().planNext(
      candidates: [
        for (var index = 0; index < 8; index++)
          RecommendationCandidate(
            item: song('local-$index', 'Local $index', 'Local $index'),
            source: 'local_favorite',
          ),
        for (var index = 0; index < 8; index++)
          RecommendationCandidate(
            item: song('external-$index', 'External $index', 'External $index'),
            source: 'youtube_radio',
          ),
      ],
      profile: profile(),
      session: FlowSession.start(tuner: tuner),
      tuner: tuner,
      blacklist: blacklist,
      limit: 8,
    );

    expect(planned, hasLength(8));
    expect(
      planned.where((item) => item.source.startsWith('local')),
      hasLength(2),
    );
  });

  test('deep-cuts control changes rank preference', () {
    final candidates = [
      RecommendationCandidate(
        item: song('hit', 'Top Hit', 'Hit Artist'),
        source: 'station_search',
        sourceRank: 0,
      ),
      RecommendationCandidate(
        item: song('deep', 'Deep Track', 'Deep Artist'),
        source: 'station_search',
        sourceRank: 12,
      ),
    ];
    final session = FlowSession.start(tuner: FlowTunerSettings.defaults());

    final hits = FlowQueuePlanner().planNext(
      candidates: candidates,
      profile: profile(),
      session: session,
      tuner: FlowTunerSettings.defaults().copyWith(deepCuts: 0),
      blacklist: blacklist,
      limit: 2,
    );
    final deep = FlowQueuePlanner().planNext(
      candidates: candidates,
      profile: profile(),
      session: session,
      tuner: FlowTunerSettings.defaults().copyWith(deepCuts: 1),
      blacklist: blacklist,
      limit: 2,
    );

    expect(hits.first.item.id, 'hit');
    expect(deep.first.item.id, 'deep');
  });

  test('selected genre changes the first candidate', () {
    final tuner = FlowTunerSettings.defaults().copyWith(genres: {'Metal'});
    final planned = FlowQueuePlanner().planNext(
      candidates: [
        RecommendationCandidate(
          item: song('piano', 'Soft Piano', 'Calm Artist'),
          source: 'youtube_radio',
        ),
        RecommendationCandidate(
          item: song('metal', 'Metal Storm', 'Heavy Artist'),
          source: 'youtube_radio',
        ),
      ],
      profile: profile(),
      session: FlowSession.start(tuner: tuner),
      tuner: tuner,
      blacklist: blacklist,
      limit: 2,
    );

    expect(planned.first.item.id, 'metal');
    expect(planned.first.reasonCodes, contains('genre_match'));
  });

  test('chill and energy modes choose different leaders', () {
    final candidates = [
      RecommendationCandidate(
        item: song('chill', 'Calm Ambient Evening', 'Soft Artist'),
        source: 'youtube_radio',
      ),
      RecommendationCandidate(
        item: song('energy', 'Workout Dance Energy', 'Fast Artist'),
        source: 'youtube_radio',
      ),
    ];
    final session = FlowSession.start(tuner: FlowTunerSettings.defaults());

    List<FlowQueueItem> plan(FlowMode mode) {
      final tuner = FlowTunerSettings.defaults().copyWith(mode: mode);
      return FlowQueuePlanner().planNext(
        candidates: candidates,
        profile: profile(),
        session: session,
        tuner: tuner,
        blacklist: blacklist,
        limit: 2,
      );
    }

    expect(plan(FlowMode.chill).first.item.id, 'chill');
    expect(plan(FlowMode.energy).first.item.id, 'energy');
  });

  test('recently played tracks receive a cooldown penalty', () {
    final recent = song('recent', 'Recent', 'Artist A');
    final fresh = song('fresh', 'Fresh', 'Artist B');
    final recentKey = RecommendationMediaJson.normalizedSongKey(recent);
    final taste = TasteProfile(
      recentSeeds: const [],
      topArtists: const {},
      skippedArtists: const {},
      playedSongIds: {'recent'},
      likedSongIds: const {},
      dismissedSongIds: const {},
      playedSongKeys: {recentKey},
      lastPlayedAtBySongKey: {
        recentKey: DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      },
    );

    final planned = FlowQueuePlanner().planNext(
      candidates: [
        RecommendationCandidate(item: recent, source: 'youtube_radio'),
        RecommendationCandidate(item: fresh, source: 'youtube_radio'),
      ],
      profile: taste,
      session: FlowSession.start(tuner: FlowTunerSettings.defaults()),
      tuner: FlowTunerSettings.defaults(),
      blacklist: blacklist,
      limit: 2,
    );

    expect(planned.first.item.id, 'fresh');
  });
}
