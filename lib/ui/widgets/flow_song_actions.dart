import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../player/player_controller.dart';
import 'snackbar.dart';

class FlowSongActions extends StatelessWidget {
  const FlowSongActions({super.key, required this.song});

  final MediaItem song;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final appPrefs = Hive.box('AppPrefs');
    void showFlowSnack(String message) {
      final snackContext = playerController.homeScaffoldkey.currentContext ??
          Get.context ??
          context;
      ScaffoldMessenger.of(snackContext).showSnackBar(
        snackbar(snackContext, message, size: SanckBarSize.MEDIUM),
      );
    }

    Future<void> runAction(
      Future<void> Function() action,
      String successMessage,
    ) async {
      if (!(appPrefs.get('flowEnabled') ?? true)) return;
      Navigator.of(context).pop();
      await action();
      if (!(appPrefs.get('flowEnabled') ?? true)) return;
      showFlowSnack(successMessage);
    }

    return ValueListenableBuilder<Box>(
      valueListenable: appPrefs.listenable(keys: const ['flowEnabled']),
      builder: (context, box, _) {
        if (!(box.get('flowEnabled') ?? true)) {
          return const SizedBox.shrink();
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              visualDensity: const VisualDensity(vertical: -1),
              leading: const Icon(Icons.auto_awesome),
              title: const Text('More like this'),
              onTap: () => runAction(
                () => playerController.moreLikeThis(song),
                'Flow will play more like this',
              ),
            ),
            ListTile(
              visualDensity: const VisualDensity(vertical: -1),
              leading: const Icon(Icons.thumb_down_alt_outlined),
              title: const Text('Play less like this'),
              onTap: () => runAction(
                () => playerController.playLessLikeThis(song),
                'Flow will play less like this',
              ),
            ),
            ListTile(
              visualDensity: const VisualDensity(vertical: -1),
              leading: const Icon(Icons.block),
              title: const Text("Don't play this track"),
              onTap: () => runAction(
                () => playerController.blockTrackFromFlow(song),
                'Track blocked from Flow',
              ),
            ),
            ListTile(
              visualDensity: const VisualDensity(vertical: -1),
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Less from this artist'),
              onTap: () => runAction(
                () => playerController.blockArtistFromFlow(song),
                'Artist blocked from Flow',
              ),
            ),
          ],
        );
      },
    );
  }
}
