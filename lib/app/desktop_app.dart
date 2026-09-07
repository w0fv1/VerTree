import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:toastification/toastification.dart';
import 'package:vertree/component/app_launch_args.dart';
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/modules/monitoring/monitoring.dart';
import 'package:vertree/api/local_http_api_server.dart';
import 'package:vertree/api/extended_automation_api.dart';
import 'package:vertree/component/app_logger.dart';
import 'package:vertree/component/configer.dart';
import 'package:vertree/component/launch_counter.dart';
import 'package:vertree/component/notifier.dart';
import 'package:vertree/adapters/ui/versions/file_version_tree.dart';
import 'package:vertree/foundation/result.dart';
import 'package:vertree/component/app_command_handler.dart';
import 'package:vertree/component/app_window_controller.dart';
import 'package:vertree/component/tray_manager.dart';
import 'package:vertree/platform/bootstrap/platform_bootstrap.dart';
import 'package:vertree/platform/platform_integration.dart';
import 'package:vertree/platform/process_exit.dart';
import 'package:vertree/service/lan_file_share_server.dart';
import 'package:vertree/service/local_http_api_service.dart';
import 'package:vertree/service/app_announcement_service.dart';
import 'package:vertree/service/initial_setup_service.dart';
import 'package:vertree/view/module/file_tree.dart';
import 'package:vertree/view/module/lan_share_dialog.dart';
import 'package:vertree/view/module/file_preview_dialog.dart';
import 'package:vertree/view/page/brand_page.dart';
import 'package:vertree/view/page/monit_page.dart';
import 'package:vertree/view/page/setting_page.dart';
import 'package:vertree/view/page/version_tree_page.dart';
import 'package:window_manager/window_manager.dart';

import '../component/app_version_info.dart';
import '../app/composition_root.dart';
import '../adapters/ui/versions/version_actions.dart';
import '../adapters/ui/desktop_scope.dart';
import '../adapters/ui/desktop_theme.dart';
import '../adapters/ui/theme_controller.dart';
import '../app/app_host.dart';
import '../platform/windows_registry_bridge.dart';
import '../foundation/app_events.dart';
import '../modules/preview/preview.dart';
import '../modules/automation/automation.dart';
import '../service/file_preview_image_service.dart';

final logger = AppLogger(LogLevel.debug);
const String configuredLanSharePageBaseUrl = String.fromEnvironment(
  'VERTREE_SHARE_PAGE_BASE_URL',
  defaultValue: LanFileShareServer.defaultSharePageBaseUrl,
);
late void Function(Widget page) go;
late MonitManager monitService;
late LocalHttpApiServer localHttpApiServer;
late LanFileShareServer lanFileShareServer;
Configer configer = Configer();
final appEvents = AppEvents();
final previewActivity = PreviewActivity(appEvents);
final jobs = AutomationJobs(appEvents);
final images = FilePreviewImageService();
final backend = AppBackend(config: configer, events: appEvents);
final versionActions = VersionActions(backend.versions);
late final AppHost appHost;
late final AppCommandHandler appCommandHandler;
late final AppWindowController appWindowController;
late final TrayManager tray;

final AppLocale appLocale = AppLocale(config: configer);
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey appScreenshotBoundaryKey = GlobalKey();
final Completer<void> _appUiReadyCompleter = Completer<void>();
String _currentUiPageId = 'brand';
Map<String, dynamic> _currentUiPageState = const {'page': 'brand'};
FileTreeViewportController? _currentFileTreeViewportController;
bool suppressAnnouncementDialogs = false;

late final AppVersionInfo appVersionInfo;

final appAnnouncementService = AppAnnouncementService(
  announcementUrl: 'https://vertree.w0fv1.dev/announcement.json',
  readConfigSnapshot: () => configer.toJson(),
  writeDismissedAnnouncementUuids: (uuids) async {
    configer.set<List<String>>(
      AppAnnouncementService.dismissedAnnouncementUuidsKey,
      uuids,
    );
    await configer.flush();
  },
  onLogInfo: logger.info,
  onLogError: logger.error,
);

final initialSetupService = InitialSetupService(configer);

late final DesktopThemeController themeController;
bool get defaultLaunchToTray => !Platform.isLinux;

