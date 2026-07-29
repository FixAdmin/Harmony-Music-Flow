import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/flow/flow_models.dart';
import 'package:harmonymusic/services/flow/flow_debug_logger.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flow_debug_test');
    Hive.init(tempDir.path);
    await Hive.openBox('FlowDebugLog');
    await Hive.openBox('AppPrefs');
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('keeps only the newest 200 decisions', () async {
    await Hive.box('AppPrefs').put('showFlowDebugEnabled', true);
    final logger = FlowDebugLogger();
    await logger.logDecisions(List.generate(205, (index) {
      return FlowQueueItem(
        item: MediaItem(id: '$index', title: 'Track $index', artist: 'Artist'),
        sessionId: 'session',
        score: index.toDouble(),
        locked: false,
        reasonCodes: const ['test'],
        source: 'youtube_radio',
      );
    }));

    final entries = logger.entries();
    expect(entries, hasLength(200));
    expect(entries.first['songId'], '204');
    expect(entries.last['songId'], '5');
  });

  test('does not log when flow debug is disabled by default', () async {
    final logger = FlowDebugLogger();

    await logger.logDecision(const FlowQueueItem(
      item: MediaItem(id: 'disabled', title: 'Track', artist: 'Artist'),
      sessionId: 'session',
      score: 1,
      locked: false,
      reasonCodes: ['test'],
      source: 'youtube_radio',
    ));

    expect(logger.entries(), isEmpty);
  });
}
