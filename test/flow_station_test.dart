import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/flow/flow_models.dart';
import 'package:harmonymusic/models/flow/flow_station.dart';

void main() {
  FlowStation station() {
    return const FlowStation(
      id: 'cinematic',
      title: 'Cinematic',
      subtitle: 'Epic strings and soundtracks',
      tags: ['soundtrack', 'orchestral'],
      seedTerms: ['cinematic', 'trailer'],
      searchQueries: ['cinematic orchestral music'],
      modeName: 'discover',
      familiarity: .45,
      variety: .7,
      deepCuts: .55,
      localWeight: .35,
      externalWeight: .65,
      confidence: .8,
      reason: 'matched orchestral history',
      previewSong: null,
    );
  }

  test('round trips station json', () {
    final restored = FlowStation.fromJson(station().toJson());

    expect(restored.id, 'cinematic');
    expect(restored.tags, contains('soundtrack'));
    expect(restored.searchQueries, contains('cinematic orchestral music'));
    expect(restored.confidence, .8);
  });

  test('round trips station preview song', () {
    final source = station().copyWith(
      previewSong: MediaItem(
        id: 'track_1',
        title: 'Epic Strings',
        artist: 'Score Artist',
        artUri: Uri.parse('https://example.com/art.jpg'),
      ),
    );
    final restored = FlowStation.fromJson(source.toJson());

    expect(restored.previewSong?.id, 'track_1');
    expect(restored.previewSong?.title, 'Epic Strings');
    expect(
        restored.previewSong?.artUri.toString(), 'https://example.com/art.jpg');
  });

  test('flow session remains backward compatible without station', () {
    final session = FlowSession.fromJson({
      'id': 'flow_1',
      'startedAt': DateTime(2026).millisecondsSinceEpoch,
      'tuner': FlowTunerSettings.defaults().toJson(),
      'seedSongIds': const ['a'],
      'skipStreak': 0,
      'isActive': true,
    });

    expect(session.station, isNull);
    expect(session.toJson().containsKey('station'), isFalse);
  });

  test('flow session persists station snapshot', () {
    final session = FlowSession.start(
      tuner: FlowTunerSettings.defaults(),
      station: station(),
    );
    final restored = FlowSession.fromJson(session.toJson());

    expect(restored.station?.id, 'cinematic');
    expect(restored.station?.title, 'Cinematic');
  });
}
