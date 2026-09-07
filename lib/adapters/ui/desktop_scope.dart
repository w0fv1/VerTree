import 'package:flutter/material.dart';
import '../../api/local_http_api_server.dart';
import '../../component/app_logger.dart';
import '../../component/app_version_info.dart';
import '../../component/configer.dart';
import '../../component/i18n_lang.dart';
import '../../modules/monitoring/monitoring.dart';
import '../../modules/versions/versions.dart';
import '../../foundation/app_events.dart';
import '../../modules/preview/preview.dart';
import '../../service/app_announcement_service.dart';
import '../../service/initial_setup_service.dart';
import 'versions/version_actions.dart';

enum AppThemeSetting { system, light, dark }

/// Explicit, typed dependencies of the desktop presentation layer. Business
/// modules never read this scope and cannot resolve services from it.
class DesktopDependencies {
  const DesktopDependencies({
    required this.logger,
    required this.configer,
    required this.appLocale,
    required this.monitService,
    required this.catalog,
    required this.events,
    required this.preview,
    required this.versionActions,
    required this.appVersionInfo,
    required this.localHttpApiServer,
    required this.appAnnouncementService,
    required this.initialSetupService,
    required this.suppressAnnouncements,
    required this.go,
    required this.quitApplication,
    required this.openLanShareDialogForPath,
    required this.readThemeSetting,
    required this.updateThemeSetting,
    required this.toggleLightDarkTheme,
    required this.refreshTray,
  });
  final AppLogger logger;
  final Configer configer;
  final AppLocale appLocale;
  final MonitManager monitService;
  final VersionCatalog catalog;
  final AppEvents events;
  final PreviewActivity preview;
  final VersionActions versionActions;
  final AppVersionInfo appVersionInfo;
  final LocalHttpApiServer localHttpApiServer;
  final AppAnnouncementService appAnnouncementService;
  final InitialSetupService initialSetupService;
  final bool Function() suppressAnnouncements;
  final void Function(Widget) go;
  final Future<void> Function() quitApplication;
  final Future<void> Function(String) openLanShareDialogForPath;
  final AppThemeSetting Function() readThemeSetting;
  final void Function(AppThemeSetting) updateThemeSetting;
  final void Function() toggleLightDarkTheme;
  final Future<void> Function() refreshTray;
  bool get suppressAnnouncementDialogs => suppressAnnouncements();
  AppThemeSetting get currentThemeSetting => readThemeSetting();
}

class DesktopScope extends InheritedWidget {
  const DesktopScope({super.key, required this.data, required super.child});
  final DesktopDependencies data;
  static DesktopDependencies read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DesktopScope>()!.data;
  @override
  bool updateShouldNotify(DesktopScope oldWidget) => data != oldWidget.data;
}
