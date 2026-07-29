import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/playback_request_guard.dart';

void main() {
  test('only the newest playback request may commit', () {
    final guard = PlaybackRequestGuard();
    final oldRequest = guard.begin();
    final newRequest = guard.begin();

    expect(guard.matches(oldRequest), isFalse);
    expect(guard.matches(newRequest), isTrue);
  });

  test('cancel invalidates an in-flight request', () {
    final guard = PlaybackRequestGuard();
    final request = guard.begin();

    guard.cancel();

    expect(guard.matches(request), isFalse);
  });
}
