import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ionicons/ionicons.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '/ui/player/components/animated_play_button.dart';
import '../player_controller.dart';
import 'flow_button.dart';

class PlayerControlWidget extends StatelessWidget {
  const PlayerControlWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: ShaderMask(
                  shaderCallback: (rect) {
                    return const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.transparent
                      ],
                    ).createShader(
                        Rect.fromLTWH(0, 0, rect.width, rect.height));
                  },
                  blendMode: BlendMode.dstIn,
                  child: Obx(() {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Marquee(
                          delay: const Duration(milliseconds: 300),
                          duration: const Duration(seconds: 10),
                          id: "${playerController.currentSong.value}_title",
                          child: Text(
                            playerController.currentSong.value != null
                                ? playerController.currentSong.value!.title
                                : "NA",
                            textAlign: TextAlign.start,
                            style: Theme.of(context).textTheme.labelMedium!,
                          ),
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        Marquee(
                          delay: const Duration(milliseconds: 300),
                          duration: const Duration(seconds: 10),
                          id: "${playerController.currentSong.value}_subtitle",
                          child: Text(
                            playerController.currentSong.value != null
                                ? playerController.currentSong.value!.artist!
                                : "NA",
                            textAlign: TextAlign.start,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        )
                      ],
                    );
                  }),
                ),
              ),
              SizedBox(
                width: 45,
                child: IconButton(
                    onPressed: playerController.toggleFavourite,
                    icon: Obx(() => Icon(
                          playerController.isCurrentSongFav.isFalse
                              ? Icons.favorite_border
                              : Icons.favorite,
                          color: Theme.of(context).textTheme.titleMedium!.color,
                        ))),
              ),
            ],
          ),
          const SizedBox(
            height: 20,
          ),
          GetX<PlayerController>(builder: (controller) {
            return ProgressBar(
              thumbRadius: 7,
              barHeight: 4.5,
              baseBarColor: Theme.of(context).sliderTheme.inactiveTrackColor,
              bufferedBarColor:
                  Theme.of(context).sliderTheme.valueIndicatorColor,
              progressBarColor: Theme.of(context).sliderTheme.activeTrackColor,
              thumbColor: Theme.of(context).sliderTheme.thumbColor,
              timeLabelTextStyle: Theme.of(context)
                  .textTheme
                  .titleMedium!
                  .copyWith(fontSize: 14),
              progress: controller.progressBarStatus.value.current,
              total: controller.progressBarStatus.value.total,
              buffered: controller.progressBarStatus.value.buffered,
              onSeek: controller.seek,
            );
          }),
          ResponsivePlayerTransportControls(
            flowButton: const FlowButton(),
            dislikeButton: _dislikeButton(playerController, context),
            shuffleButton: _shuffleButton(playerController, context),
            previousButton: _previousButton(playerController, context),
            playButton: const CircleAvatar(
              radius: 35,
              child: AnimatedPlayButton(key: Key("playButton")),
            ),
            nextButton: _nextButton(playerController, context),
            loopButton: _loopButton(playerController, context),
          ),
        ]);
  }

  Widget _dislikeButton(
      PlayerController playerController, BuildContext context) {
    return Obx(() => IconButton(
          tooltip: "Don't recommend",
          onPressed: playerController.currentSong.value == null
              ? null
              : () => playerController.dislikeCurrentSong(),
          icon: Icon(
            Icons.thumb_down_alt_outlined,
            color: Theme.of(context).textTheme.titleMedium!.color,
          ),
        ));
  }

  Widget _shuffleButton(
      PlayerController playerController, BuildContext context) {
    return IconButton(
      onPressed: playerController.toggleShuffleMode,
      icon: Obx(() => Icon(
            Ionicons.shuffle,
            color: playerController.isShuffleModeEnabled.value
                ? Theme.of(context).textTheme.titleLarge!.color
                : Theme.of(context)
                    .textTheme
                    .titleLarge!
                    .color!
                    .withOpacity(0.2),
          )),
    );
  }

  Widget _loopButton(PlayerController playerController, BuildContext context) {
    return Obx(() => IconButton(
          onPressed: playerController.toggleLoopMode,
          icon: Icon(
            Icons.all_inclusive,
            color: playerController.isLoopModeEnabled.value
                ? Theme.of(context).textTheme.titleLarge!.color
                : Theme.of(context)
                    .textTheme
                    .titleLarge!
                    .color!
                    .withOpacity(0.2),
          ),
        ));
  }

  Widget _previousButton(
      PlayerController playerController, BuildContext context) {
    return Obx(() {
      final canGoPrevious = playerController.canSkipToPrevious;
      return IconButton(
        icon: Icon(
          Icons.skip_previous,
          color: !canGoPrevious
              ? Theme.of(context).textTheme.titleLarge!.color!.withOpacity(0.2)
              : Theme.of(context).textTheme.titleMedium!.color,
        ),
        iconSize: 30,
        onPressed: canGoPrevious ? playerController.prev : null,
      );
    });
  }
}

class ResponsivePlayerTransportControls extends StatelessWidget {
  const ResponsivePlayerTransportControls({
    super.key,
    required this.flowButton,
    required this.dislikeButton,
    required this.shuffleButton,
    required this.previousButton,
    required this.playButton,
    required this.nextButton,
    required this.loopButton,
  });

  static const compactBreakpoint = 380.0;

  final Widget flowButton;
  final Widget dislikeButton;
  final Widget shuffleButton;
  final Widget previousButton;
  final Widget playButton;
  final Widget nextButton;
  final Widget loopButton;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= compactBreakpoint) {
        return SizedBox(
          height: 70,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              flowButton,
              dislikeButton,
              shuffleButton,
              previousButton,
              playButton,
              nextButton,
              loopButton,
            ],
          ),
        );
      }

      return SizedBox(
        height: 122,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 70,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  previousButton,
                  const SizedBox(width: 12),
                  playButton,
                  const SizedBox(width: 12),
                  nextButton,
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  flowButton,
                  dislikeButton,
                  shuffleButton,
                  loopButton,
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

Widget _nextButton(PlayerController playerController, BuildContext context) {
  return Obx(() {
    final canGoNext = playerController.canSkipToNext;
    return IconButton(
        icon: Icon(
          Icons.skip_next,
          color: !canGoNext
              ? Theme.of(context).textTheme.titleLarge!.color!.withOpacity(0.2)
              : Theme.of(context).textTheme.titleMedium!.color,
        ),
        iconSize: 30,
        onPressed: canGoNext ? playerController.next : null);
  });
}
