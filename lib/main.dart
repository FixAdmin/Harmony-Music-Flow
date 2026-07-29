import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:terminate_restart/terminate_restart.dart';

import '/ui/screens/Search/search_screen_controller.dart';
import '/utils/get_localization.dart';
import '/services/downloader.dart';
import '/services/flow/flow_candidate_mixer.dart';
import '/services/flow/flow_debug_logger.dart';
import '/services/flow/flow_feedback_policy.dart';
import '/services/flow/flow_queue_planner.dart';
import '/services/flow/flow_service.dart';
import '/services/flow/flow_station_service.dart';
import '/services/flow/flow_tuner.dart';
import '/services/library/blacklist_service.dart';
import '/services/library/library_automation_service.dart';
import '/services/piped_service.dart';
import '/services/recommendation/candidate_provider.dart';
import '/services/recommendation/feedback_tracker.dart';
import '/services/recommendation/lastfm_provider.dart';
import '/services/recommendation/recommendation_service.dart';
import '/services/recommendation/taste_profile_service.dart';
import 'utils/app_link_controller.dart';
import '/services/audio_handler.dart';
import '/services/music_service.dart';
import '/services/playback_audit_log_service.dart';
import '/ui/home.dart';
import '/ui/player/player_controller.dart';
import 'ui/screens/Settings/settings_screen_controller.dart';
import '/ui/utils/theme_controller.dart';
import 'ui/screens/Home/home_screen_controller.dart';
import 'ui/screens/Library/library_controller.dart';
import 'utils/system_tray.dart';
import 'utils/update_check_flag_file.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHive();
  _setAppInitPrefs();
  startApplicationServices();
  Get.put<AudioHandler>(await initAudioService(), permanent: true);
  WidgetsBinding.instance.addObserver(LifecycleHandler());
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  TerminateRestart.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    if (!GetPlatform.isDesktop) Get.put(AppLinksController());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    return GetMaterialApp(
        title: 'Harmony Music',
        home: const Home(),
        debugShowCheckedModeBanner: false,
        translations: Languages(),
        locale:
            Locale(Hive.box("AppPrefs").get('currentAppLanguageCode') ?? "en"),
        fallbackLocale: const Locale("en"),
        builder: (context, child) {
          final mQuery = MediaQuery.of(context);
          final scale =
              mQuery.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.1);
          return Stack(
            children: [
              GetX<ThemeController>(
                builder: (controller) => MediaQuery(
                  data: mQuery.copyWith(textScaler: scale),
                  child: AnimatedTheme(
                      duration: const Duration(milliseconds: 700),
                      data: controller.themedata.value!,
                      child: child!),
                ),
              ),
              GestureDetector(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    color: Colors.transparent,
                    height: mQuery.padding.bottom,
                    width: mQuery.size.width,
                  ),
                ),
              )
            ],
          );
        });
  }
}

Future<void> startApplicationServices() async {
  Get.lazyPut(() => PipedServices(), fenix: true);
  Get.lazyPut(() => MusicServices(), fenix: true);
  Get.lazyPut(() => PlaybackAuditLogService(), fenix: true);
  Get.lazyPut(() => FeedbackTracker(), fenix: true);
  Get.lazyPut(() => TasteProfileService(), fenix: true);
  Get.lazyPut(() => LastFmProvider(), fenix: true);
  Get.lazyPut(() => CandidateProvider(), fenix: true);
  Get.lazyPut(() => RecommendationService(), fenix: true);
  Get.lazyPut(() => FlowTuner(), fenix: true);
  Get.lazyPut(() => FlowCandidateMixer(), fenix: true);
  Get.lazyPut(() => FlowQueuePlanner(), fenix: true);
  Get.lazyPut(() => FlowFeedbackPolicy(), fenix: true);
  Get.lazyPut(() => FlowDebugLogger(), fenix: true);
  Get.lazyPut(() => FlowStationService(), fenix: true);
  Get.lazyPut(() => BlacklistService(), fenix: true);
  Get.lazyPut(() => LibraryAutomationService(), fenix: true);
  Get.lazyPut(() => FlowService(), fenix: true);
  Get.lazyPut(() => ThemeController(), fenix: true);
  Get.lazyPut(() => PlayerController(), fenix: true);
  Get.lazyPut(() => HomeScreenController(), fenix: true);
  Get.lazyPut(() => LibrarySongsController(), fenix: true);
  Get.lazyPut(() => LibraryPlaylistsController(), fenix: true);
  Get.lazyPut(() => LibraryAlbumsController(), fenix: true);
  Get.lazyPut(() => LibraryArtistsController(), fenix: true);
  Get.lazyPut(() => SettingsScreenController(), fenix: true);
  Get.lazyPut(() => Downloader(), fenix: true);
  if (GetPlatform.isDesktop) {
    Get.lazyPut(() => SearchScreenController(), fenix: true);
    Get.put(DesktopSystemTray());
  }
}

initHive() async {
  String applicationDataDirectoryPath;
  if (GetPlatform.isDesktop) {
    applicationDataDirectoryPath =
        "${(await getApplicationSupportDirectory()).path}/db";
  } else {
    applicationDataDirectoryPath =
        (await getApplicationDocumentsDirectory()).path;
  }
  await Hive.initFlutter(applicationDataDirectoryPath);
  await Hive.openBox("SongsCache");
  await Hive.openBox("SongDownloads");
  await Hive.openBox('SongsUrlCache');
  await Hive.openBox("AppPrefs");
  await Hive.openBox("ListeningEvents");
  await Hive.openBox("PlaybackAuditLog");
  await Hive.openBox("TasteProfile");
  await Hive.openBox("RecommendationCache");
  await Hive.openBox("RecommendationSettings");
  await Hive.openBox("FlowSessions");
  await Hive.openBox("FlowQueueState");
  await Hive.openBox("FlowTunerPresets");
  await Hive.openBox("FlowStats");
  await Hive.openBox("FlowDebugLog");
  await Hive.openBox("TrackBlacklist");
  await Hive.openBox("ArtistBlacklist");
  await Hive.openBox("LibraryAutomationSettings");
  await Hive.openBox("SyncDevices");
  await Hive.openBox("SyncManifest");
  await Hive.openBox("SyncChangeLog");
}

void _setAppInitPrefs() {
  final appPrefs = Hive.box("AppPrefs");
  if (appPrefs.isEmpty) {
    appPrefs.putAll({
      'themeModeType': 0,
      "cacheSongs": false,
      "skipSilenceEnabled": false,
      'streamingQuality': 1,
      'themePrimaryColor': 4278199603,
      'discoverContentType': "QP",
      'newVersionVisibility': updateCheckFlag,
      "cacheHomeScreenData": true,
      "recommendationsEnabled": true,
      "lastFmApiKey": "",
      "flowEnabled": true,
      "showFlowDebugEnabled": false
    });
  }
}

class LifecycleHandler extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else if (state == AppLifecycleState.detached) {
      await Get.find<AudioHandler>().customAction("saveSession");
    }
  }
}