Future<Result<Map<String, dynamic>, String>> setThemeModeForApi(
  String mode,
) async {
  final normalized = mode.trim().toLowerCase();
  if (!{'system', 'light', 'dark'}.contains(normalized)) {
    return Result.eMsg(
      'Unsupported theme mode "$mode". Supported values: system, light, dark.',
    );
  }

  themeController.update(AppThemeSetting.values.byName(normalized));
  await _waitForRenderedFrames(waitMilliseconds: 180);
  return Result.ok(_currentUiState());
}

Future<void> showMainWindow({Widget? page, bool animate = true}) async {
  await appWindowController.showMainWindow(page: page, animate: animate);
}

Future<void> hideMainWindowToTray() async {
  await appWindowController.hideMainWindowToTray();
}

bool _isQuittingApplication = false;

Future<void> quitApplication() async {
  if (_isQuittingApplication) {
    return;
  }
  _isQuittingApplication = true;
  // Keep the engine/message loop alive until bounded service cleanup finishes.
  // windowManager.destroy() posts WM_QUIT on Windows, tearing down the engine
  // before Dart cleanup or a Dart fallback timer can reliably complete.
  await _disposeBackgroundServicesForQuit();
  exitAfterCleanup();
}

Future<void> _disposeBackgroundServicesForQuit() async {
  await appHost.stop();
  await _safeHideTrayForQuit();
}

Future<void> _safeHideTrayForQuit() async {
  try {
    await tray.hideForQuit().timeout(const Duration(milliseconds: 700));
  } catch (_) {}
}

Future<void> toggleMainWindowVisibility({Widget? page}) async {
  await appWindowController.toggleMainWindowVisibility(page: page);
}

bool _isNonActionableSecondArgs(List<String> args) {
  return args.isEmpty || !appCommandHandler.isActionable(args);
}

Future<void> _bringExistingWindowToFront() async {
  await showMainWindow(animate: false);
}

void _handleSecondInstance(List<String> args) {
  logger.info("onSecondWindow $args");
  unawaited(() async {
    await _bringExistingWindowToFront();

    if (_isNonActionableSecondArgs(args)) {
      go(BrandPage());
      return;
    }

    processArgs(args);
  }());
}

