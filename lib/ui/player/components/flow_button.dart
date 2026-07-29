import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../player_controller.dart';
import 'flow_tuner_sheet.dart';

class FlowButton extends StatelessWidget {
  const FlowButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final appPrefs = Hive.box('AppPrefs');
    return ValueListenableBuilder<Box>(
      valueListenable: appPrefs.listenable(keys: const ['flowEnabled']),
      builder: (context, box, _) {
        if (!(box.get('flowEnabled') ?? true)) {
          return const SizedBox.shrink();
        }
        return Obx(() {
          final active = playerController.isFlowModeOn.value;
          final loading = playerController.isFlowStarting.value;
          return IconButton(
            tooltip: loading
                ? 'Building Flow queue'
                : active
                    ? 'Tune Flow'
                    : 'Start Flow',
            iconSize: compact ? 20 : 24,
            onPressed: loading
                ? null
                : () {
                    if (!(appPrefs.get('flowEnabled') ?? true)) return;
                    if (active) {
                      _showTuner(context);
                    } else {
                      playerController.startFlow();
                    }
                  },
            icon: loading
                ? SizedBox.square(
                    dimension: compact ? 16 : 19,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    active ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                    color: active
                        ? Theme.of(context).colorScheme.secondary
                        : Theme.of(context).iconTheme.color,
                  ),
          );
        });
      },
    );
  }

  static void showTuner(BuildContext context) => _showTuner(context);

  static void _showTuner(BuildContext context) {
    if (GetPlatform.isDesktop) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: const SingleChildScrollView(child: FlowTunerSheet()),
          ),
        ),
      );
      return;
    }
    showModalBottomSheet(
      constraints: const BoxConstraints(maxWidth: 520),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
      ),
      isScrollControlled: true,
      context: context,
      barrierColor: Colors.transparent.withAlpha(100),
      builder: (context) => const FlowTunerSheet(),
    );
  }
}
