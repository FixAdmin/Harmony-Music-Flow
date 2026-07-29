import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/flow/flow_queue_policy.dart';

void main() {
  MediaItem song(String id, String title, String artist) {
    return MediaItem(id: id, title: title, artist: artist);
  }

  test('late planning preserves the track that is playing now', () {
    final first = song('first', 'First', 'Alpha');
    final current = song('current', 'Current', 'Beta');
    final staleUpcoming = song('stale', 'Stale', 'Gamma');
    final planned = song('planned', 'Planned', 'Delta');

    final result = FlowQueuePolicy.mergeUpcoming(
      queue: [first, current, staleUpcoming],
      currentSong: current,
      planned: [planned],
      replaceUpcoming: true,
    );

    expect(result.map((item) => item.id), ['first', 'current', 'planned']);
  });

  test('negative feedback removes matches only after the current track', () {
    final current = song('current', 'Current', 'Alpha');
    final sameArtist = song('same-artist', 'Other', 'Alpha feat. Beta');
    final alternateUpload = song('alt', 'Blocked', 'Gamma');
    final blocked = song('blocked', 'Blocked', 'Gamma');
    final safe = song('safe', 'Safe', 'Delta');

    final result = FlowQueuePolicy.mergeUpcoming(
      queue: [current, sameArtist, alternateUpload, safe],
      currentSong: current,
      planned: const [],
      removeSong: blocked,
      removeArtist: 'Alpha',
    );

    expect(result.map((item) => item.id), ['current', 'safe']);
  });

  test('planned alternate uploads are canonically deduplicated', () {
    final current = song('current', 'Current', 'Alpha');
    final first = song('upload-a', 'Same Song', 'Beta');
    final duplicate = song('upload-b', 'Same Song', 'Beta');

    final result = FlowQueuePolicy.mergeUpcoming(
      queue: [current],
      currentSong: current,
      planned: [first, duplicate],
    );

    expect(result.map((item) => item.id), ['current', 'upload-a']);
  });

  test('queue end only stays actionable for an active continuation mode', () {
    expect(
      FlowQueuePolicy.canRequestNext(
        hasCurrentSong: true,
        hasQueue: true,
        isAtQueueEnd: true,
        isFlowActive: false,
        isRadioActive: false,
      ),
      isFalse,
    );
    expect(
      FlowQueuePolicy.canRequestNext(
        hasCurrentSong: true,
        hasQueue: true,
        isAtQueueEnd: true,
        isFlowActive: true,
        isRadioActive: false,
      ),
      isTrue,
    );
  });
}