Future<void> runVertreeApp(
  PlatformBootstrap bootstrap,
  List<String> args,
) async {
  if (await bootstrap.handlePreBootstrapArgs(args)) {
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  final packageInfo = await PackageInfo.fromPlatform();
  appVersionInfo = AppVersionInfo.fromPackageVersion(
    packageVersion: packageInfo.version,
    releaseApiUrl: "https://api.github.com/repos/w0fv1/vertree/releases",
    readConfigString: (key, defaultValue) =>
        configer.get<String>(key, defaultValue),
    writeConfigString: (key, value) => configer.set<String>(key, value),
    onLogInfo: logger.info,
    onLogError: logger.error,
  );
  await logger.init();
  await configer.init();
  appLocale.initialize();
  themeController = DesktopThemeController(configer);
  WindowsRegistryBridge.configure(
    config: configer,
    locale: appLocale,
    logger: logger,
  );
  await PlatformIntegration.init();
  logger.info('Platform bootstrap: ${bootstrap.name}');
  appCommandHandler = AppCommandHandler(
    onBackup: backup,
    onExpressBackup: expressBackup,
    onMonit: monit,
    onShare: share,
    onViewTree: viewtree,
    onPreview: previewFile,
    onNotify: showWindowsNotification,
    onLogInfo: logger.info,
    onLogError: logger.error,
  );
  tray = TrayManager(
    appLocale: appLocale,
    onLog: logger.info,
    showMainWindow: showMainWindow,
    toggleMainWindowVisibility: toggleMainWindowVisibility,
    quitApplication: quitApplication,
    backup: backup,
    expressBackup: expressBackup,
    monit: monit,
    share: share,
    viewtree: viewtree,
  );
  appWindowController = AppWindowController(
    onShowPage: (page) => go(page),
    onLogError: logger.error,
    onRefreshDockIcon: PlatformIntegration.refreshMacOSDockIcon,
    onRefreshTray: tray.refreshTray,
  );

  monitService = backend.monitors;
  lanFileShareServer = LanFileShareServer(
    events: appEvents,
    sharePageBaseUrl: configuredLanSharePageBaseUrl,
    onLogInfo: logger.info,
    onLogError: logger.error,
  );
  final apiService = LocalHttpApiService(
    configer: configer,
    versions: backend.versions,
    comparator: backend.comparator,
    catalog: backend.catalog,
    monitManager: monitService,
    lanFileShareServer: lanFileShareServer,
    currentVersion: appVersionInfo.currentVersion,
    startedAt: DateTime.now(),
    currentPortResolver: () => localHttpApiServer.port,
    currentUiStateResolver: _currentUiState,
    navigateUiHandler: navigateToPageForApi,
    captureUiScreenshotHandler: captureCurrentAppScreenshot,
    setWindowStateHandler: setWindowStateForApi,
    setThemeModeHandler: setThemeModeForApi,
    setFileTreeViewportHandler: setFileTreeViewportForApi,
    quitAppHandler: quitApplication,
  );
  final automation = ExtendedAutomationApi(
    events: appEvents,
    preview: previewActivity,
    jobs: jobs,
    images: images,
    service: apiService,
    config: configer,
    openPreview: (path) async {
      await _waitForUiReady();
      await showMainWindow(animate: false);
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) throw StateError('UI_NOT_READY');
      unawaited(showFilePreview(context, path));
    },
    closePreview: closeFilePreview,
    diagnostics: () => {
      'platform': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'runtime': apiService.health(),
      'previewEngine': 'Office-Viewer',
      'imageRendering': Platform.isWindows
          ? 'WebView2'
          : Platform.isMacOS
          ? 'WKWebView'
          : Platform.isLinux
          ? 'Chromium (requires installed browser)'
          : 'unavailable',
    },
  );
  localHttpApiServer = LocalHttpApiServer(
    apiService: apiService,
    additionalRoutes: automation.routes,
    accessToken: Platform.environment['VERTREE_LOCAL_API_TOKEN'],
    forceEnabled: Platform.environment['VERTREE_LOCAL_API_ENABLED'] == '1',
  );
  appHost = AppHost(
    [
      HostedResource('events', start: () async {}, stop: appEvents.dispose),
      HostedResource('settings', start: () async {}, stop: configer.dispose),
      HostedResource(
        'theme',
        start: () async {},
        stop: () async => themeController.dispose(),
      ),
      HostedResource(
        'file-writes',
        start: () async {},
        stop: backend.writes.close,
      ),
      HostedResource('jobs', start: () async {}, stop: automation.jobs.dispose),
      HostedResource(
        'monitors',
        start: monitService.startAll,
        stop: monitService.dispose,
      ),
      HostedResource(
        'sharing',
        start: () async {},
        stop: lanFileShareServer.dispose,
      ),
      HostedResource('preview', start: () async {}, stop: closeFilePreview),
      HostedResource(
        'http',
        start: localHttpApiServer.syncWithConfig,
        stop: localHttpApiServer.stop,
      ),
    ],
    onCleanupError: (name, error) =>
        logger.error('Cleanup $name failed: $error'),
  );
  logger.info("启动参数: $args");

  try {
    final bool isStartupLaunch = containsStartupLaunchArg(args);
    suppressAnnouncementDialogs = containsNoAnnouncementLaunchArg(args);
    final bool launch2Tray = configer.get("launch2Tray", defaultLaunchToTray);
    final bool isSetupDone = configer.get<bool>('isSetupDone', false);
    final bool isGnomeWithoutTray =
        PlatformIntegration.isLinuxGnome &&
        !PlatformIntegration.supportsTrayOnlyBackgroundMode;
    final bool canLaunchToTray =
        PlatformIntegration.supportsTrayOnlyBackgroundMode;
    final bool shouldLaunchToTray =
        launch2Tray && isSetupDone && canLaunchToTray && isStartupLaunch;

    await bootstrap.setupPlatformChannels(
      ensureWindowVisible: _ensureWindowVisible,
      openSettings: () => go(SettingPage()),
      processArgs: processArgs,
      pickFileAndRunAction: _pickFileAndRunAction,
    );
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);

    if (bootstrap.supportsDockTrayStartupOptimization && shouldLaunchToTray) {
      try {
        await windowManager.setSkipTaskbar(true);
      } catch (_) {}
    }

    await bootstrap.configureSingleInstance(
      args: args,
      onSecondInstanceArgs: _handleSecondInstance,
    );
    await PlatformIntegration.reAddContextMenu();
    await initLocalNotifier();
    try {
      await appHost.start();
    } catch (e) {
      logger.error('Backend startup failed: $e');
      rethrow;
    }

    windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(600, 600),
        center: true,
        backgroundColor: Colors.transparent,
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.setOpacity(0.92);

        if (shouldLaunchToTray) {
          await showWindowsNotificationWithTask(
            appLocale.getText(LocaleKey.appTrayNotificationTitle),
            appLocale.getText(LocaleKey.appTrayNotificationContent),
            () {
              go(BrandPage());
            },
          );
          await hideMainWindowToTray();
        } else {
          if (launch2Tray && isSetupDone && !canLaunchToTray) {
            logger.info('当前 Linux GNOME 未启用托盘支持，改为显示主窗口');
          }
          await showMainWindow(animate: true);
          if (isGnomeWithoutTray && launch2Tray && isSetupDone) {
            showToast(
              appLocale.getText(LocaleKey.settingLaunchToTraySetupHint),
            );
          }
        }

        if (monitService.runningTaskCount > 0) {
          await showWindowsNotificationWithTask(
            appLocale.getText(LocaleKey.appMonitStartedTitle),
            appLocale.getText(LocaleKey.appMonitStartedContent),
            () => go(MonitPage()),
          );
        }
      },
    );
    String appPath = Platform.resolvedExecutable;
    logger.info("Current app path: $appPath");

    await tray.init();
    runApp(
      DesktopScope(
        data: DesktopDependencies(
          logger: logger,
          configer: configer,
          appLocale: appLocale,
          monitService: monitService,
          catalog: backend.catalog,
          events: appEvents,
          preview: previewActivity,
          versionActions: versionActions,
          appVersionInfo: appVersionInfo,
          localHttpApiServer: localHttpApiServer,
          appAnnouncementService: appAnnouncementService,
          initialSetupService: initialSetupService,
          suppressAnnouncements: () => suppressAnnouncementDialogs,
          go: (page) => go(page),
          quitApplication: quitApplication,
          openLanShareDialogForPath: openLanShareDialogForPath,
          readThemeSetting: () => themeController.setting,
          updateThemeSetting: themeController.update,
          toggleLightDarkTheme: themeController.toggle,
          refreshTray: () => tray.refreshTray(forceRebuild: true),
        ),
        child: const MainPage(),
      ),
    );
    LaunchCounter.trackLaunchIfNeeded(configer: configer, logger: logger);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      processArgs(args);
    });
  } catch (e) {
    logger.error('Vertree启动失败: $e');
    await appHost.stop();
    exit(1);
  }
}

