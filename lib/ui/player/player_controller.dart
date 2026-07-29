import 'dart:async';
import 'package:flutter_lyric/lyric_ui/ui_netease.dart';
import 'package:hive/hive.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';

import '../../models/playling_from.dart';
import '../../models/flow/flow_models.dart';
import '../../models/flow/flow_station.dart';
import '../../models/recommendation_item.dart';
import '../../services/flow/flow_service.dart';
import '../../services/flow/flow_queue_policy.dart';
import '../../services/flow/flow_tuner.dart';
import '../../services/library/blacklist_service.dart';
import '../../services/library/library_automation_service.dart';
import '../screens/Playlist/playlist_screen_controller.dart';
import '../widgets/snackbar.dart';
import '/services/synced_lyrics_service.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../services/windows_audio_service.dart';
import '../../utils/helper.dart';
import '/models/media_Item_builder.dart';
import '../screens/Home/home_screen_controller.dart';
import '../widgets/sliding_up_panel.dart';
import '/models/durationstate.dart';
import '/services/music_service.dart';
import '/services/playback_audit_log_service.dart';
import '/services/recommendation/candidate_provider.dart';
import '/services/recommendation/feedback_tracker.dart';
import '/services/recommendation/playback_signal_gate.dart';

class PlayerController extends GetxController
    with GetSingleTickerProviderStateMixin {
  final _audioHandler = Get.find<AudioHandler>();
  final _musicServices = Get.find<MusicServices>();
  final _playbackAuditLog = Get.find<PlaybackAuditLogService>();
  final _candidateProvider = Get.find<CandidateProvider>();
  final _feedbackTracker = Get.find<FeedbackTracker>();
  final _flowService = Get.find<FlowService>();
  final _libraryAutomation = Get.find<LibraryAutomationService>();
  final _blacklistService = Get.find<BlacklistService>();
  final currentQueue = <MediaItem>[].obs;

  final playerPaneOpacity = (1.0).obs;
  final isPlayerpanelTopVisible = true.obs;
  final isPanelGTHOpened = false.obs;
  final playerPanelMinHeight = 0.0.obs;
  bool initFlagForPlayer = true;
  final isQueueReorderingInProcess = false.obs;
  PanelController playerPanelController = PanelController();
  PanelController queuePanelController = PanelController();
  AnimationController? gesturePlayerStateAnimationController;
  Animation<double>? gesturePlayerStateAnimation;
  bool isRadioModeOn = false;
  final isFlowModeOn = false.obs;
  final isFlowStarting = false.obs;
  bool _flowRefillInProgress = false;
  int _flowLaunchGeneration = 0;
  Future<void> _flowRebuildTail = Future<void>.value();
  Completer<void>? _flowLaunchCompleter;
  String? radioContinuationParam;
  dynamic radioInitiatorItem;
  Timer? sleepTimer;
  int timerDuration = 0;
  final timerDurationLeft = 0.obs;
  final isSleepTimerActive = false.obs;
  final isSleepEndOfSongActive = false.obs;
  final volume = 100.obs;

  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero, current: Duration.zero, total: Duration.zero)
      .obs;

  final currentSongIndex = (0).obs;
  final isFirstSong = true;
  final isLastSong = true;
  final isQueueLoopModeEnabled = false.obs;
  final isLoopModeEnabled = false.obs;
  final isShuffleModeEnabled = false.obs;
  final currentSong = Rxn<MediaItem>();
  final isCurrentSongFav = false.obs;
  final playinfrom = PlaylingFrom(type: PlaylingFromType.SELECTION).obs;
  final showLyricsflag = false.obs;
  final isLyricsLoading = false.obs;
  final lyricsMode = 0.obs;
  bool isDesktopLyricsDialogOpen = false;
  // 0 for play, 1 for pause, 2 for blank
  final gesturePlayerVisibleState = 2.obs;
  final lyricUi =
      UINetease(highlight: true, defaultSize: 20, defaultExtSize: 12);
  RxMap<String, dynamic> lyrics =
      <String, dynamic>{"synced": "", "plainLyrics": ""}.obs;
  ScrollController scrollController = ScrollController();
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();

  final buttonState = PlayButtonState.paused.obs;

  // track whether wakelock is currently enabled to avoid repeated calls
  bool _wakelockActive = false;
  final PlaybackSignalGate _playbackSignalGate = PlaybackSignalGate();
  String _recommendationSessionSource = 'unknown';
  String? _recommendationFlowSessionId;

  var _newSongFlag = true;
  final isCurrentSongBuffered = false.obs;

  bool get isAtNaturalQueueEnd {
    final song = currentSong.value;
    if (song == null || currentQueue.isEmpty) return true;
    if (currentQueue.length == 1) return true;
    if (isShuffleModeEnabled.isTrue || isQueueLoopModeEnabled.isTrue) {
      return false;
    }
    return currentQueue.last.id == song.id;
  }

  bool get isFlowEnabled => _flowService.isEnabled;

  bool get canSkipToNext {
    return FlowQueuePolicy.canRequestNext(
      hasCurrentSong: currentSong.value != null,
      hasQueue: currentQueue.isNotEmpty,
      isAtQueueEnd: isAtNaturalQueueEnd,
      isFlowActive: isFlowModeOn.isTrue,
      isRadioActive: isRadioModeOn,
    );
  }

  bool get canSkipToPrevious {
    final song = currentSong.value;
    if (song == null || currentQueue.isEmpty) return false;
    if (isShuffleModeEnabled.isTrue) return true;
    return currentQueue.first.id != song.id ||
        progressBarStatus.value.current.inSeconds > 5;
  }

  List<MediaItem> get _effectiveQueue {
    try {
      return _audioHandler.queue.value.toList();
    } catch (_) {
      return currentQueue.toList();
    }
  }

  late StreamSubscription<bool> keyboardSubscription;

  @override
  onInit() {
    _init();
    super.onInit();
  }

  @override
  void onReady() {
    if (GetPlatform.isWindows) {
      Get.put(WindowsAudioService());
    }
    _restorePrevSession();
    super.onReady();
  }

  void _init() async {
    //_createAppDocDir();
    _listenForChangesInPlayerState();
    _listenForChangesInPosition();
    _listenForChangesInBufferedPosition();
    _listenForChangesInDuration();
    _listenForPlaylistChange();
    _listenForKeyboardActivity();
    _setInitLyricsMode();
    final appPrefs = Hive.box("AppPrefs");
    final restoredFlowSession = _flowService.session.value;
    if (_flowService.isActive.value && restoredFlowSession?.isActive == true) {
      isFlowModeOn.value = true;
      playinfrom.value = PlaylingFrom(
        type: PlaylingFromType.SELECTION,
        name: restoredFlowSession?.station == null
            ? 'Harmony Flow'
            : 'Flow: ${restoredFlowSession!.station!.title}',
      );
    }
    isLoopModeEnabled.value = appPrefs.get("isLoopModeEnabled") ?? false;
    isShuffleModeEnabled.value = appPrefs.get("isShuffleModeEnabled") ?? false;
    isQueueLoopModeEnabled.value =
        appPrefs.get("queueLoopModeEnabled") ?? false;

    if (GetPlatform.isDesktop) {
      setVolume(appPrefs.get("volume") ?? 100);
    }

    if ((appPrefs.get("playerUi") ?? 0) == 1) {
      initGesturePlayerStateAnimationController();
    }

    // only for android auto
    if (GetPlatform.isAndroid) {
      _listenForCustomEvents();
    }
  }

  void initGesturePlayerStateAnimationController() {
    gesturePlayerStateAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    gesturePlayerStateAnimation = Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(
            parent: gesturePlayerStateAnimationController!,
            curve: Curves.easeIn));
  }

  void _setInitLyricsMode() {
    lyricsMode.value = Hive.box("AppPrefs").get("lyricsMode") ?? 0;
  }

  void panellistener(double x) {
    if (x >= 0 && x <= 0.2) {
      playerPaneOpacity.value = 1 - (x * 5);
      isPlayerpanelTopVisible.value = true;
    } else if (x > 0.2) {
      isPlayerpanelTopVisible.value = false;
    }

    if (x > 0.6) {
      isPanelGTHOpened.value = true;
    } else {
      isPanelGTHOpened.value = false;
    }
  }

  void _listenForKeyboardActivity() {
    var keyboardVisibilityController = KeyboardVisibilityController();
    keyboardSubscription =
        keyboardVisibilityController.onChange.listen((bool visible) {
      visible ? playerPanelController.hide() : playerPanelController.show();
    });
  }

  void _listenForChangesInPlayerState() {
    _audioHandler.playbackState.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;
      if (processingState == AudioProcessingState.loading) {
        buttonState.value = PlayButtonState.loading;
      } else if (processingState == AudioProcessingState.buffering) {
        buttonState.value = PlayButtonState.loading;
      } else if (!isPlaying || processingState == AudioProcessingState.error) {
        buttonState.value = PlayButtonState.paused;
      } else if (processingState != AudioProcessingState.completed) {
        buttonState.value = PlayButtonState.playing;
      } else {
        _audioHandler.seek(Duration.zero);
        _audioHandler.pause();
      }

      final settings = Get.find<SettingsScreenController>();
      // Keep the screen awake whenever playback is active and the setting is enabled.
      final shouldEnable = settings.keepScreenAwake.isTrue && isPlaying;
      _setWakelock(shouldEnable);
    });
  }

  void _setWakelock(bool enable) {
    if (_wakelockActive == enable) return; // no-op if already in desired state

    try {
      if (enable) {
        printINFO("Enabling wakelock");
        WakelockPlus.enable();
        _wakelockActive = true;
      } else {
        printINFO("Disabling wakelock");
        WakelockPlus.disable();
        _wakelockActive = false;
      }
    } catch (e) {
      printERROR(e);
    }
  }

  void _listenForChangesInPosition() {
    AudioService.position.listen((position) {
      final oldState = progressBarStatus.value;
      if (isSleepEndOfSongActive.isTrue) {
        timerDurationLeft.value = oldState.total.inSeconds - position.inSeconds;
        if (timerDurationLeft.value == 1) {
          pause();
          cancelSleepTimer();
        }
      }
      progressBarStatus.update((val) {
        val!.current = position;
        val.buffered = oldState.buffered;
        val.total = oldState.total;
      });
      _maybeRecordValidPlayStart(position);
      _maybeRecordCompleted70(position, oldState.total);
    });
  }

  void _listenForChangesInBufferedPosition() {
    _audioHandler.playbackState.listen((playbackState) {
      final oldState = progressBarStatus.value;
      if (progressBarStatus.value.total.inSeconds != 0 &&
          playbackState.bufferedPosition.inSeconds /
                  progressBarStatus.value.total.inSeconds >=
              0.98) {
        if (_newSongFlag) {
          _audioHandler.customAction(
              "checkWithCacheDb", {'mediaItem': currentSong.value!});
          _newSongFlag = false;
        }
      }
      progressBarStatus.update((val) {
        val!.buffered = playbackState.bufferedPosition;
        val.current = oldState.current;
        val.total = oldState.total;
      });
    });
  }

  void _listenForChangesInDuration() {
    _audioHandler.mediaItem.listen((mediaItem) async {
      final oldState = progressBarStatus.value;
      progressBarStatus.update((val) {
        val!.total = mediaItem?.duration ?? Duration.zero;
        val.current = oldState.current;
        val.buffered = oldState.buffered;
      });
      if (mediaItem != null) {
        printINFO(mediaItem.title);
        _newSongFlag = true;
        isCurrentSongBuffered.value = false;
        currentSong.value = mediaItem;
        _startRecommendationSession(mediaItem);
        currentSongIndex.value = currentQueue
            .indexWhere((element) => element.id == currentSong.value!.id);
        await _checkFav();
        await _addToRP(currentSong.value!);
        if (isRadioModeOn &&
            isFlowModeOn.isFalse &&
            currentQueue.isNotEmpty &&
            (currentSong.value!.id == currentQueue.last.id)) {
          await _addRadioContinuation(radioInitiatorItem!);
        }
        await _refillFlowIfNeeded(mediaItem);
        lyrics.value = {"synced": "", "plainLyrics": ""};
        showLyricsflag.value = false;
        if (isDesktopLyricsDialogOpen) {
          Navigator.pop(Get.context!);
        }

        // reset player visible state when player is in gesture mode
        if (Get.find<SettingsScreenController>().playerUi.value == 1) {
          gesturePlayerVisibleState.value = 2;
        }
      }
    });
  }

  void _listenForPlaylistChange() {
    _audioHandler.queue.listen((queue) {
      currentQueue.value = queue;
      currentQueue.refresh();
    });
  }

  void _startRecommendationSession(MediaItem mediaItem) {
    _recommendationSessionSource = _currentPlaybackAuditSource();
    _recommendationFlowSessionId =
        isFlowModeOn.isTrue ? _flowService.session.value?.id : null;
    _playbackSignalGate.begin(
      mediaItem.id,
      playbackSessionId: mediaItem.extras?['playbackRequestId'],
    );
  }

  String _currentPlaybackAuditSource() {
    if (isFlowModeOn.isTrue) {
      final station = _flowService.session.value?.station;
      return station == null ? 'flow' : 'flow: ${station.title}';
    }
    if (isRadioModeOn) return 'radio';
    final name = playinfrom.value.name.trim();
    if (name.isNotEmpty) return name;
    return playinfrom.value.type.name.toLowerCase();
  }

  void _maybeRecordValidPlayStart(Duration position) {
    final song = currentSong.value;
    if (song == null || _playbackSignalGate.songId != song.id) return;
    final playbackState = _audioHandler.playbackState.value;
    if (!_playbackSignalGate.shouldRecordPlayStart(
      position,
      isPlaying: playbackState.playing &&
          playbackState.processingState != AudioProcessingState.error,
    )) {
      return;
    }
    _playbackAuditLog.record(
      song,
      source: _recommendationSessionSource,
    );
    _feedbackTracker.recordPlayStart(
      song,
      source: _recommendationSessionSource,
      sessionId: _recommendationFlowSessionId,
    );
  }

  void _maybeRecordCompleted70(Duration position, Duration total) {
    final song = currentSong.value;
    if (song == null || _playbackSignalGate.songId != song.id) return;
    if (!_playbackSignalGate.shouldRecordCompletion(position, total)) return;
    _feedbackTracker.recordCompleted70(
      song,
      positionSeconds: position.inSeconds,
      durationSeconds: total.inSeconds,
      source: _recommendationSessionSource,
      sessionId: _recommendationFlowSessionId,
    );
    if (isFlowModeOn.isTrue) {
      _flowService.onFeedback(FlowFeedbackAction.completion, song);
      _refillFlowIfNeeded(song);
    }
  }

  Future<void> _recordPotentialEarlySkip({
    Duration? position,
    Duration? total,
  }) async {
    final song = currentSong.value;
    if (song == null || _playbackSignalGate.songId != song.id) return;
    final skipPosition = position ?? progressBarStatus.value.current;
    final trackDuration = total ?? progressBarStatus.value.total;
    if (!_playbackSignalGate.shouldRecordEarlySkip(
      skipPosition,
      trackDuration,
    )) {
      return;
    }
    await _feedbackTracker.recordSkipEarly(
      song,
      positionSeconds: skipPosition.inSeconds,
      durationSeconds: trackDuration.inSeconds,
      source: _recommendationSessionSource,
      sessionId: _recommendationFlowSessionId,
    );
    if (isFlowModeOn.isTrue) {
      await _flowService.onFeedback(FlowFeedbackAction.earlySkip, song);
      if (!isAtNaturalQueueEnd) {
        unawaited(_rebuildUpcomingFlow(
          removeLike: song,
          omitCurrentSeed: true,
        ));
      }
    }
  }

  Future<void> _restorePrevSession() async {
    final restrorePrevSessionEnabled =
        Hive.box("AppPrefs").get("restrorePlaybackSession") ?? false;
    if (restrorePrevSessionEnabled) {
      final prevSessionData = await Hive.openBox("prevSessionData");
      if (prevSessionData.keys.isNotEmpty) {
        final songList = (prevSessionData.get("queue") as List)
            .map((e) => MediaItemBuilder.fromJson(e))
            .toList();
        final int currentIndex = prevSessionData.get("index");
        final int position = prevSessionData.get("position");
        prevSessionData.close();
        await _audioHandler.addQueueItems(songList);
        _playerPanelCheck(restoreSession: true);
        await _audioHandler.customAction("playByIndex", {
          "index": currentIndex,
          "position": position,
          "restoreSession": true
        });
      }
    }
  }

  void _listenForCustomEvents() {
    _audioHandler.customEvent.listen((event) {
      if (event['eventType'] == 'playFromMediaId') {
        _playViaAndroidAuto(event['songId'], event['libraryId']);
      }
    });
  }

  ///pushSongToPlaylist method clear previous song queue, plays the tapped song and push related
  ///songs into Queue
  Future<void> pushSongToQueue(MediaItem? mediaItem,
      {String? playlistid, bool radio = false, String? playbackSource}) async {
    if (radio) {
      await stopFlow();
    } else if (isFlowModeOn.isTrue) {
      await stopFlow();
    }

    /// update playing from value
    playinfrom.value = PlaylingFrom(
        type: PlaylingFromType.SELECTION,
        name: playbackSource ??
            (radio ? "randomRadio".tr : "randomSelection".tr));

    /// set global radio mode flag
    isRadioModeOn = radio;

    Future.delayed(
      Duration.zero,
      () async {
        final content = await _musicServices.getWatchPlaylist(
            videoId: mediaItem?.id ?? "", radio: radio, playlistId: playlistid);
        radioContinuationParam = content['additionalParamsForNext'];
        await _audioHandler
            .updateQueue(List<MediaItem>.from(content['tracks']));
        if (isShuffleModeEnabled.isTrue) {
          await _audioHandler.customAction("shuffleCmd", {"index": 0});
        }

        // added here to broadcast current mediaitem via Audio Service as list is updated
        // if radio is started on current playing song
        if (radio && (currentSong.value?.id == mediaItem?.id)) {
          _audioHandler
              .customAction("upadateMediaItemInAudioService", {"index": 0});
        }
      },
    ).then((value) async {
      if (playlistid != null) {
        _playerPanelCheck();
        await _audioHandler.customAction("playByIndex", {"index": 0});
      } else {
        if (Hive.box("AppPrefs").get("discoverContentType") == "BOLI") {
          Get.find<HomeScreenController>()
              .changeDiscoverContent("BOLI", songId: mediaItem!.id);
        }
      }
    });

    if (playlistid != null ||
        (radio && (currentSong.value?.id == mediaItem?.id))) {
      return;
    }

    //currentSong.value = mediaItem;
    _playerPanelCheck();
    await _audioHandler
        .customAction("setSourceNPlay", {'mediaItem': mediaItem});

    // disable queue loop mode when radio is started
    if (radio &&
        isQueueLoopModeEnabled.isTrue &&
        isShuffleModeEnabled.isFalse) {
      toggleQueueLoopMode();
    }
  }

  Future<void> playPlayListSong(List<MediaItem> mediaItems, int index,
      {PlaylingFrom? playfrom}) async {
    if (isFlowModeOn.isTrue) {
      await stopFlow();
    }
    isRadioModeOn = false;
    //open player pane,set current song and push first song into playing list,

    /// update playing from value
    playinfrom.value =
        playfrom ?? PlaylingFrom(type: PlaylingFromType.SELECTION);

    //for changing home content based on last interation
    Future.delayed(const Duration(seconds: 3), () {
      if (Hive.box("AppPrefs").get("discoverContentType") == "BOLI") {
        Get.find<HomeScreenController>()
            .changeDiscoverContent("BOLI", songId: mediaItems[index].id);
      }
    });

    _playerPanelCheck();
    await _audioHandler.updateQueue(mediaItems);
    if (isShuffleModeEnabled.value) {
      await _audioHandler.customAction("shuffleCmd", {"index": index});
    }
    await _audioHandler.customAction("playByIndex", {"index": index});
  }

  Future<void> startRadio(MediaItem? mediaItem, {String? playlistid}) async {
    await stopFlow();
    radioInitiatorItem = mediaItem ?? playlistid;
    await pushSongToQueue(mediaItem, playlistid: playlistid, radio: true);
  }

  Future<void> startFlow({
    MediaItem? seed,
    FlowMode mode = FlowMode.auto,
    FlowStation? station,
    bool useCurrentSongAsSeed = true,
  }) async {
    if (!_flowService.isEnabled) {
      isFlowModeOn.value = false;
      isFlowStarting.value = false;
      return;
    }
    if (useCurrentSongAsSeed) seed ??= currentSong.value;
    seed ??= station?.previewSong;
    final previousQueue = _effectiveQueue;
    final previousSong = currentSong.value;
    final previousSongIndex = previousSong == null
        ? -1
        : previousQueue.indexWhere((item) => item.id == previousSong.id);
    final previousPosition = progressBarStatus.value.current;
    final previousWasPlaying = _audioHandler.playbackState.value.playing;
    final previousFlowMode = isFlowModeOn.value;
    final previousFlowSession = _flowService.session.value;
    final previousRadioMode = isRadioModeOn;
    final previousPlayingFrom = PlaylingFrom(
      type: playinfrom.value.type,
      name: playinfrom.value.name,
    );
    final launchGeneration = ++_flowLaunchGeneration;
    final previousLaunch = _flowLaunchCompleter;
    if (previousLaunch != null && !previousLaunch.isCompleted) {
      previousLaunch.complete();
    }
    final launchCompleter = Completer<void>();
    _flowLaunchCompleter = launchCompleter;
    isRadioModeOn = false;
    isFlowModeOn.value = true;
    isFlowStarting.value = true;
    playinfrom.value = PlaylingFrom(
      type: PlaylingFromType.SELECTION,
      name: station == null ? 'Harmony Flow' : 'Flow: ${station.title}',
    );
    _playerPanelCheck();
    var queueMutated = false;
    Future<List<MediaItem>>? planning;

    Future<void> rollbackLaunch() async {
      if (launchGeneration != _flowLaunchGeneration) return;
      try {
        if (previousFlowMode && previousFlowSession?.isActive == true) {
          await _flowService.restoreActiveSession(previousFlowSession!);
        } else {
          await _flowService.stop();
        }
      } catch (_) {}
      if (queueMutated) {
        try {
          await _audioHandler.updateQueue(previousQueue);
          if (previousSongIndex >= 0) {
            await _audioHandler.customAction('playByIndex', {
              'index': previousSongIndex,
              'position': previousPosition.inMilliseconds,
            });
            if (!previousWasPlaying) await _audioHandler.pause();
          }
        } catch (_) {}
      }
      isRadioModeOn = previousRadioMode;
      isFlowModeOn.value = previousFlowMode && _flowService.isActive.value;
      playinfrom.value = previousPlayingFrom;
    }

    try {
      planning = _flowService.start(
        seed: seed,
        mode: mode,
        station: station,
      );

      final seedWasPlaying = seed != null && currentSong.value?.id == seed.id;
      final switchImmediately = seed != null && !seedWasPlaying;
      if (switchImmediately) {
        queueMutated = true;
        await _audioHandler.updateQueue([seed]);
        await _audioHandler.customAction('playByIndex', {'index': 0});
      }

      final flowItems = await planning;
      if (launchGeneration != _flowLaunchGeneration || isFlowModeOn.isFalse) {
        return;
      }
      var nextItems = _uniqueMediaItems(
        flowItems,
        excludingItems: seed == null ? const [] : [seed],
      );
      if (nextItems.isEmpty && seed != null) {
        nextItems = await _fetchAnyFallbackItems(seed);
      }
      if (launchGeneration != _flowLaunchGeneration || isFlowModeOn.isFalse) {
        return;
      }

      final activeSong = currentSong.value;
      final queue = activeSong == null
          ? <MediaItem>[if (seed != null) seed, ...nextItems]
          : FlowQueuePolicy.mergeUpcoming(
              queue: _effectiveQueue,
              currentSong: activeSong,
              planned: nextItems,
              replaceUpcoming: true,
              isEligible: _isFlowFallbackEligible,
            );
      final activeIndex = activeSong == null
          ? -1
          : queue.indexWhere((item) => item.id == activeSong.id);
      final hasUpcoming =
          activeIndex < 0 ? queue.isNotEmpty : activeIndex + 1 < queue.length;
      if (queue.isEmpty || (seed != null && !hasUpcoming)) {
        await rollbackLaunch();
        _showNoNextTrackFound();
        return;
      }

      queueMutated = true;
      await _audioHandler.updateQueue(queue);
      final currentIsStillQueued = currentSong.value != null &&
          queue.any((item) => item.id == currentSong.value!.id);
      if (!currentIsStillQueued) {
        await _audioHandler.customAction('playByIndex', {'index': 0});
      }
    } catch (_) {
      final pendingPlanning = planning;
      if (pendingPlanning != null) {
        unawaited(pendingPlanning.catchError((_) => <MediaItem>[]));
      }
      await rollbackLaunch();
      _showNoNextTrackFound();
    } finally {
      if (launchGeneration == _flowLaunchGeneration) {
        isFlowStarting.value = false;
      }
      if (!launchCompleter.isCompleted) launchCompleter.complete();
      if (identical(_flowLaunchCompleter, launchCompleter)) {
        _flowLaunchCompleter = null;
      }
    }
  }

  Future<void> startFlowStation(FlowStation station) {
    return startFlow(
      seed: station.previewSong,
      station: station,
      mode: FlowMode.values.firstWhere(
        (mode) => mode.name == station.modeName,
        orElse: () => FlowMode.auto,
      ),
      useCurrentSongAsSeed: false,
    );
  }

  Future<void> stopFlow() async {
    _flowLaunchGeneration++;
    final launchCompleter = _flowLaunchCompleter;
    if (launchCompleter != null && !launchCompleter.isCompleted) {
      launchCompleter.complete();
    }
    _flowLaunchCompleter = null;
    isFlowStarting.value = false;
    isFlowModeOn.value = false;
    await _flowService.stop();
  }

  Future<void> tuneFlow(FlowMode mode) async {
    await startFlow(seed: currentSong.value, mode: mode);
  }

  Future<void> applyFlowTuning() async {
    final settings = Get.find<FlowTuner>().current.value;
    await _flowService.updateTuner(settings);
    await startFlow(seed: currentSong.value, mode: settings.mode);
  }

  Future<void> moreLikeThis(MediaItem song) async {
    if (isFlowModeOn.isFalse) {
      await _flowService.onFeedback(FlowFeedbackAction.moreLikeThis, song);
      await startFlow(seed: song);
      return;
    }
    await _flowService.onFeedback(FlowFeedbackAction.moreLikeThis, song);
    unawaited(_rebuildUpcomingFlow(seed: song, replaceUpcoming: true));
  }

  Future<void> playLessLikeThis(MediaItem song) async {
    if (isFlowModeOn.isFalse) {
      await _flowService.onFeedback(
        FlowFeedbackAction.playLessLikeThis,
        song,
      );
      return;
    }
    await _flowService.onFeedback(FlowFeedbackAction.playLessLikeThis, song);
    await _removeUpcomingMatches(song: song, artist: song.artist);
    unawaited(_rebuildUpcomingFlow(
      seed: currentSong.value,
      removeLike: song,
      removeArtist: song.artist,
      omitCurrentSeed: true,
    ));
  }

  Future<void> blockTrackFromFlow(MediaItem song) async {
    await _flowService.onFeedback(FlowFeedbackAction.blockTrack, song);
    await _removeUpcomingMatches(song: song);
    if (currentSong.value?.id == song.id) {
      await next();
    }
    unawaited(_rebuildUpcomingFlow(
      seed: currentSong.value,
      removeLike: song,
    ));
  }

  Future<void> blockArtistFromFlow(MediaItem song) async {
    await _flowService.onFeedback(FlowFeedbackAction.blockArtist, song);
    await _removeUpcomingMatches(artist: song.artist);
    if (currentSong.value?.id == song.id) {
      await next();
    }
    unawaited(_rebuildUpcomingFlow(
      seed: currentSong.value,
      removeArtist: song.artist,
    ));
  }

  Future<void> dislikeCurrentSong() async {
    final song = currentSong.value;
    if (song == null) return;
    await blockTrackFromFlow(song);
  }

  Future<int> _addRadioContinuation(dynamic item) async {
    final isSong = item.runtimeType.toString() == "MediaItem";
    final content = await _musicServices.getWatchPlaylist(
        videoId: isSong ? item.id : "",
        radio: true,
        limit: 24,
        playlistId: isSong ? null : item,
        additionalParamsNext: radioContinuationParam);
    radioContinuationParam = content['additionalParamsForNext'];
    return _appendUniqueQueueItems(
      List<MediaItem>.from(content['tracks'] ?? const []),
      excludingId: isSong ? item.id : null,
    );
  }

  ///enqueueSong   append a song to current queue
  ///if current queue is empty, push the song into Queue and play that song
  Future<void> enqueueSong(MediaItem mediaItem) async {
    if (currentQueue.isEmpty) {
      await playPlayListSong([mediaItem], 0);
      return;
    }
    //check if song is available in queue and if not add it to queue
    if (!currentQueue.contains(mediaItem)) {
      _audioHandler.addQueueItem(mediaItem);
    }
  }

  ///enqueueSongList method add song List to current queue
  Future<void> enqueueSongList(List<MediaItem> mediaItems) async {
    if (currentQueue.isEmpty) {
      await playPlayListSong(mediaItems, 0);
      return;
    }
    final listToEnqueue = <MediaItem>[];
    for (MediaItem item in mediaItems) {
      if (!currentQueue.contains(item)) {
        listToEnqueue.add(item);
      }
    }
    await _audioHandler.addQueueItems(listToEnqueue);
  }

  Future<int> _refillFlowIfNeeded(MediaItem mediaItem) async {
    if (isFlowModeOn.isFalse || _flowRefillInProgress) return 0;
    final launchGeneration = _flowLaunchGeneration;
    final sessionId = _flowService.session.value?.id;
    _flowRefillInProgress = true;
    try {
      final items = await _flowService.refillIfNeeded(
        currentQueue.toList(),
        currentSongIndex.value,
        currentSong: mediaItem,
      );
      if (!_isCurrentFlowWork(launchGeneration, sessionId)) return 0;
      return _appendUniqueQueueItems(items, excludingId: mediaItem.id);
    } finally {
      _flowRefillInProgress = false;
    }
  }

  Future<void> _rebuildUpcomingFlow({
    MediaItem? seed,
    MediaItem? removeLike,
    String? removeArtist,
    bool replaceUpcoming = false,
    bool omitCurrentSeed = false,
  }) {
    final launchGeneration = _flowLaunchGeneration;
    final sessionId = _flowService.session.value?.id;
    final task = _flowRebuildTail.then((_) => _performFlowRebuild(
          launchGeneration: launchGeneration,
          sessionId: sessionId,
          seed: seed,
          removeLike: removeLike,
          removeArtist: removeArtist,
          replaceUpcoming: replaceUpcoming,
          omitCurrentSeed: omitCurrentSeed,
        ));
    _flowRebuildTail = task.catchError((Object error, StackTrace stackTrace) {
      printERROR('Flow rebuild failed: $error');
    });
    return task;
  }

  Future<void> _performFlowRebuild({
    required int launchGeneration,
    required String? sessionId,
    required MediaItem? seed,
    required MediaItem? removeLike,
    required String? removeArtist,
    required bool replaceUpcoming,
    required bool omitCurrentSeed,
  }) async {
    if (!_isCurrentFlowWork(launchGeneration, sessionId)) return;
    if (!await _waitForFlowPlanner(launchGeneration, sessionId)) return;

    final queue = _effectiveQueue;
    final current = currentSong.value;
    if (queue.isEmpty || current == null) return;
    final currentIndex = queue.indexWhere((item) => item.id == current.id);
    if (currentIndex < 0) return;
    final baseQueue = FlowQueuePolicy.mergeUpcoming(
      queue: queue,
      currentSong: current,
      planned: const [],
      removeSong: removeLike,
      removeArtist: removeArtist,
      isEligible: _isFlowFallbackEligible,
    );
    final baseCurrentIndex =
        baseQueue.indexWhere((item) => item.id == current.id);

    _flowRefillInProgress = true;
    try {
      final planned = await _flowService.replan(
        baseQueue,
        baseCurrentIndex,
        currentSong: omitCurrentSeed ? null : seed ?? current,
      );
      if (planned.isEmpty || !_isCurrentFlowWork(launchGeneration, sessionId)) {
        return;
      }

      final liveQueue = _effectiveQueue;
      final liveCurrent = currentSong.value;
      if (liveQueue.isEmpty || liveCurrent == null) return;
      final updatedQueue = FlowQueuePolicy.mergeUpcoming(
        queue: liveQueue,
        currentSong: liveCurrent,
        planned: planned,
        replaceUpcoming: replaceUpcoming,
        removeSong: removeLike,
        removeArtist: removeArtist,
        isEligible: _isFlowFallbackEligible,
      );
      if (!_sameQueue(liveQueue, updatedQueue) &&
          _isCurrentFlowWork(launchGeneration, sessionId)) {
        await _audioHandler.updateQueue(updatedQueue);
      }
    } finally {
      _flowRefillInProgress = false;
    }
  }

  bool _isCurrentFlowWork(int launchGeneration, String? sessionId) {
    return isFlowModeOn.isTrue &&
        launchGeneration == _flowLaunchGeneration &&
        sessionId != null &&
        _flowService.session.value?.id == sessionId;
  }

  Future<bool> _waitForFlowPlanner(
    int launchGeneration,
    String? sessionId,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while ((_flowRefillInProgress || _flowService.isRefilling.isTrue) &&
        DateTime.now().isBefore(deadline)) {
      if (!_isCurrentFlowWork(launchGeneration, sessionId)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return !_flowRefillInProgress &&
        _flowService.isRefilling.isFalse &&
        _isCurrentFlowWork(launchGeneration, sessionId);
  }

  Future<void> _removeUpcomingMatches({
    MediaItem? song,
    String? artist,
  }) async {
    final queue = _effectiveQueue;
    final current = currentSong.value;
    if (queue.isEmpty || current == null) return;
    final updatedQueue = FlowQueuePolicy.mergeUpcoming(
      queue: queue,
      currentSong: current,
      planned: const [],
      removeSong: song,
      removeArtist: artist,
      isEligible: _isFlowFallbackEligible,
    );
    if (_sameQueue(queue, updatedQueue)) return;
    await _audioHandler.updateQueue(updatedQueue);
  }

  Future<int> _appendUniqueQueueItems(
    Iterable<MediaItem> mediaItems, {
    String? excludingId,
  }) async {
    final toAdd = _uniqueMediaItems(
      mediaItems,
      excludingIds: {
        if (excludingId != null) excludingId,
      },
      excludingItems: _effectiveQueue,
    );
    if (toAdd.isEmpty) return 0;
    await _audioHandler.addQueueItems(toAdd);
    return toAdd.length;
  }

  List<MediaItem> _uniqueMediaItems(
    Iterable<MediaItem> mediaItems, {
    Set<String> excludingIds = const {},
    Iterable<MediaItem> excludingItems = const [],
  }) {
    final seenIds = excludingIds.toSet();
    final seenKeys =
        excludingItems.map(RecommendationMediaJson.normalizedSongKey).toSet();
    seenIds.addAll(excludingItems.map((item) => item.id));
    final unique = <MediaItem>[];
    for (final item in mediaItems) {
      if (item.id.trim().isEmpty) continue;
      final key = RecommendationMediaJson.normalizedSongKey(item);
      if (!seenIds.add(item.id) || !seenKeys.add(key)) continue;
      unique.add(item);
    }
    return unique;
  }

  bool _isFlowFallbackEligible(MediaItem item) {
    if (_blacklistService.isBlocked(item) ||
        RecommendationMediaJson.hasNoisyVersionMarker(item)) {
      return false;
    }
    if (!Hive.isBoxOpen('RecommendationCache')) return true;
    final cache = Hive.box('RecommendationCache');
    final dismissedIds =
        Set<String>.from(cache.get('dismissedSongIds') ?? const []);
    if (dismissedIds.contains(item.id)) return false;
    final dismissedKeys =
        Set<String>.from(cache.get('dismissedSongKeys') ?? const []);
    return !dismissedKeys.contains(
      RecommendationMediaJson.normalizedSongKey(item),
    );
  }

  bool _sameQueue(List<MediaItem> first, List<MediaItem> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index].id != second[index].id) return false;
    }
    return true;
  }

  Future<int> _appendFallback(MediaItem seed) async {
    final items = await _fetchAnyFallbackItems(seed);
    return _appendUniqueQueueItems(items, excludingId: seed.id);
  }

  Future<List<MediaItem>> _fetchAnyFallbackItems(MediaItem seed) async {
    final flowWasActive = isFlowModeOn.isTrue;
    final launchGeneration = _flowLaunchGeneration;
    final sessionId = flowWasActive ? _flowService.session.value?.id : null;
    final query = '${seed.artist ?? ''} ${seed.title}'.trim();
    final groups = await Future.wait([
      _candidateProvider.getYouTubeRadioCandidates(seed, limit: 24),
      _candidateProvider.getYouTubeRelatedCandidates(seed, limit: 24),
      _candidateProvider.getSearchCandidates(
        query,
        limit: 24,
        source: 'search_fallback',
        seedId: seed.id,
        sourceScore: .58,
      ),
      _candidateProvider.getLastFmCandidates(seed, limit: 8),
    ]);
    if (flowWasActive && !_isCurrentFlowWork(launchGeneration, sessionId)) {
      return [];
    }

    final candidates = groups.expand((items) => items).toList();
    if (candidates.isEmpty) return [];
    if (flowWasActive) {
      final queue = _effectiveQueue;
      final current = currentSong.value ?? seed;
      final currentIndex = queue.indexWhere((item) => item.id == current.id);
      return _flowService.planFallbackCandidates(
        candidates: candidates,
        currentQueue: queue,
        currentIndex: currentIndex,
        currentSong: current,
      );
    }

    return _uniqueMediaItems(
      candidates.map(
        (candidate) => _withFallbackMetadata(candidate.item, candidate.source),
      ),
      excludingItems: [seed],
    ).where(_isFlowFallbackEligible).take(24).toList();
  }

  MediaItem _withFallbackMetadata(MediaItem item, String source) {
    return item.copyWith(extras: {
      ...?item.extras,
      'flowSource': source,
      'flowReasonCodes': const ['fallback'],
    });
  }

  void _playViaAndroidAuto(String songId, String libraryId) {
    Hive.openBox(libraryId).then((box) {
      List<MediaItem> songList = [];
      final songJson = box.values.toList();
      int songIndex = 0;
      for (int i = 0; i < box.length; i++) {
        final song = MediaItemBuilder.fromJson(songJson[i]);
        if (song.id == songId) {
          songIndex = i;
        }
        songList.add(song);
      }
      playPlayListSong(songList, songIndex);
      if (libraryId != "SongDownloads") {
        box.close();
      }
    });
  }

  void playNext(MediaItem song) {
    if (currentQueue.isEmpty) {
      enqueueSong(song);
      return;
    }
    int index = -1;
    for (int i = 0; i < currentQueue.length; i++) {
      if (song.id == (currentQueue[i]).id) {
        index = i;
        break;
      }
    }
    final currentIndx = currentSongIndex.value;
    if (index == currentIndx) {
      return;
    }
    if (index != -1) {
      if (currentQueue.length == 1 ||
          (currentQueue.length == 2 && index == 1)) {
        return;
      }
      onReorder(index, currentSongIndex.value + 1);
    } else {
      //Will add song just below the current song
      (currentIndx == currentQueue.length - 1)
          ? enqueueSong(song)
          : _audioHandler.customAction("addPlayNextItem", {"mediaItem": song});
    }
  }

  void _playerPanelCheck({bool restoreSession = false}) {
    final isWideScreen = Get.size.width > 800;
    final autoOpenPlayer = Hive.box("AppPrefs").get("autoOpenPlayer") ?? true;
    if ((!isWideScreen && autoOpenPlayer && playerPanelController.isAttached) &&
        !restoreSession) {
      playerPanelController.open();
    }

    if (initFlagForPlayer) {
      final miniPlayerHeight = isWideScreen ? 105.0 : 75.0;
      if (Get.find<SettingsScreenController>().isBottomNavBarEnabled.isFalse ||
          getCurrentRouteName() != '/homeScreen') {
        playerPanelMinHeight.value =
            miniPlayerHeight + Get.mediaQuery.viewPadding.bottom;
      } else {
        playerPanelMinHeight.value = miniPlayerHeight;
      }
      initFlagForPlayer = false;
    }
  }

  void removeFromQueue(MediaItem song) {
    _audioHandler.removeQueueItem(song);
  }

  void clearQueue() {
    _audioHandler.customAction("clearQueue");
  }

  void shuffleQueue() {
    _audioHandler.customAction("shuffleQueue");
  }

  Future<void> toggleShuffleMode() async {
    final shuffleModeEnabled = isShuffleModeEnabled.value;
    shuffleModeEnabled
        ? _audioHandler.setShuffleMode(AudioServiceShuffleMode.none)
        : _audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
    isShuffleModeEnabled.value = !shuffleModeEnabled;
    await Hive.box("AppPrefs").put("isShuffleModeEnabled", !shuffleModeEnabled);
    // restrict queue loop mode when shuffle mode is enabled
    if (isShuffleModeEnabled.isTrue && isQueueLoopModeEnabled.isFalse) {
      isQueueLoopModeEnabled.value = true;
    } else if (isShuffleModeEnabled.isFalse) {
      isQueueLoopModeEnabled.value =
          Hive.box("AppPrefs").get("queueLoopModeEnabled", defaultValue: false);
    }
  }

  void onReorder(int oldIndex, int newIndex) {
    _audioHandler.customAction(
        "reorderQueue", {"oldIndex": oldIndex, "newIndex": newIndex});
  }

  void onReorderStart(int index) {
    isQueueReorderingInProcess.value = true;
  }

  void onReorderEnd(int index) {
    isQueueReorderingInProcess.value = false;
  }

  void play() {
    _audioHandler.play();
  }

  void pause() {
    _audioHandler.pause();
  }

  void playPause() {
    if (initFlagForPlayer) return;
    _audioHandler.playbackState.value.playing ? pause() : play();
    // for gesture player
    if (Get.find<SettingsScreenController>().playerUi.value == 1) {
      gesturePlayerVisibleState.value =
          _audioHandler.playbackState.value.playing ? 0 : 1;
      gesturePlayerStateAnimationController?.reset();
      gesturePlayerStateAnimationController?.forward();
    }
  }

  Future<void> prev() async {
    final position = progressBarStatus.value.current;
    final changesTrack = position.inMilliseconds <= 5000 &&
        currentQueue.length > 1 &&
        (isShuffleModeEnabled.isTrue || currentSongIndex.value > 0);
    if (changesTrack) await _recordPotentialEarlySkip();
    await _audioHandler.skipToPrevious();
  }

  Future<void> next() async {
    final skipPosition = progressBarStatus.value.current;
    final trackDuration = progressBarStatus.value.total;
    final hasNext = await prepareNextQueueItem();
    if (!hasNext) {
      _showNoNextTrackFound();
      return;
    }
    await _recordPotentialEarlySkip(
      position: skipPosition,
      total: trackDuration,
    );
    await _audioHandler.skipToNext();
  }

  Future<bool> prepareNextQueueItem() {
    return _ensureNextQueueItem();
  }

  Future<bool> _ensureNextQueueItem() async {
    final song = currentSong.value;
    if (song == null || currentQueue.isEmpty) return false;
    if (!isAtNaturalQueueEnd) return true;

    if (isFlowModeOn.isTrue) {
      final pendingLaunch = _flowLaunchCompleter;
      if (pendingLaunch != null && !pendingLaunch.isCompleted) {
        try {
          await pendingLaunch.future.timeout(const Duration(milliseconds: 800));
        } on TimeoutException {
          // Related fallback keeps Next responsive while the full plan continues.
        }
        if (!isAtNaturalQueueEnd) return true;
      }
      final added = await _refillFlowIfNeeded(song);
      return added > 0 || await _appendFallback(song) > 0;
    }

    if (isRadioModeOn && radioInitiatorItem != null) {
      final added = await _addRadioContinuation(radioInitiatorItem!);
      return added > 0 || await _appendFallback(song) > 0;
    }

    return false;
  }

  void _showNoNextTrackFound() {
    final context = homeScaffoldkey.currentContext ?? Get.context;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(snackbar(
      context,
      'No next track could be found',
      size: SanckBarSize.MEDIUM,
      duration: const Duration(seconds: 2),
    ));
  }

  void seek(Duration position) {
    _audioHandler.seek(position);
  }

  Future<void> seekByIndex(int index) async {
    if (index < 0 || index >= currentQueue.length) return;
    if (currentQueue[index].id != currentSong.value?.id) {
      await _recordPotentialEarlySkip();
    }
    await _audioHandler.customAction("playByIndex", {"index": index});
  }

  void toggleSkipSilence(bool enable) {
    _audioHandler.customAction("toggleSkipSilence", {"enable": enable});
  }

  void toggleLoudnessNormalization(bool enable) {
    _audioHandler
        .customAction("toggleLoudnessNormalization", {"enable": enable});
  }

  Future<void> toggleLoopMode() async {
    isLoopModeEnabled.isFalse
        ? _audioHandler.setRepeatMode(AudioServiceRepeatMode.one)
        : _audioHandler.setRepeatMode(AudioServiceRepeatMode.none);
    isLoopModeEnabled.value = !isLoopModeEnabled.value;
    await Hive.box("AppPrefs")
        .put("isLoopModeEnabled", isLoopModeEnabled.value);
  }

  Future<void> toggleQueueLoopMode({bool showMessage = true}) async {
    if (isShuffleModeEnabled.isTrue && isQueueLoopModeEnabled.isTrue) {
      if (!showMessage) return;
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "queueLoopNotDisMsg1".tr,
          size: SanckBarSize.BIG, duration: const Duration(seconds: 2)));
      return;
    }

    if (isRadioModeOn && isQueueLoopModeEnabled.isFalse) {
      if (!showMessage) return;
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "queueLoopNotDisMsg2".tr,
          size: SanckBarSize.BIG, duration: const Duration(seconds: 2)));
      return;
    }

    isQueueLoopModeEnabled.value = !isQueueLoopModeEnabled.value;
    await _audioHandler.customAction(
        "toggleQueueLoopMode", {"enable": isQueueLoopModeEnabled.value});
    await Hive.box("AppPrefs")
        .put("queueLoopModeEnabled", isQueueLoopModeEnabled.value);
  }

  Future<void> setVolume(int value) async {
    _audioHandler.customAction("setVolume", {"value": value});
    volume.value = value;
    await Hive.box("AppPrefs").put("volume", value);
  }

  Future<void> mute() async {
    int? vol;
    if (volume.value != 0) {
      vol = 0;
    } else {
      vol = await Hive.box("AppPrefs").get("volume", defaultValue: 10);
      if (vol == 0) {
        vol = 10;
        await Hive.box("AppPrefs").put("volume", vol);
      }
    }
    _audioHandler.customAction("setVolume", {"value": vol!});
    volume.value = vol;
  }

  Future<void> _checkFav() async {
    isCurrentSongFav.value =
        (await Hive.openBox("LIBFAV")).containsKey(currentSong.value!.id);
  }

  Future<void> toggleFavourite() async {
    final currMediaItem = currentSong.value!;
    final adding = isCurrentSongFav.isFalse;
    if (adding) {
      final result = await _libraryAutomation.likeTrack(currMediaItem);
      if (!result.success) {
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!, 'This track is blocked from Flow',
            size: SanckBarSize.MEDIUM));
        return;
      }
    } else {
      await _libraryAutomation.unlikeTrack(currMediaItem);
    }
    try {
      final playlistController = Get.find<PlaylistScreenController>(
          tag: const Key("LIBFAV").hashCode.toString());
      adding
          ? playlistController.addNRemoveItemsinList(currMediaItem,
              action: 'add', index: 0)
          : playlistController.addNRemoveItemsinList(currMediaItem,
              action: 'remove');

      // ignore: empty_catches
    } catch (e) {}
    isCurrentSongFav.value = !isCurrentSongFav.value;
    if (isFlowModeOn.isTrue && isCurrentSongFav.isTrue) {
      await _flowService.onFeedback(FlowFeedbackAction.like, currMediaItem);
    }
  }

  // ignore: prefer_typing_uninitialized_variables
  var recentItem;

  /// This function is used to add a mediaItem/Song to Recently played playlist
  Future<void> _addToRP(MediaItem mediaItem) async {
    if (recentItem != mediaItem) {
      final box = await Hive.openBox("LIBRP");
      String? removedSongId;
      if (box.keys.length >= 30) {
        removedSongId = box.getAt(0)['videoId'];
        box.deleteAt(0);
      }
      final valuesCopy = box.values.toList();
      for (int i = valuesCopy.length - 1; i >= 0; i--) {
        if (valuesCopy[i]['videoId'] == mediaItem.id) {
          box.deleteAt(i);
        }
      }
      box.add(MediaItemBuilder.toJson(mediaItem));
      try {
        final playlistController = Get.find<PlaylistScreenController>(
            tag: const Key("LIBRP").hashCode.toString());
        if (removedSongId != null) {
          playlistController.songList
              .removeWhere((element) => element.id == removedSongId);
        }
        // removes current duplicate item from list
        playlistController.songList
            .removeWhere((element) => element.id == mediaItem.id);
        // adds current item to list
        playlistController.addNRemoveItemsinList(mediaItem,
            action: 'add', index: 0);

        // ignore: empty_catches
      } catch (e) {}
    }
    recentItem = mediaItem;
  }

  Future<void> showLyrics() async {
    showLyricsflag.value = !showLyricsflag.value;
    if ((lyrics["synced"].isEmpty && lyrics['plainLyrics'].isEmpty) &&
        showLyricsflag.value) {
      isLyricsLoading.value = true;
      try {
        final Map<String, dynamic>? lyricsR =
            await SyncedLyricsService.getSyncedLyrics(
                currentSong.value!, progressBarStatus.value.total.inSeconds);
        if (lyricsR != null) {
          lyrics.value = lyricsR;
          isLyricsLoading.value = false;
          return;
        }
        final related = await _musicServices.getWatchPlaylist(
            videoId: currentSong.value!.id, onlyRelated: true);
        final relatedLyricsId = related['lyrics'];
        if (relatedLyricsId != null) {
          final lyrics_ = await _musicServices.getLyrics(relatedLyricsId);
          lyrics.value = {"synced": "", "plainLyrics": lyrics_};
        } else {
          lyrics.value = {"synced": "", "plainLyrics": "NA"};
        }
      } catch (e) {
        lyrics.value = {"synced": "", "plainLyrics": "NA"};
      }
      isLyricsLoading.value = false;
    }
  }

  void changeLyricsMode(int? val) {
    Hive.box("AppPrefs").put("lyricsMode", val);
    lyricsMode.value = val!;
  }

  void sleepEndOfSong() {
    isSleepTimerActive.value = true;
    isSleepEndOfSongActive.value = true;
  }

  void startSleepTimer(int minutes) {
    timerDuration = minutes * 60;
    isSleepTimerActive.value = true;
    if ((sleepTimer != null && !sleepTimer!.isActive) || sleepTimer == null) {
      sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (timer.tick == timerDuration) {
          sleepTimer?.cancel();
          pause();
          isSleepTimerActive.value = false;
          timerDuration = 0;
          timerDurationLeft.value = 0;
        } else {
          timerDurationLeft.value = timerDuration - timer.tick;
        }
      });
    }
  }

  void addFiveMinutes() {
    timerDuration += 300;
  }

  void cancelSleepTimer() {
    if (isSleepEndOfSongActive.isTrue) {
      isSleepEndOfSongActive.value = false;
    }
    sleepTimer?.cancel();
    isSleepTimerActive.value = false;
    timerDuration = 0;
    timerDurationLeft.value = 0;
  }

  Future<void> openEqualizer() async {
    await _audioHandler.customAction("openEqualizer");
  }

  /// Called from audio handler in case audio is not playable
  /// or returned streamInfo null due to network error
  void notifyPlayError(String message) {
    ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
        Get.context!, message == "networkError" ? message.tr : message,
        size: SanckBarSize.MEDIUM));
  }

  @override
  void dispose() {
    _audioHandler.customAction('dispose');
    keyboardSubscription.cancel();
    scrollController.dispose();
    gesturePlayerStateAnimationController?.dispose();
    sleepTimer?.cancel();
    if (GetPlatform.isWindows) {
      Get.delete<WindowsAudioService>();
    }
    // ensure wakelock disabled when player controller disposed
    try {
      _setWakelock(false);
    } catch (e) {
      printERROR(e);
    }
    super.dispose();
  }
}

enum PlayButtonState { paused, playing, loading }
