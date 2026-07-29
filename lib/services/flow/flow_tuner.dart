import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/flow/flow_models.dart';

class FlowTuner extends GetxService {
  final current = FlowTunerSettings.defaults().obs;

  Box get _box => Hive.box('FlowTunerPresets');

  @override
  void onInit() {
    load();
    super.onInit();
  }

  void load() {
    final raw = _box.get('current');
    if (raw is Map) {
      current.value = FlowTunerSettings.fromJson(raw);
    }
  }

  Future<void> setMode(FlowMode mode) {
    return _save(current.value.copyWith(mode: mode));
  }

  Future<void> setFamiliarity(double value) {
    return _save(current.value.copyWith(familiarity: value));
  }

  Future<void> setVariety(double value) {
    return _save(current.value.copyWith(variety: value));
  }

  Future<void> setDeepCuts(double value) {
    return _save(current.value.copyWith(deepCuts: value));
  }

  Future<void> toggleGenre(String genre) {
    final normalized = genre.trim();
    if (normalized.isEmpty) return Future.value();

    final genres = Set<String>.from(current.value.genres);
    if (genres.contains(normalized)) {
      genres.remove(normalized);
    } else {
      genres.add(normalized);
    }
    return _save(current.value.copyWith(genres: genres));
  }

  Future<void> reset() {
    return _save(FlowTunerSettings.defaults());
  }

  Future<void> applySettings(FlowTunerSettings settings) {
    return _save(settings);
  }

  void restoreSettings(FlowTunerSettings settings) {
    current.value = settings;
  }

  Future<void> _save(FlowTunerSettings settings) async {
    current.value = settings;
    await _box.put('current', settings.toJson());
  }
}
