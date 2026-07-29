import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/flow/flow_models.dart';
import 'package:harmonymusic/services/flow/flow_tuner.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flow_tuner_test');
    Hive.init(tempDir.path);
    await Hive.openBox('FlowTunerPresets');
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('FlowTunerSettings serializes default auto mode', () {
    final settings = FlowTunerSettings.defaults();
    final copy = FlowTunerSettings.fromJson(settings.toJson());

    expect(copy.mode, FlowMode.auto);
    expect(copy.familiarity, 0.55);
    expect(copy.variety, 0.55);
    expect(copy.deepCuts, 0.35);
    expect(copy.genres, isEmpty);
  });

  test('FlowTuner clamps sliders and persists genre changes', () async {
    final tuner = FlowTuner();
    tuner.onInit();

    await tuner.setFamiliarity(2);
    await tuner.setVariety(-1);
    await tuner.toggleGenre('Electronic');

    expect(tuner.current.value.familiarity, 1);
    expect(tuner.current.value.variety, 0);
    expect(tuner.current.value.genres, contains('Electronic'));

    final restored = FlowTuner();
    restored.onInit();
    expect(restored.current.value.genres, contains('Electronic'));
  });
}
