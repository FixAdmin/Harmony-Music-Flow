import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/flow/flow_models.dart';

class FlowDebugLogger extends GetxService {
  static const maxEntries = 200;
  static const enabledPreferenceKey = 'showFlowDebugEnabled';

  Box get _box => Hive.box('FlowDebugLog');

  bool get isEnabled {
    if (!Hive.isBoxOpen('AppPrefs')) return false;
    return Hive.box('AppPrefs').get(enabledPreferenceKey) ?? false;
  }

  Future<void> logDecision(FlowQueueItem item) async {
    if (!isEnabled) return;
    await _box.add({
      'sessionId': item.sessionId,
      'songId': item.item.id,
      'title': item.item.title,
      'artist': item.item.artist,
      'score': item.score,
      'source': item.source,
      'reasonCodes': item.reasonCodes,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await trim();
  }

  Future<void> logDecisions(List<FlowQueueItem> items) async {
    if (!isEnabled) return;
    for (final item in items) {
      await _box.add({
        'sessionId': item.sessionId,
        'songId': item.item.id,
        'title': item.item.title,
        'artist': item.item.artist,
        'score': item.score,
        'source': item.source,
        'reasonCodes': item.reasonCodes,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
    await trim();
  }

  List<Map<dynamic, dynamic>> entries() {
    return _box.values.whereType<Map>().toList().reversed.toList();
  }

  Future<void> clear() => _box.clear();

  Future<void> trim() async {
    final overflow = _box.length - maxEntries;
    if (overflow <= 0) return;
    for (var i = 0; i < overflow; i++) {
      await _box.deleteAt(0);
    }
  }
}