Future<void> _ensureWindowVisible() async {
  await showMainWindow(animate: true);
}

void previewFile(String path) {
  unawaited(() async {
    try {
      await _waitForUiReady();
      await _ensureWindowVisible();
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await showFilePreview(context, path);
    } catch (error) {
      logger.error('打开文件预览失败: $error');
    }
  }());
}

Future<void> _waitForUiReady() async {
  if (_appUiReadyCompleter.isCompleted) {
    return;
  }
  await _appUiReadyCompleter.future.timeout(const Duration(seconds: 10));
}

Future<void> _waitForRenderedFrames({int waitMilliseconds = 0}) async {
  await Future<void>.delayed(Duration.zero);
  await WidgetsBinding.instance.endOfFrame;
  if (waitMilliseconds > 0) {
    await Future<void>.delayed(Duration(milliseconds: waitMilliseconds));
  }
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 32));
}

Map<String, dynamic> _describePage(Widget page) {
  if (page is BrandPage) {
    return {
      'page': 'brand',
      'forceShowInitialSetupDialog': page.forceShowInitialSetupDialog,
    };
  }
  if (page is MonitPage) {
    return const {'page': 'monitor'};
  }
  if (page is SettingPage) {
    return const {'page': 'settings'};
  }
  if (page is FileTreePage) {
    return {
      'page': 'version-tree',
      'path': page.path,
      'fitToViewportOnLoad': page.fitToViewportOnLoad,
      'initialScale': page.initialScale,
      'currentScale': page.viewportController?.currentScale,
    };
  }
  return {'page': page.runtimeType.toString()};
}

void _updateCurrentUiPage(Widget page) {
  final pageInfo = _describePage(page);
  _currentUiPageId = (pageInfo['page'] ?? page.runtimeType.toString())
      .toString();
  _currentUiPageState = Map<String, dynamic>.from(pageInfo);
  _currentFileTreeViewportController = page is FileTreePage
      ? page.viewportController
      : null;
}

