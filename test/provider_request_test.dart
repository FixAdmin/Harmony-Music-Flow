import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/recommendation/provider_request.dart';

void main() {
  test('returns fallback when a provider never completes', () async {
    final pending = Completer<List<int>>();

    final result = await ProviderRequest.resolve(
      pending.future,
      timeout: const Duration(milliseconds: 20),
      fallback: const <int>[],
    );

    expect(result, isEmpty);
  });

  test('returns fallback when a provider throws', () async {
    final result = await ProviderRequest.resolve(
      Future<int>.error(StateError('provider failed')),
      timeout: const Duration(seconds: 1),
      fallback: -1,
    );

    expect(result, -1);
  });
}
