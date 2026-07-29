import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/recommendation/playback_signal_gate.dart';

void main() {
  test('records play start only after five seconds of real progression', () {
    final gate = PlaybackSignalGate()..begin('song');

    expect(
      gate.shouldRecordPlayStart(
        const Duration(seconds: 80),
        isPlaying: true,
      ),
      isFalse,
    );
    expect(
      gate.shouldRecordPlayStart(
        const Duration(seconds: 84),
        isPlaying: true,
      ),
      isFalse,
    );
    expect(
      gate.shouldRecordPlayStart(
        const Duration(seconds: 85),
        isPlaying: true,
      ),
      isTrue,
    );
    expect(
      gate.shouldRecordPlayStart(
        const Duration(seconds: 90),
        isPlaying: true,
      ),
      isFalse,
    );
  });

  test('does not count buffering or failed playback as a start', () {
    final gate = PlaybackSignalGate()..begin('song');

    expect(
      gate.shouldRecordPlayStart(Duration.zero, isPlaying: false),
      isFalse,
    );
    expect(
      gate.shouldRecordPlayStart(
        const Duration(seconds: 10),
        isPlaying: false,
      ),
      isFalse,
    );
    expect(gate.playStartRecorded, isFalse);
  });

  test('ignores seek jumps while accumulating real forward playback', () {
    final gate = PlaybackSignalGate()..begin('song');

    expect(
      gate.shouldRecordPlayStart(Duration.zero, isPlaying: true),
      isFalse,
    );
    expect(
      gate.shouldRecordPlayStart(
        const Duration(seconds: 2),
        isPlaying: true,
      ),
      isFalse,
    );
    expect(
      gate.shouldRecordPlayStart(
        const Duration(seconds: 80),
        isPlaying: true,
      ),
      isFalse,
    );
    expect(
      gate.shouldRecordPlayStart(
        const Duration(seconds: 82),
        isPlaying: true,
      ),
      isFalse,
    );
    expect(
      gate.shouldRecordPlayStart(
        const Duration(seconds: 83),
        isPlaying: true,
      ),
      isTrue,
    );
  });

  test('same song restarts only for a new playback session', () {
    final gate = PlaybackSignalGate()
      ..begin('song', playbackSessionId: 'request-1');

    gate.shouldRecordPlayStart(Duration.zero, isPlaying: true);
    gate.shouldRecordPlayStart(
      const Duration(seconds: 4),
      isPlaying: true,
    );

    gate.begin('song', playbackSessionId: 'request-1');
    expect(
      gate.shouldRecordPlayStart(
        const Duration(seconds: 5),
        isPlaying: true,
      ),
      isTrue,
    );

    gate.begin('song', playbackSessionId: 'request-2');
    expect(gate.playStartRecorded, isFalse);
    expect(
      gate.shouldRecordPlayStart(Duration.zero, isPlaying: true),
      isFalse,
    );
    expect(
      gate.shouldRecordPlayStart(
        const Duration(seconds: 5),
        isPlaying: true,
      ),
      isTrue,
    );
  });

  test('completion suppresses an early-skip signal', () {
    final gate = PlaybackSignalGate()..begin('song');
    gate.shouldRecordPlayStart(Duration.zero, isPlaying: true);
    gate.shouldRecordPlayStart(const Duration(seconds: 5), isPlaying: true);

    expect(
      gate.shouldRecordCompletion(
        const Duration(seconds: 70),
        const Duration(seconds: 100),
      ),
      isTrue,
    );
    expect(
      gate.shouldRecordEarlySkip(
        const Duration(seconds: 71),
        const Duration(seconds: 100),
      ),
      isFalse,
    );
  });
}