Map<String, dynamic> _currentUiState() {
  final configuredThemeMode = themeController.mode.value;
  final effectiveBrightness = themeController.effectiveBrightness;
  return {
    'ready': _appUiReadyCompleter.isCompleted,
    'currentPage': _currentUiPageId,
    'pageState': Map<String, dynamic>.from(_currentUiPageState),
    'screenshotReady': appScreenshotBoundaryKey.currentContext != null,
    'fileTreeViewportReady':
        _currentFileTreeViewportController?.isAttached ?? false,
    'fileTreeScale': _currentFileTreeViewportController?.currentScale,
    'theme': {
      'setting': themeController.setting.name,
      'themeMode': configuredThemeMode.name,
      'effectiveBrightness': effectiveBrightness.name,
      'platformBrightness':
          ui.PlatformDispatcher.instance.platformBrightness.name,
    },
    'startup': {'announcementSuppressed': suppressAnnouncementDialogs},
  };
}

Widget? _buildPageForApi(
  String page, {
  String? path,
  bool showInitialSetupDialog = false,
  double? fileTreeScale,
  bool fitFileTreeToViewport = false,
}) {
  final normalized = page.trim().toLowerCase();
  switch (normalized) {
    case 'brand':
    case 'home':
      return BrandPage(
        forceShowInitialSetupDialog: showInitialSetupDialog,
        initialSetupDialogDelay: showInitialSetupDialog
            ? const Duration(milliseconds: 250)
            : const Duration(seconds: 1),
      );
    case 'monitor':
    case 'monit':
      return MonitPage();
    case 'setting':
    case 'settings':
      return SettingPage();
    case 'version-tree':
    case 'viewtree':
    case 'tree':
      if (path == null || path.trim().isEmpty) {
        return null;
      }
      return FileTreePage(
        key: UniqueKey(),
        path: path.trim(),
        viewportController: FileTreeViewportController(),
        initialScale: fileTreeScale,
        fitToViewportOnLoad: fitFileTreeToViewport,
      );
  }
  return null;
}

Future<Map<String, dynamic>> _readWindowState() async {
  final size = await windowManager.getSize();
  return {
    'isVisible': await windowManager.isVisible(),
    'isFocused': await windowManager.isFocused(),
    'isMaximized': await windowManager.isMaximized(),
    'isFullScreen': await windowManager.isFullScreen(),
    'size': {'width': size.width, 'height': size.height},
  };
}

