import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:harmonymusic/models/flow/flow_models.dart';
import 'package:harmonymusic/models/flow/flow_station.dart';
import 'package:harmonymusic/services/flow/flow_service.dart';
import 'package:harmonymusic/services/library/blacklist_service.dart';
import 'package:harmonymusic/services/library/library_automation_service.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/playback_audit_log_service.dart';
import 'package:harmonymusic/services/recommendation/candidate_provider.dart';
import 'package:harmonymusic/services/recommendation/feedback_tracker.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';

void main() {
  late Directory directory;
  late _FlowService flow;
  late _AudioHandler audio;
  late PlayerController controller;
  const current = MediaItem(id: 'current', title: 'Old Song', artist: 'Alpha');
  const next = MediaItem(id: 'next', title: 'Station Song', artist: 'Beta');

  setUp(() async {
    Get.testMode = true;
    directory = await Directory.systemTemp.createTemp('flow_station_playback');
    Hive.init(directory.path);
    await Hive.openBox('AppPrefs');
    await Hive.openBox('TrackBlacklist');
    await Hive.openBox('ArtistBlacklist');
    flow = _FlowService();
    audio = _AudioHandler();
    Get.put<AudioHandler>(audio);
    Get.put<MusicServices>(_MusicServices());
    Get.put<PlaybackAuditLogService>(PlaybackAuditLogService());
    Get.put<CandidateProvider>(_CandidateProvider());
    Get.put<FeedbackTracker>(FeedbackTracker());
    Get.put<FlowService>(flow);
    Get.put<BlacklistService>(BlacklistService());
    Get.put<LibraryAutomationService>(_LibraryAutomation());
    controller = PlayerController()..initFlagForPlayer = false;
    controller.currentSong.value = current;
    audio.queue.add([current]);
    audio.onPlay = (song) => controller.currentSong.value = song;
  });

  tearDown(() async {
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: SizedBox()));
  }

  testWidgets('station without artwork replaces the playing track',
      (tester) async {
    await mount(tester);
    flow.result = [current, next];

    await controller.startFlowStation(station('gaming'));

    expect(audio.played, ['next']);
    expect(audio.queue.value.map((item) => item.id), ['next']);
    expect(controller.currentSong.value?.id, 'next');
    expect(flow.seed, isNull);
    expect(flow.selectedStation?.id, 'gaming');
    expect(controller.isFlowStarting.value, isFalse);
  });

  testWidgets('station whose preview is playing starts another station track',
      (tester) async {
    await mount(tester);
    flow.result = [next];

    await controller.startFlowStation(station('cinematic', preview: current));

    expect(audio.played, ['next']);
    expect(audio.queue.value.first.id, 'next');
  });

  testWidgets('a different preview starts immediately before planning finishes',
      (tester) async {
    await mount(tester);
    final pending = Completer<List<MediaItem>>();
    flow.pending = pending.future;
    final launch = controller.startFlowStation(station('night', preview: next));
    await tester.pump();

    expect(audio.played, ['next']);
    pending.complete([const MediaItem(id: 'tail', title: 'Tail')]);
    await launch;

    expect(audio.played, ['next']);
    expect(audio.queue.value.map((item) => item.id), ['next', 'tail']);
  });

  testWidgets('Start Harmony Flow leaves a station and starts another track',
      (tester) async {
    await mount(tester);
    controller.isFlowModeOn.value = true;
    flow.selectedStation = station('cinematic');
    flow.result = [next];

    await controller.startPersonalFlow();

    expect(audio.played, ['next']);
    expect(audio.queue.value.map((item) => item.id), ['next']);
    expect(flow.selectedStation, isNull);
    expect(flow.seed, isNull);
    expect(flow.usePersonalSettings, isTrue);
    expect(controller.playinfrom.value.name, 'Harmony Flow');
  });

  testWidgets('repeated Start Harmony Flow starts a fresh track each time',
      (tester) async {
    await mount(tester);
    flow.result = [next];
    await controller.startPersonalFlow();
    flow.result = [const MediaItem(id: 'fresh', title: 'Fresh')];

    await controller.startPersonalFlow();

    expect(audio.played, ['next', 'fresh']);
    expect(audio.queue.value.map((item) => item.id), ['fresh']);
  });

  testWidgets('a delayed station cannot replace a newer station',
      (tester) async {
    await mount(tester);
    final pending = Completer<List<MediaItem>>();
    flow.pending = pending.future;
    final first = controller.startFlowStation(station('first'));
    flow.pending = null;
    flow.result = [next];
    await controller.startFlowStation(station('second'));
    pending.complete([const MediaItem(id: 'stale', title: 'Stale')]);
    await first;

    expect(audio.played, ['next']);
    expect(audio.queue.value.map((item) => item.id), ['next']);
    expect(controller.playinfrom.value.name, 'Flow: second');
  });

  testWidgets('tuning can preserve the current track', (tester) async {
    await mount(tester);
    flow.result = [next];

    await controller.tuneFlow(FlowMode.chill);

    expect(audio.played, isEmpty);
    expect(audio.queue.value.map((item) => item.id), ['current', 'next']);
  });
}

FlowStation station(String id, {MediaItem? preview}) => FlowStation(
      id: id,
      title: id,
      subtitle: '',
      tags: [id],
      seedTerms: [id],
      searchQueries: ['$id music'],
      modeName: 'auto',
      familiarity: .5,
      variety: .5,
      deepCuts: .5,
      localWeight: .5,
      externalWeight: .5,
      confidence: 1,
      reason: '',
      previewSong: preview,
    );

class _AudioHandler extends BaseAudioHandler {
  final played = <String>[];
  void Function(MediaItem)? onPlay;

  @override
  Future<void> updateQueue(List<MediaItem> items) async => queue.add(items);

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    if (name == 'playByIndex') {
      final song = queue.value[extras!['index'] as int];
      played.add(song.id);
      mediaItem.add(song);
      onPlay?.call(song);
    }
  }
}

class _FlowService extends GetxService implements FlowService {
  List<MediaItem> result = [];
  Future<List<MediaItem>>? pending;
  MediaItem? seed;
  FlowStation? selectedStation;
  bool usePersonalSettings = false;
  @override
  bool get isEnabled => true;
  @override
  final session = Rxn<FlowSession>();
  @override
  final isActive = false.obs;

  @override
  Future<List<MediaItem>> start({
    MediaItem? seed,
    FlowMode mode = FlowMode.auto,
    FlowStation? station,
    bool usePersonalSettings = false,
  }) {
    this.seed = seed;
    selectedStation = station;
    this.usePersonalSettings = usePersonalSettings;
    isActive.value = true;
    return pending ?? Future.value(result);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MusicServices extends GetxService implements MusicServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CandidateProvider extends GetxService implements CandidateProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LibraryAutomation extends GetxService
    implements LibraryAutomationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
