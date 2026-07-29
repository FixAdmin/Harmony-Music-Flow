import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/natural_completion_guard.dart';

void main() {
  const duration = Duration(minutes: 3);
  const terminalOffset = Duration(milliseconds: 200);

  test('claims a natural completion only once per playback request', () {
    final guard = NaturalCompletionGuard()..begin(10);

    expect(
      guard.observe(
        requestId: 10,
        position: const Duration(minutes: 2, seconds: 58),
        duration: duration,
        terminalOffset: terminalOffset,
      ),
      isFalse,
    );
    expect(
      guard.observe(
        requestId: 10,
        position: const Duration(minutes: 2, seconds: 59, milliseconds: 900),
        duration: duration,
        terminalOffset: terminalOffset,
      ),
      isTrue,
    );
    expect(
      guard.observe(
        requestId: 10,
        position: duration,
        duration: duration,
        terminalOffset: terminalOffset,
      ),
      isFalse,
    );
  });

  test('rejects a stale terminal event after the next request begins', () {
    final guard = NaturalCompletionGuard()..begin(10);
    guard.observe(
      requestId: 10,
      position: const Duration(minutes: 2, seconds: 58),
      duration: duration,
      terminalOffset: terminalOffset,
    );

    guard.begin(11);

    expect(
      guard.observe(
        requestId: 11,
        position: duration,
        duration: duration,
        terminalOffset: terminalOffset,
      ),
      isFalse,
    );
  });

  test('accepts completion after the new request reaches its own ending', () {
    final guard = NaturalCompletionGuard()..begin(11);

    expect(
      guard.observe(
        requestId: 11,
        position: const Duration(minutes: 2, seconds: 57),
        duration: duration,
        terminalOffset: terminalOffset,
      ),
      isFalse,
    );
    expect(
      guard.observe(
        requestId: 11,
        position: const Duration(minutes: 2, seconds: 59, milliseconds: 850),
        duration: duration,
        terminalOffset: terminalOffset,
      ),
      isTrue,
    );
  });

  test('a backwards jump leaves completion unarmed', () {
    final guard = NaturalCompletionGuard()..begin(12);
    guard.observe(
      requestId: 12,
      position: const Duration(minutes: 2, seconds: 58),
      duration: duration,
      terminalOffset: terminalOffset,
    );
    guard.observe(
      requestId: 12,
      position: const Duration(seconds: 1),
      duration: duration,
      terminalOffset: terminalOffset,
    );

    expect(
      guard.observe(
        requestId: 12,
        position: duration,
        duration: duration,
        terminalOffset: terminalOffset,
      ),
      isFalse,
    );
  });
}