Future<Result<Map<String, dynamic>, String>> setWindowStateForApi({
  String mode = 'restore',
  double? width,
  double? height,
  bool focus = true,
}) async {
  try {
    final normalizedMode = mode.trim().isEmpty
        ? 'restore'
        : mode.trim().toLowerCase();
    if (!{'restore', 'maximize', 'fullscreen'}.contains(normalizedMode)) {
      return Result.eMsg(
        'Unsupported window mode "$mode". Supported values: restore, maximize, fullscreen.',
      );
    }

    await showMainWindow(animate: false);
    if (normalizedMode != 'fullscreen' && await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    if (normalizedMode == 'restore') {
      if (await windowManager.isMaximized()) {
        await windowManager.restore();
      }
      if (width != null && height != null) {
        await windowManager.setSize(Size(width, height));
        await windowManager.center();
      }
    } else if (normalizedMode == 'maximize') {
      await windowManager.maximize();
    } else if (normalizedMode == 'fullscreen') {
      await windowManager.setFullScreen(true);
    }

    if (focus) {
      await windowManager.focus();
    }
    await _waitForRenderedFrames(waitMilliseconds: 220);

    return Result.ok({
      'mode': normalizedMode,
      'window': await _readWindowState(),
    });
  } catch (e) {
    return Result.eMsg('Failed to update window state: $e');
  }
}

Future<Result<Map<String, dynamic>, String>> setFileTreeViewportForApi({
  double? scale,
  bool fitToViewport = false,
}) async {
  try {
    await _waitForUiReady();
    final controller = _currentFileTreeViewportController;
    if (_currentUiPageId != 'version-tree' || controller == null) {
      return Result.eMsg(
        'File tree viewport controls are only available on the version-tree page.',
      );
    }
    await _waitForRenderedFrames(waitMilliseconds: 220);
    if (!controller.isAttached) {
      return Result.eMsg('File tree viewport is not ready yet.');
    }
    if (fitToViewport) {
      controller.fitScene();
    } else if (scale != null) {
      controller.setScale(scale);
    } else {
      return Result.eMsg('Either scale or fitToViewport must be provided.');
    }
    await _waitForRenderedFrames(waitMilliseconds: 220);

    return Result.ok({
      'page': _currentUiPageId,
      'scale': controller.currentScale,
      'fitToViewport': fitToViewport,
      'pageState': Map<String, dynamic>.from(_currentUiPageState),
    });
  } catch (e) {
    return Result.eMsg('Failed to update file tree viewport: $e');
  }
}

Future<Result<Map<String, dynamic>, String>> navigateToPageForApi({
  required String page,
  String? path,
  int waitMilliseconds = 400,
  bool ensureWindowVisible = true,
  String? windowMode,
  double? windowWidth,
  double? windowHeight,
  bool showInitialSetupDialog = false,
  double? fileTreeScale,
  bool fitFileTreeToViewport = false,
}) async {
  try {
    await _waitForUiReady();
    final targetPage = _buildPageForApi(
      page,
      path: path,
      showInitialSetupDialog: showInitialSetupDialog,
      fileTreeScale: fileTreeScale,
      fitFileTreeToViewport: fitFileTreeToViewport,
    );
    if (targetPage == null) {
      return Result.eMsg(
        'Unsupported page "$page". Supported values: brand, monitor, settings, version-tree (requires path).',
      );
    }

    if (ensureWindowVisible) {
      await showMainWindow(page: targetPage, animate: false);
    } else {
      go(targetPage);
    }

    if (windowMode != null || windowWidth != null || windowHeight != null) {
      final windowResult = await setWindowStateForApi(
        mode: windowMode ?? 'restore',
        width: windowWidth,
        height: windowHeight,
        focus: ensureWindowVisible,
      );
      if (windowResult.isErr) {
        return Result.eMsg(windowResult.msg);
      }
    }

    await _waitForRenderedFrames(waitMilliseconds: waitMilliseconds);

    return Result.ok({
      'requestedPage': page,
      'currentPage': _currentUiPageId,
      'pageState': Map<String, dynamic>.from(_currentUiPageState),
      'waitMilliseconds': waitMilliseconds,
      'window': await _readWindowState(),
      'fileTreeScale': _currentFileTreeViewportController?.currentScale,
    });
  } catch (e) {
    return Result.eMsg('Failed to navigate UI: $e');
  }
}

Future<Result<Map<String, dynamic>, String>> captureCurrentAppScreenshot({
  required String outputPath,
  double pixelRatio = 1.5,
  int waitMilliseconds = 450,
  bool ensureWindowVisible = true,
}) async {
  final normalizedOutputPath = p.normalize(outputPath);
  try {
    await _waitForUiReady();
    if (ensureWindowVisible) {
      await showMainWindow(animate: false);
      await windowManager.focus();
    }
    await _waitForRenderedFrames(waitMilliseconds: waitMilliseconds);

    final renderObject = appScreenshotBoundaryKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      return Result.eMsg('Screenshot boundary render object is unavailable.');
    }

    final image = await renderObject.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return Result.eMsg('Failed to encode the screenshot as PNG.');
      }

      final bytes = byteData.buffer.asUint8List();
      final file = File(normalizedOutputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);

      return Result.ok({
        'outputPath': file.path,
        'pixelRatio': pixelRatio,
        'waitMilliseconds': waitMilliseconds,
        'page': _currentUiPageId,
        'pageState': Map<String, dynamic>.from(_currentUiPageState),
        'image': {
          'width': image.width,
          'height': image.height,
          'byteLength': bytes.length,
        },
      });
    } finally {
      image.dispose();
    }
  } catch (e) {
    return Result.eMsg('Failed to capture app screenshot: $e');
  }
}

Future<void> _pickFileAndRunAction(String action) async {
  await _ensureWindowVisible();
  final result = await FilePicker.platform.pickFiles();
  final path = result?.files.single.path;
  if (path == null || path.isEmpty) return;
  processArgs(['--menu', action, path]);
}

