import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/recommendation_item.dart';
import 'package:harmonymusic/models/taste_profile.dart';
import 'package:harmonymusic/services/flow/flow_station_service.dart';

void main() {
  MediaItem song(
    String id,
    String title,
    String artist, {
    String? album,
    String? art,
  }) {
    return MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album,
      artUri: art == null ? null : Uri.parse(art),
    );
  }

  TasteProfile profile(List<MediaItem> seeds) {
    return TasteProfile(
      recentSeeds: seeds,
      topArtists: {
        for (final seed in seeds) seed.artist ?? '': 2,
      },
      skippedArtists: const {},
      playedSongIds: seeds.map((item) => item.id).toSet(),
      likedSongIds: const {},
      dismissedSongIds: const {},
    );
  }

  test('promotes cinematic station for orchestral history', () {
    final stations = FlowStationService().buildStations(profile([
      song('1', 'Epic Orchestral Strings', 'Trailer Music'),
      song('2', 'Vivaldi Winter Violin Concerto', 'Classical Ensemble'),
      song('3', 'Dark Symphony OST', 'Soundtrack Orchestra'),
    ]));

    expect(stations.first.id, 'cinematic');
    expect(stations.first.confidence, greaterThan(.4));
    expect(stations.first.seedTerms, contains('orchestral'));
  });

  test('returns cold start stations without listening signals', () {
    final stations = FlowStationService().buildStations(TasteProfile(
      recentSeeds: const [],
      topArtists: const {},
      skippedArtists: const {},
      playedSongIds: const {},
      likedSongIds: const {},
      dismissedSongIds: const {},
    ));

    expect(stations.length, greaterThanOrEqualTo(4));
    expect(stations.map((station) => station.id), contains('discover'));
  });

  test('does not reuse the same preview song across stations', () {
    final stations = FlowStationService().buildStations(profile([
      song(
        'shared',
        'Dark Violin Metal Epic Orchestral Gaming Energy',
        'Kopisatu Music',
        art: 'https://example.com/shared.jpg',
      ),
      song(
        'night',
        'Midnight Ambient Focus',
        'Touch Factory',
        art: 'https://example.com/night.jpg',
      ),
      song(
        'energy',
        'Workout Dance Energy',
        'Drive Artist',
        art: 'https://example.com/energy.jpg',
      ),
    ]));

    final previewIds = stations
        .map((station) => station.previewSong?.id)
        .whereType<String>()
        .toList();

    expect(previewIds.toSet().length, previewIds.length);
  });

  test('previews do not reuse canonical tracks or artwork URLs', () {
    final stations = FlowStationService().buildStations(profile([
      song(
        'broad-a',
        'Epic Orchestral Gaming Focus Instrumental Energy Dance Night Dark',
        'Nova',
        art: 'https://example.com/shared.jpg',
      ),
      song(
        'broad-b',
        'Epic Orchestral Gaming Focus Instrumental Energy Dance Night Dark '
            '(Official Audio)',
        'Nova',
        art: 'https://example.com/alternate.jpg',
      ),
      song(
        'gaming',
        'Gaming Focus Electronic Instrumental',
        'Pulse',
        art: 'https://example.com/gaming.jpg',
      ),
      song(
        'energy-shared-art',
        'Workout Dance Energy Metal',
        'Drive A',
        art: 'https://example.com/shared.jpg',
      ),
      song(
        'energy-alternative',
        'Workout Dance Energy Rock',
        'Drive B',
        art: 'https://example.com/energy.jpg',
      ),
      song(
        'night',
        'Night Dark Slow Ambient',
        'Moon',
        art: 'https://example.com/night.jpg',
      ),
    ]));
    final previews = stations
        .map((station) => station.previewSong)
        .whereType<MediaItem>()
        .toList();
    final canonicalKeys =
        previews.map(RecommendationMediaJson.normalizedSongKey).toList();
    final artUrls = previews
        .map((item) => item.artUri?.toString())
        .whereType<String>()
        .toList();

    expect(previews.length, greaterThanOrEqualTo(4));
    expect(canonicalKeys.toSet(), hasLength(canonicalKeys.length));
    expect(artUrls.toSet(), hasLength(artUrls.length));
  });

  test('creates adaptive stations from repeated external tags', () {
    final stations = FlowStationService().buildStations(
      profile([
        song('1', 'Dream Synthpop', 'Nova'),
        song('2', 'Night Synthpop', 'Echo'),
      ]),
      externalTags: const [
        'synthpop',
        'synthpop',
        'synthpop',
        'post-rock',
        'post-rock',
      ],
    );

    expect(stations.first.id, 'tag_synthpop');
    expect(stations.first.searchQueries, contains('synthpop music'));
  });
}