void processArgs(List<String> args) {
  appCommandHandler.process(args);
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WindowListener {
  Widget page = BrandPage();

  @override
  void initState() {
    super.initState();
    go = goPage;
    _updateCurrentUiPage(page);
    if (!_appUiReadyCompleter.isCompleted) {
      _appUiReadyCompleter.complete();
    }
    windowManager.addListener(this);
  }

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeController.mode,
        builder: (context, themeMode, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: appLocale.getText(LocaleKey.appTitle),
            themeMode: themeMode,
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            builder: (context, child) {
              return RepaintBoundary(
                key: appScreenshotBoundaryKey,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: page,
          );
        },
      ),
    );
  }

  void goPage(Widget page) async {
    logger.info("goPage");

    if (!mounted) return;

    setState(() {
      this.page = page;
      _updateCurrentUiPage(page);
    });
  }

  @override
  void onWindowClose() async {
    await quitApplication();
  }

  @override
  void onWindowMinimize() {
    unawaited(tray.refreshTray());
  }

  @override
  void onWindowRestore() {
    unawaited(tray.refreshTray());
  }

  @override
  void onWindowFocus() {
    unawaited(tray.refreshTray());
  }

  @override
  void onWindowBlur() {
    unawaited(tray.refreshTray());
  }
}

Future<void> expressBackup(String path) async {
  logger.info(path);
  FileNode fileNode = FileNode(path);

  final result = await versionActions.create(fileNode.mate.fullPath);
  if (result.isErr) {
    showWindowsNotification(
      appLocale.getText(LocaleKey.appBackupFailed),
      result.msg,
    );
    return;
  }
  FileNode backup = result.unwrap();
  showWindowsNotificationWithFile(
    appLocale.getText(LocaleKey.appBackupSuccessTitle),
    appLocale.getText(LocaleKey.appBackupSuccessContent),
    backup.mate.fullPath,
  );
}

Future<void> backup(String path) async {
  logger.info(path);
  FileNode fileNode = FileNode(path);

  await _waitForUiReady();
  await showMainWindow(animate: false);
  String? label;

  try {
    final overlayContext = navigatorKey.currentState?.overlay?.context;
    if (overlayContext == null || !overlayContext.mounted) return;
    label = await showDialog<String>(
      context: overlayContext,
      builder: (context) {
        String input = "";
        return AlertDialog(
          title: Text(
            appLocale.getText(LocaleKey.appEnterLabelTitle).tr([
              fileNode.mate.name,
            ]),
          ),
          content: TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: appLocale.getText(LocaleKey.appEnterLabelHint),
            ),
            onChanged: (value) {
              input = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop('\$CANCEL_BACKUP');
              },
              child: Text(
                appLocale.getText(LocaleKey.appCancelBackup),
                style: TextStyle(color: Colors.red),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(input);
              },
              child: Text(appLocale.getText(LocaleKey.appConfirm)),
            ),
          ],
        );
      },
    );
    if (label == null || label == '\$CANCEL_BACKUP') {
      showWindowsNotification(
        appLocale.getText(LocaleKey.appCancelNotificationTitle),
        appLocale.getText(LocaleKey.appCancelNotificationContent),
      );
      logger.info("用户取消了文件 ${fileNode.mate.fullPath} 的备份");
      return;
    }
  } catch (e) {
    logger.error("创建询问label失败：$e");
    showToast(appLocale.getText(LocaleKey.appLabelDialogError) + e.toString());
    return;
  }

  final result = await versionActions.create(
    fileNode.mate.fullPath,
    label: label,
  );
  if (result.isErr) {
    showWindowsNotification(
      appLocale.getText(LocaleKey.appBackupFailed),
      result.msg,
    );
    return;
  }
  FileNode backup = result.unwrap();
  showWindowsNotificationWithFile(
    appLocale.getText(LocaleKey.appBackupSuccessTitle),
    appLocale.getText(LocaleKey.appBackupSuccessContent),
    backup.mate.fullPath,
  );

  final monitorDialogContext = navigatorKey.currentState?.overlay?.context;
  if (monitorDialogContext == null || !monitorDialogContext.mounted) {
    viewtree(backup.mate.fullPath);
    return;
  }

  bool? enableMonit = await showDialog<bool>(
    context: monitorDialogContext,
    builder: (context) {
      return AlertDialog(
        title: Text(appLocale.getText(LocaleKey.appEnableMonitTitle)),
        content: Text(appLocale.getText(LocaleKey.appEnableMonitContent)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appLocale.getText(LocaleKey.appNo)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(appLocale.getText(LocaleKey.appYes)),
          ),
        ],
      );
    },
  );
  if (enableMonit == true) {
    await monit(backup.mate.fullPath);
  }

  viewtree(backup.mate.fullPath);
}

Future<void> monit(String path) async {
  logger.info(path);
  final fileMonitTaskResult = await monitService.addFileMonitTask(path);
  if (fileMonitTaskResult.isErr) {
    showWindowsNotification(
      appLocale.getText(LocaleKey.appMonitFailedTitle),
      fileMonitTaskResult.msg,
    );
    return;
  }
  FileMonitTask fileMonitTask = fileMonitTaskResult.unwrap();
  if (fileMonitTask.backupDirPath != null) {
    showWindowsNotificationWithFolder(
      appLocale.getText(LocaleKey.appMonitSuccessTitle),
      appLocale.getText(LocaleKey.appMonitSuccessContent),
      fileMonitTask.backupDirPath!,
    );
  }
}

Future<void> share(String path) => openLanShareDialogForPath(path);

Future<void> openLanShareDialogForPath(String path) async {
  logger.info('share $path');
  await showMainWindow(animate: false);
  final result = await withProgressToast(
    appLocale.getText(LocaleKey.fileleafSharePreparing),
    () async {
      try {
        return await lanFileShareServer.createShare(path);
      } catch (error) {
        logger.error('Failed to prepare LAN share: $error');
        return Result<Map<String, dynamic>, String>.eMsg(error.toString());
      }
    },
  );
  if (result.isErr) {
    final message = appLocale.getText(LocaleKey.fileleafShareCreateFailed).tr([
      result.msg,
    ]);
    showToast(message);
    unawaited(
      showWindowsNotification(
        appLocale.getText(LocaleKey.fileleafMenuShare),
        message,
      ),
    );
    return;
  }

  final shareData = result.unwrap();
  await _showShareReadyAttention(path, shareData);
  final shouldRestoreAfterDialog = await _prepareWindowForShareDialog();
  try {
    await _waitForRenderedFrames(
      waitMilliseconds: shouldRestoreAfterDialog ? 220 : 80,
    );
    final dialogContext =
        navigatorKey.currentContext ?? navigatorKey.currentState?.context;
    if (dialogContext == null || !dialogContext.mounted) {
      final message = (shareData['sharePageUrl'] as String?) ?? path;
      showToast(message);
      return;
    }

    await showDialog<void>(
      context: dialogContext,
      useRootNavigator: true,
      builder: (context) => LanShareDialog(shareData: shareData),
    );
  } finally {
    if (shouldRestoreAfterDialog) {
      await _restoreWindowAfterShareDialog();
    }
  }
}

Future<void> _showShareReadyAttention(
  String path,
  Map<String, dynamic> shareData,
) async {
  final fileName = (shareData['fileName'] as String?) ?? p.basename(path);
  final message = appLocale.getText(LocaleKey.fileleafShareReady).tr([
    fileName,
  ]);

  await _bringWindowToFrontForShareReady();
  showToast(message);
  unawaited(
    showWindowsNotificationWithTask(
      appLocale.getText(LocaleKey.fileleafMenuShare),
      message,
      _bringWindowToFrontForShareReady,
    ),
  );
}

Future<void> _bringWindowToFrontForShareReady() async {
  await showMainWindow(animate: false);
  try {
    await windowManager.focus();
  } catch (_) {}
  if (!PlatformIntegration.isWindows) {
    return;
  }
  try {
    await windowManager.setAlwaysOnTop(true);
    unawaited(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        await windowManager.setAlwaysOnTop(false);
      } catch (_) {}
    }());
  } catch (_) {}
}

Future<bool> _prepareWindowForShareDialog() async {
  try {
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
    if (await windowManager.isFullScreen()) {
      return false;
    }
    if (await windowManager.isMaximized()) {
      return false;
    }
    await windowManager.maximize();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _restoreWindowAfterShareDialog() async {
  try {
    if (await windowManager.isFullScreen()) {
      return;
    }
    if (await windowManager.isMaximized()) {
      await windowManager.restore();
    }
  } catch (_) {}
}

void viewtree(String path) {
  logger.info(path);
  go(FileTreePage(key: UniqueKey(), path: path));
}
