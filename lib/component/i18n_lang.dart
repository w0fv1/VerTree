import 'dart:async';
import 'dart:io';

import 'package:vertree/platform/platform_integration.dart';

import '../main.dart';

extension StringTranslate on String {
  String tr([List<String>? args]) {
    String result = this;

    if (args == null) {
      return result;
    }
    for (final arg in args) {
      result = result.replaceFirst('%a', arg);
    }
    return result;
  }
}

enum Lang {
  zhCn("简体中文"),
  en("English"),
  ja("日本語"),
  other("");

  final String label;

  const Lang(this.label);

  static Lang fromString(String value) {
    for (var l in Lang.values) {
      if (l.name == value) return l;
    }
    return Lang.other;
  }
}

enum LocaleKey {
  registryPreviewKeyName,
  settingAddPreviewMenu,
  settingMenuUpdateFailed,
  registryBackupKeyName,
  registryExpressBackupKeyName,
  registryMonitorKeyName,
  registryShareKeyName,
  registryViewTreeKeyName,

  appTitle,
  appConfirmExitTitle,
  appConfirmExitContent,
  appMinimize,
  appExit,
  appTrayNotificationTitle,
  appTrayNotificationContent,
  appMonitStartedTitle,
  appMonitStartedContent,
  appBackupFailed,
  appBackupSuccessTitle,
  appBackupSuccessContent,
  appEnterLabelTitle,
  appEnterLabelHint,
  appCancelBackup,
  appConfirm,
  appCancelNotificationTitle,
  appCancelNotificationContent,
  appLabelDialogError,
  appEnableMonitTitle,
  appEnableMonitContent,
  appYes,
  appNo,
  appMonitFailedTitle,
  appMonitSuccessTitle,
  appMonitSuccessContent,
  appAdminPermissionTooFrequent,

  brandTitle,
  brandSlogan,
  brandMonitorPage,
  brandSettingPage,
  brandExit,
  brandInitTitle,
  brandInitContent,
  brandCancel,
  brandConfirm,
  brandInitDoneTitle,
  brandInitDoneBody,
  brandExpressMenuPromptTitle,
  brandExpressMenuPromptContent,
  brandExpressMenuPromptLater,
  brandExpressMenuPromptEnable,
  brandSetupPartialFailedBody,
  brandAnnouncementTitle,
  brandAnnouncementClose,
  brandAnnouncementDontShowAgain,
  brandAnnouncementGo,
  brandAnnouncementOpenFailed,
  brandAnnouncementExpiresAt,

  monitTitle,
  monitEmpty,
  monitAddSuccess,
  monitAddFail,
  monitFileNotSelected,
  monitDeleteDialogTitle,
  monitDeleteDialogContent,
  monitCancel,
  monitDelete,
  monitDeleteSuccess,
  monitSearchHint,
  monitNoResults,
  monitAddTaskAction,
  monitCleanInvalidAction,
  monitCleanInvalidTasksDialogTitle,
  monitInvalidTaskDialogItem,
  monitCleanInvalidTaskDialogBackupDirNotSet,
  monitCleanInvalidTaskDialogNoInvalidTasks,
  monitCleanInvalidTaskDialogCleaned,

  settingTitle,
  settingTitleBar,
  settingEnvironmentGroup,
  settingEnvironmentDescription,
  settingTraySupportTitle,
  settingWin11MenuEnvironmentTitle,
  settingAppearanceGroup,
  settingIntegrationsGroup,
  settingResourcesGroup,
  settingLanguage,
  settingContextMenuGroup,
  settingLinuxContextMenuGroup,
  settingThemeModeLabel,
  settingThemeModeSystem,
  settingThemeModeLight,
  settingThemeModeDark,
  settingContextMenuToggle,
  settingContextMenuLegacySuffix,
  settingLegacyMenuCollapseToggle,
  settingAddBackupMenu,
  settingAddExpressBackupMenu,
  settingAddMonitorMenu,
  settingAddShareMenu,
  settingAddViewtreeMenu,
  settingLinuxContextMenuToggle,
  settingLinuxContextMenuToggleInstallHint,
  settingMonitGroup,
  settingMonitRate,
  settingMonitMaxSize,
  settingHttpApiGroup,
  settingEnableLocalHttpApi,
  settingHttpApiStatus,
  settingHttpApiRunning,
  settingHttpApiStopped,
  settingHttpApiDocs,
  settingHttpApiCopyToken,
  settingHttpApiTokenCopied,
  settingLaunchToTray,
  settingLaunchMinimized,
  settingLaunchToTrayUnsupported,
  settingLaunchToTraySetupHint,
  settingEnableAutostart,
  settingOpenConfig,
  settingOpenLogs,
  settingVisitWebsite,
  settingDonate,
  settingVersionInfo,
  settingOpenGithub,
  settingCommandCopied,
  settingDetectingPlatformIntegration,
  settingSupportStatusAvailable,
  settingSupportStatusMissingDependency,
  settingSupportStatusInstalledButDisabled,
  settingSupportStatusUnavailable,
  settingSupportStatusUnknown,
  settingSupportStatusChecking,
  settingGnomeMenuUpdated,
  settingGnomeMenuUnavailable,
  settingGnomeMenuRestartHint,
  settingWin11MenuNeedsIdentity,
  settingWin11IdentityRequired,
  settingCopyRegisterCommand,
  settingCopyRefreshCommand,
  settingCopyConfigCommand,
  settingCopyAssistCommand,
  settingOpenUrlFailed,
  settingLocalHttpApiToggleFailed,
  settingNotifyAddBackup,
  settingNotifyRemoveBackup,
  settingNotifyAddMonitor,
  settingNotifyRemoveMonitor,
  settingNotifyAddShare,
  settingNotifyRemoveShare,
  settingNotifyAddView,
  settingNotifyRemoveView,
  settingNotifyEnableAutostart,
  settingNotifyDisableAutostart,
  settingNotifyAddExpress,
  settingNotifyRemoveExpress,
  settingHasNewVertion,

  vertreeTitle,
  vertreeFileTreeTitle,
  vertreeOverviewTitle,
  vertreeFocusVersion,
  vertreeLatestVersion,
  vertreeTotalNodes,
  vertreeTotalBranches,
  vertreeCanvasHint,

  monitcardMonitorStatus,
  monitcardBackupFolder,
  monitcardOpenBackupFolder,
  monitcardDelete,
  monitcardPause,
  monitcardClean,
  monitcardCleanSuccess,
  monitcardCleanFail,
  monitcardCleanDialogTitle,
  monitcardCleanDialogContent,
  monitcardCleanDialogCancel,
  monitcardCleanDialogConfirm,
  monitcardStatusRunning,
  monitcardStatusStopped,
  monitcardStatusEnabled,
  monitcardStatusDisabled,

  filetreeInputLabelTitle,
  filetreeInputLabelHint,
  filetreeInputCancel,
  filetreeInputConfirm,
  filetreeBackupBlockedHasChild,

  fileleafNoLabel,
  fileleafLastModified,
  fileleafOpenTitle,
  fileleafOpenContent,
  fileleafCancel,
  fileleafConfirm,
  fileleafMenuBackup,
  fileleafMenuBranch,
  fileleafMenuMonit,
  fileleafMenuProperty,
  fileleafMenuShare,
  fileleafMenuPreview,
  previewOpenSystem,
  previewFailed,
  previewBrowserHint,
  previewOpenBrowser,
  fileleafSharePreparing,
  fileleafShareCreateFailed,
  fileleafShareReady,
  fileleafShareDialogTitle,
  fileleafShareDialogHint,
  fileleafShareExpiresAt,
  fileleafShareLandingLink,
  fileleafShareCandidates,
  fileleafShareBrowserHint,
  fileleafShareCopiedLink,
  fileleafShareCopyLink,
  fileleafShareOpenLanding,
  fileleafShareOpenFailed,
  fileleafMonitTitle,
  fileleafMonitContent,
  fileleafNotifyFailed,
  fileleafNotifySuccess,
  fileleafNotifyHint,
  fileleafPropertyTitle,
  fileleafPropertyFullname,
  fileleafPropertyName,
  fileleafPropertyLabel,
  fileleafPropertyInputLabel,
  fileleafPropertyVersion,
  fileleafPropertyExt,
  fileleafPropertyPath,
  fileleafPropertySize,
  fileleafPropertyCreated,
  fileleafPropertyModified,
  fileleafPropertyClose,
  fileleafBranchLabel,
  fileleafRevisionLabel,

  trayToggleHide,
  trayToggleHideTooltip,
  trayToggleShow,
  trayToggleShowTooltip,
  trayBackup,
  trayBackupTooltip,
  trayExpressBackup,
  trayExpressBackupTooltip,
  trayMonit,
  trayMonitTooltip,
  trayShare,
  trayShareTooltip,
  trayViewTree,
  trayViewTreeTooltip,
  traySetting,
  traySettingTooltip,
  trayExit,
  trayExitTooltip,
}

class AppLocale {
  Lang lang = Lang.zhCn;
  Future<void>? _contextMenuRefreshTask;
  bool _contextMenuRefreshQueued = false;

  AppLocale() {
    _initializeLocale();
  }

  void _initializeLocale() {
    final String localeStr = configer.get<String>('locale', 'OTHER');
    final Lang configLang = Lang.fromString(localeStr);

    if (configLang == Lang.other) {
      final systemLocale = Platform.localeName.toLowerCase();
      if (systemLocale.startsWith('zh')) {
        lang = Lang.zhCn;
      } else if (systemLocale.startsWith('ja')) {
        lang = Lang.ja;
      } else if (systemLocale.startsWith('en')) {
        lang = Lang.en;
      } else {
        lang = Lang.zhCn;
      }
    } else {
      lang = configLang;
    }
    logger.info("AppLocale initialized. Language set to: ${lang.name}");
  }

  void changeLang(Lang newLang) {
    if (newLang.name == lang.name || newLang == Lang.other) {
      return;
    }
    lang = newLang;
    configer.set<String>('locale', newLang.name);

    _scheduleContextMenuRefresh();

    logger.info("AppLocale language changed to: ${lang.name}");
  }

  void _scheduleContextMenuRefresh() {
    if (!PlatformIntegration.isWindows) {
      return;
    }
    if (_contextMenuRefreshTask != null) {
      _contextMenuRefreshQueued = true;
      return;
    }

    _contextMenuRefreshTask = _refreshContextMenus();
  }

  Future<void> _refreshContextMenus() async {
    try {
      do {
        _contextMenuRefreshQueued = false;
        await PlatformIntegration.reAddContextMenu();
      } while (_contextMenuRefreshQueued);
    } finally {
      _contextMenuRefreshTask = null;
    }
  }

  List<Lang> get supportedLangs => [Lang.zhCn, Lang.en, Lang.ja];

  String getText(LocaleKey key) {
    final Map<LocaleKey, String> langMap;

    switch (lang) {
      case Lang.zhCn:
        langMap = _zhCn;
        break;
      case Lang.en:
        langMap = _en;
        break;
      case Lang.ja:
        langMap = _ja;
        break;
      case Lang.other:
        langMap = _zhCn;
        break;
    }

    return langMap[key] ?? _zhCn[key] ?? _en[key] ?? key.name;
  }

  static const Map<LocaleKey, String> _en = {
    LocaleKey.registryPreviewKeyName: 'Preview file · Vertree',
    LocaleKey.settingAddPreviewMenu: 'Preview file',
    LocaleKey.settingMenuUpdateFailed:
        'Could not update the context menu. Your changes were not fully applied.',
    LocaleKey.appTitle: "Vertree",
    LocaleKey.registryBackupKeyName: "Backup Files VerTree",
    LocaleKey.registryExpressBackupKeyName: "Quick Backup Files VerTree",
    LocaleKey.registryMonitorKeyName: "Monitor File Changes VerTree",
    LocaleKey.registryShareKeyName: "Share for LAN Download VerTree",
    LocaleKey.registryViewTreeKeyName: "View File Version Tree VerTree",

    LocaleKey.appConfirmExitTitle: "Confirm Exit",
    LocaleKey.appConfirmExitContent:
        "Are you sure you want to exit the application?",
    LocaleKey.appMinimize: "Minimize",
    LocaleKey.appExit: "Exit",

    LocaleKey.appTrayNotificationTitle: "Vertree running in background",
    LocaleKey.appTrayNotificationContent:
        "File version tree manager 🌲 (Click to open)",

    LocaleKey.appMonitStartedTitle: "Vertree started monitoring",
    LocaleKey.appMonitStartedContent: "Click to view monitoring tasks",

    LocaleKey.appBackupFailed: "Vertree failed to back up the file",
    LocaleKey.appBackupSuccessTitle: "Vertree backed up file",
    LocaleKey.appBackupSuccessContent: "Click to open new file",

    LocaleKey.appEnterLabelTitle: "Enter a note for backing up",
    LocaleKey.appEnterLabelHint: "Note (optional)",
    LocaleKey.appCancelBackup: "Cancel backup",
    LocaleKey.appConfirm: "Confirm",

    LocaleKey.appCancelNotificationTitle: "Vertree backup canceled",
    LocaleKey.appCancelNotificationContent:
        "User canceled the backup operation",

    LocaleKey.appLabelDialogError: "Failed to create label input dialog: ",

    LocaleKey.appEnableMonitTitle: "Enable monitoring?",
    LocaleKey.appEnableMonitContent:
        "Do you want to monitor the new version after backup?",
    LocaleKey.appYes: "Yes",
    LocaleKey.appNo: "No",

    LocaleKey.appMonitFailedTitle: "Vertree monitoring failed",
    LocaleKey.appMonitSuccessTitle: "Vertree started monitoring file",
    LocaleKey.appMonitSuccessContent: "Click to open backup folder",
    LocaleKey.appAdminPermissionTooFrequent:
        "Administrator elevation is being requested too frequently. Please try again later.",

    LocaleKey.brandTitle: 'Vertree',
    LocaleKey.brandSlogan:
        'Vertree, a tree-based file version manager 🌲, making every iteration worry-free!',
    LocaleKey.brandMonitorPage: 'Monitor Page',
    LocaleKey.brandSettingPage: 'Settings',
    LocaleKey.brandExit: 'Exit',
    LocaleKey.brandInitTitle: 'Initial Setup',
    LocaleKey.brandInitContent:
        'Allow Vertree to add context menu and enable auto start?',
    LocaleKey.brandCancel: 'Cancel',
    LocaleKey.brandConfirm: 'Confirm',
    LocaleKey.brandInitDoneTitle: 'Vertree setup complete!',
    LocaleKey.brandInitDoneBody: 'Let’s get started!',
    LocaleKey.brandExpressMenuPromptTitle:
        'Enable "Quick Backup" context menu?',
    LocaleKey.brandExpressMenuPromptContent:
        'This changes the system context menu and may require administrator permission.',
    LocaleKey.brandExpressMenuPromptLater: 'Later',
    LocaleKey.brandExpressMenuPromptEnable: 'Enable',
    LocaleKey.brandSetupPartialFailedBody:
        'Setup completed partially. Please retry in Settings and review platform integration support.',
    LocaleKey.brandAnnouncementTitle: 'Announcement',
    LocaleKey.brandAnnouncementClose: 'Close',
    LocaleKey.brandAnnouncementDontShowAgain: 'Do not show again',
    LocaleKey.brandAnnouncementGo: 'Open',
    LocaleKey.brandAnnouncementOpenFailed:
        'Unable to open the announcement link',
    LocaleKey.brandAnnouncementExpiresAt: 'Visible until %a',

    LocaleKey.monitTitle: 'Vertree Monitor',
    LocaleKey.monitEmpty: 'No monitoring tasks yet',
    LocaleKey.monitAddSuccess: 'Successfully added monitor task: %a',
    LocaleKey.monitAddFail: 'Failed to add task: %a',
    LocaleKey.monitFileNotSelected: 'No file selected',
    LocaleKey.monitDeleteDialogTitle: 'Confirm Delete',
    LocaleKey.monitDeleteDialogContent:
        'Are you sure you want to delete the monitor task: %a?',
    LocaleKey.monitCancel: 'Cancel',
    LocaleKey.monitDelete: 'Delete',
    LocaleKey.monitDeleteSuccess: 'Deleted monitor task: %a',
    LocaleKey.monitSearchHint: "Filter by keyword...",
    LocaleKey.monitNoResults: "No matching tasks found",
    LocaleKey.monitAddTaskAction: "Add file",
    LocaleKey.monitCleanInvalidAction: "Clean invalid tasks",

    LocaleKey.monitCleanInvalidTasksDialogTitle: "Clean Invalid Monitor Tasks",
    LocaleKey.monitInvalidTaskDialogItem: "File Path: %a, Backup Path: %a",
    LocaleKey.monitCleanInvalidTaskDialogBackupDirNotSet: "Backup path not set",
    LocaleKey.monitCleanInvalidTaskDialogNoInvalidTasks:
        "No invalid monitor tasks found",
    LocaleKey.monitCleanInvalidTaskDialogCleaned:
        "Invalid monitor tasks cleaned successfully",

    LocaleKey.settingTitle: "Settings",
    LocaleKey.settingTitleBar: "Vertree Settings",
    LocaleKey.settingEnvironmentGroup: "Environment setup",
    LocaleKey.settingEnvironmentDescription:
        "Install dependencies, complete desktop integration, and finish any manual setup here. These guidance cards disappear automatically once the environment is ready.",
    LocaleKey.settingTraySupportTitle: "Tray support",
    LocaleKey.settingWin11MenuEnvironmentTitle:
        "Windows 11 context menu environment",
    LocaleKey.settingAppearanceGroup: "Appearance",
    LocaleKey.settingIntegrationsGroup: "System Integration",
    LocaleKey.settingResourcesGroup: "Resources",
    LocaleKey.settingLanguage: "Language",
    LocaleKey.settingContextMenuGroup: "Context Menu Options",
    LocaleKey.settingLinuxContextMenuGroup: "GNOME Files context menu",
    LocaleKey.settingThemeModeLabel: "Theme mode",
    LocaleKey.settingThemeModeSystem: "Follow system",
    LocaleKey.settingThemeModeLight: "Light",
    LocaleKey.settingThemeModeDark: "Dark",
    LocaleKey.settingContextMenuToggle: "Context menu options",
    LocaleKey.settingContextMenuLegacySuffix: " (Legacy)",
    LocaleKey.settingLegacyMenuCollapseToggle:
        "Collapse legacy menu into a Vertree submenu",
    LocaleKey.settingAddBackupMenu: "Add 'Backup this file' to context menu",
    LocaleKey.settingAddExpressBackupMenu:
        "Add 'Express backup this file' to context menu",
    LocaleKey.settingAddMonitorMenu: "Add 'Monitor this file' to context menu",
    LocaleKey.settingAddShareMenu:
        "Add 'Share for LAN download' to context menu",
    LocaleKey.settingAddViewtreeMenu: "Add 'View version tree' to context menu",
    LocaleKey.settingLinuxContextMenuToggle: "Enable GNOME Files context menu",
    LocaleKey.settingLinuxContextMenuToggleInstallHint:
        "Enable GNOME Files context menu (requires nautilus-python)",
    LocaleKey.settingMonitGroup: "File Monitoring",
    LocaleKey.settingMonitRate: "Backup interval (minutes)",
    LocaleKey.settingMonitMaxSize:
        "Maximum backups to keep (oldest files are removed first)",
    LocaleKey.settingHttpApiGroup: "Local HTTP API",
    LocaleKey.settingEnableLocalHttpApi: "Enable loopback-only local HTTP API",
    LocaleKey.settingHttpApiStatus: "API status: %a",
    LocaleKey.settingHttpApiRunning: "Running",
    LocaleKey.settingHttpApiStopped: "Stopped",
    LocaleKey.settingHttpApiDocs: "Open API docs",
    LocaleKey.settingHttpApiCopyToken: "Copy API token",
    LocaleKey.settingHttpApiTokenCopied: "API token copied",
    LocaleKey.settingLaunchToTray: "Hide to tray on startup",
    LocaleKey.settingLaunchMinimized: "Launch minimized",
    LocaleKey.settingLaunchToTrayUnsupported:
        "Launch minimized to tray (tray support required)",
    LocaleKey.settingLaunchToTraySetupHint:
        "Tray support is not ready in the current GNOME session yet. Please complete the suggested setup first.",
    LocaleKey.settingEnableAutostart: "Enable Vertree on startup (Recommended)",
    LocaleKey.settingOpenConfig: "Open config.json",
    LocaleKey.settingOpenLogs: "Open logs folder",
    LocaleKey.settingVisitWebsite: "Visit official website",
    LocaleKey.settingDonate: "Donate & Support",
    LocaleKey.settingCommandCopied: "Command copied",
    LocaleKey.settingDetectingPlatformIntegration:
        "Detecting desktop integration support...",
    LocaleKey.settingSupportStatusAvailable: "Available",
    LocaleKey.settingSupportStatusMissingDependency: "Missing dependency",
    LocaleKey.settingSupportStatusInstalledButDisabled:
        "Installed but disabled",
    LocaleKey.settingSupportStatusUnavailable: "Unavailable in this session",
    LocaleKey.settingSupportStatusUnknown: "Unknown",
    LocaleKey.settingSupportStatusChecking: "Checking",
    LocaleKey.settingGnomeMenuUpdated:
        "GNOME Files context menu has been updated",
    LocaleKey.settingGnomeMenuUnavailable:
        "GNOME Files extension is unavailable. Install nautilus-python first.",
    LocaleKey.settingGnomeMenuRestartHint:
        "GNOME Files integration was updated. You may need to restart Files for the change to appear.",
    LocaleKey.settingWin11MenuNeedsIdentity:
        "Windows 11 menu registration failed. Make sure Vertree is fully installed and allow the admin prompt.",
    LocaleKey.settingWin11IdentityRequired:
        "The Windows 11 menu can be registered directly by the installer build. If Explorer still does not refresh, run the refresh command once.",
    LocaleKey.settingCopyRegisterCommand: "Copy register command",
    LocaleKey.settingCopyRefreshCommand: "Copy refresh command",
    LocaleKey.settingCopyConfigCommand: "Copy setup command",
    LocaleKey.settingCopyAssistCommand: "Copy helper command",
    LocaleKey.settingOpenUrlFailed: "Unable to open %a",
    LocaleKey.settingLocalHttpApiToggleFailed:
        "Failed to toggle Local HTTP API: %a",
    LocaleKey.settingOpenGithub: "View GitHub repo",
    LocaleKey.settingNotifyAddBackup:
        "Added 'Backup this file version' to context menu",
    LocaleKey.settingNotifyRemoveBackup:
        "Removed 'Backup this file version' from context menu",
    LocaleKey.settingNotifyAddMonitor:
        "Added 'Monitor this file' to context menu",
    LocaleKey.settingNotifyRemoveMonitor:
        "Removed 'Monitor this file' from context menu",
    LocaleKey.settingNotifyAddShare:
        "Added 'Share for LAN download' to context menu",
    LocaleKey.settingNotifyRemoveShare:
        "Removed 'Share for LAN download' from context menu",
    LocaleKey.settingNotifyAddView:
        "Added 'View file version tree' to context menu",
    LocaleKey.settingNotifyRemoveView:
        "Removed 'View file version tree' from context menu",
    LocaleKey.settingNotifyEnableAutostart: "Enabled autostart",
    LocaleKey.settingNotifyDisableAutostart: "Disabled autostart",
    LocaleKey.settingNotifyAddExpress:
        "Added 'Express backup this file' to context menu",
    LocaleKey.settingNotifyRemoveExpress:
        "Removed 'Express backup this file' from context menu",

    LocaleKey.vertreeTitle: "Vertree",
    LocaleKey.vertreeFileTreeTitle: "%a.%a File Version Tree",
    LocaleKey.vertreeOverviewTitle: "Version tree overview",
    LocaleKey.vertreeFocusVersion: "Focus version",
    LocaleKey.vertreeLatestVersion: "Latest version",
    LocaleKey.vertreeTotalNodes: "Total nodes",
    LocaleKey.vertreeTotalBranches: "Branch nodes",
    LocaleKey.vertreeCanvasHint:
        "Drag to pan, scroll to zoom, right click a node for actions",

    LocaleKey.monitcardMonitorStatus: "Monitoring of %a has been %a",
    LocaleKey.monitcardBackupFolder: "Backup Folder: %a",
    LocaleKey.monitcardOpenBackupFolder: "Open Backup Folder",
    LocaleKey.monitcardDelete: "Delete Monitor Task",
    LocaleKey.monitcardPause: "Pause",
    LocaleKey.monitcardClean: "Clean Backup Folder",
    LocaleKey.monitcardCleanSuccess: "Successfully cleaned backup folder %a",
    LocaleKey.monitcardCleanFail: "Failed to clean backup folder %a",
    LocaleKey.monitcardCleanDialogTitle: "Confirm Clean Backup Folder",
    LocaleKey.monitcardCleanDialogContent:
        "Are you sure you want to clean all files in backup folder %a? This action cannot be undone.",
    LocaleKey.monitcardCleanDialogCancel: "Cancel",
    LocaleKey.monitcardCleanDialogConfirm: "Confirm",
    LocaleKey.monitcardStatusEnabled: "enabled",
    LocaleKey.monitcardStatusDisabled: "disabled",

    LocaleKey.filetreeInputLabelTitle: "Enter a label",
    LocaleKey.filetreeInputLabelHint: "Enter a label (optional)",
    LocaleKey.filetreeInputCancel: "Cancel",
    LocaleKey.filetreeInputConfirm: "Confirm",
    LocaleKey.filetreeBackupBlockedHasChild:
        "This version already has a direct child, so backup is not allowed",

    LocaleKey.fileleafNoLabel: "No label",
    LocaleKey.fileleafLastModified: "Last modified",
    LocaleKey.fileleafOpenTitle: "Open file %a.%a?",
    LocaleKey.fileleafOpenContent: "You are about to open \"%a.%a\" version %a",
    LocaleKey.fileleafCancel: "Cancel",
    LocaleKey.fileleafConfirm: "Confirm",
    LocaleKey.fileleafMenuBackup: "Backup version",
    LocaleKey.fileleafMenuBranch: "Create branch",
    LocaleKey.fileleafMenuMonit: "Monitor changes",
    LocaleKey.fileleafMenuProperty: "Properties",
    LocaleKey.fileleafMenuShare: "Share on LAN",
    LocaleKey.fileleafMenuPreview: "Preview",
    LocaleKey.previewOpenSystem: "Open in default app",
    LocaleKey.previewFailed:
        "Could not load preview. You can open the file in its default app.",
    LocaleKey.previewBrowserHint:
        "On Linux, preview opens in your local browser. Keep this dialog open while viewing; closing it ends access to the file.",
    LocaleKey.previewOpenBrowser: "Preview in browser",
    LocaleKey.fileleafSharePreparing: "Preparing LAN share...",
    LocaleKey.fileleafShareCreateFailed: "Unable to create LAN share: %a",
    LocaleKey.fileleafShareReady:
        "LAN download is ready for %a. Click to view.",
    LocaleKey.fileleafShareDialogTitle: "LAN share for %a",
    LocaleKey.fileleafShareDialogHint:
        "Scan the QR code or send the short share link. The browser will try the candidate LAN addresses automatically, then download the file.",
    LocaleKey.fileleafShareExpiresAt: "Expires at",
    LocaleKey.fileleafShareLandingLink: "Short share link",
    LocaleKey.fileleafShareCandidates: "Direct LAN download candidates",
    LocaleKey.fileleafShareBrowserHint:
        "If the share page cannot auto-detect the route in your browser, use one of the direct LAN links below.",
    LocaleKey.fileleafShareCopiedLink: "Link copied",
    LocaleKey.fileleafShareCopyLink: "Copy link",
    LocaleKey.fileleafShareOpenLanding: "Open share page",
    LocaleKey.fileleafShareOpenFailed: "Unable to open the share page",
    LocaleKey.fileleafMonitTitle: "Confirm file monitoring",
    LocaleKey.fileleafMonitContent: "Start monitoring file \"%a.%a\"?",
    LocaleKey.fileleafNotifyFailed: "Vertree monitoring failed,",
    LocaleKey.fileleafNotifySuccess: "Vertree is now monitoring file",
    LocaleKey.fileleafNotifyHint: "Click me to open backup folder",

    LocaleKey.fileleafPropertyTitle: "File Properties",
    LocaleKey.fileleafPropertyFullname: "Full Name:",
    LocaleKey.fileleafPropertyName: "Name:",
    LocaleKey.fileleafPropertyLabel: "Label:",
    LocaleKey.fileleafPropertyInputLabel: "Enter label",
    LocaleKey.fileleafPropertyVersion: "Version:",
    LocaleKey.fileleafPropertyExt: "Extension:",
    LocaleKey.fileleafPropertyPath: "Path:",
    LocaleKey.fileleafPropertySize: "File Size:",
    LocaleKey.fileleafPropertyCreated: "Created Time:",
    LocaleKey.fileleafPropertyModified: "Modified Time:",
    LocaleKey.fileleafPropertyClose: "Close",
    LocaleKey.fileleafBranchLabel: "Branch",
    LocaleKey.fileleafRevisionLabel: "Revision",

    LocaleKey.trayToggleHide: "Hide to tray",
    LocaleKey.trayToggleHideTooltip: "Hide the window to the tray",
    LocaleKey.trayToggleShow: "Show main window",
    LocaleKey.trayToggleShowTooltip: "Show the main window",
    LocaleKey.trayBackup: "Back up file",
    LocaleKey.trayBackupTooltip: "Choose a file to back up",
    LocaleKey.trayExpressBackup: "Quick backup",
    LocaleKey.trayExpressBackupTooltip: "Choose a file for quick backup",
    LocaleKey.trayMonit: "Monitor file",
    LocaleKey.trayMonitTooltip: "Choose a file to add to monitoring",
    LocaleKey.trayShare: "Share on LAN",
    LocaleKey.trayShareTooltip: "Choose a file to create a LAN download link",
    LocaleKey.trayViewTree: "View version tree",
    LocaleKey.trayViewTreeTooltip: "Choose a file to inspect its version tree",
    LocaleKey.traySetting: "Settings",
    LocaleKey.traySettingTooltip: "Open app settings",
    LocaleKey.trayExit: "Exit",
    LocaleKey.trayExitTooltip: "Quit the app",
  };

  static const Map<LocaleKey, String> _zhCn = {
    LocaleKey.registryPreviewKeyName: '预览文件 · Vertree',
    LocaleKey.settingAddPreviewMenu: '预览文件',
    LocaleKey.settingMenuUpdateFailed: '右键菜单更新失败，未能完整应用更改。',
    LocaleKey.appTitle: "Vertree维树",
    LocaleKey.registryBackupKeyName: "备份文件 VerTree",
    LocaleKey.registryExpressBackupKeyName: "快速备份文件 VerTree",
    LocaleKey.registryMonitorKeyName: "监控文件变动 VerTree",
    LocaleKey.registryShareKeyName: "局域网分享下载 VerTree",
    LocaleKey.registryViewTreeKeyName: "查看文件版本树 VerTree",

    LocaleKey.appConfirmExitTitle: "确认退出",
    LocaleKey.appConfirmExitContent: "确定要退出应用吗？",
    LocaleKey.appMinimize: "最小化",
    LocaleKey.appExit: "退出",

    LocaleKey.appTrayNotificationTitle: "Vertree最小化运行中",
    LocaleKey.appTrayNotificationContent: "树状文件版本管理🌲（点我打开）",

    LocaleKey.appMonitStartedTitle: "Vertree开始监控",
    LocaleKey.appMonitStartedContent: "点击查看监控任务",

    LocaleKey.appBackupFailed: "Vertree 备份文件失败",
    LocaleKey.appBackupSuccessTitle: "Vertree 已备份文件",
    LocaleKey.appBackupSuccessContent: "点击我打开新文件",

    LocaleKey.appEnterLabelTitle: "请输入备份备注（可选）",
    LocaleKey.appEnterLabelHint: "备注信息（可选）",
    LocaleKey.appCancelBackup: "取消备份",
    LocaleKey.appConfirm: "确定",

    LocaleKey.appCancelNotificationTitle: "Vertree 备份已取消",
    LocaleKey.appCancelNotificationContent: "用户取消了备份操作",

    LocaleKey.appLabelDialogError: "创建询问备注对话框失败：",

    LocaleKey.appEnableMonitTitle: "开启监控？",
    LocaleKey.appEnableMonitContent: "是否对备份的新版本进行监控？",
    LocaleKey.appYes: "是",
    LocaleKey.appNo: "否",

    LocaleKey.appMonitFailedTitle: "Vertree监控失败",
    LocaleKey.appMonitSuccessTitle: "Vertree已开始监控文件",
    LocaleKey.appMonitSuccessContent: "点击我打开备份目录",
    LocaleKey.appAdminPermissionTooFrequent: "获得管理员权限频率过高，请稍后再试。",

    LocaleKey.brandTitle: 'Vertree维树',
    LocaleKey.brandSlogan: 'Vertree维树，树状文件版本管理🌲，让每一次迭代都有备无患！',
    LocaleKey.brandMonitorPage: '监控页',
    LocaleKey.brandSettingPage: '设置页',
    LocaleKey.brandExit: '退出',
    LocaleKey.brandInitTitle: '初始化设置',
    LocaleKey.brandInitContent: '是否允许Vertree添加右键菜单和开机启动？',
    LocaleKey.brandCancel: '取消',
    LocaleKey.brandConfirm: '确定',
    LocaleKey.brandInitDoneTitle: 'Vertree初始设置已完成！',
    LocaleKey.brandInitDoneBody: '开始使用吧！',
    LocaleKey.brandExpressMenuPromptTitle: '启用“快速备份”右键菜单？',
    LocaleKey.brandExpressMenuPromptContent: '此操作会修改系统右键菜单，可能需要管理员权限授权。',
    LocaleKey.brandExpressMenuPromptLater: '稍后',
    LocaleKey.brandExpressMenuPromptEnable: '启用',
    LocaleKey.brandSetupPartialFailedBody: '初始化部分失败，请在设置页面重试并检查平台集成能力。',
    LocaleKey.brandAnnouncementTitle: '公告',
    LocaleKey.brandAnnouncementClose: '关闭',
    LocaleKey.brandAnnouncementDontShowAgain: '不再显示',
    LocaleKey.brandAnnouncementGo: '前往',
    LocaleKey.brandAnnouncementOpenFailed: '无法打开公告链接',
    LocaleKey.brandAnnouncementExpiresAt: '显示截止到 %a',

    LocaleKey.monitTitle: 'Vertree 监控',
    LocaleKey.monitEmpty: '暂无监控任务',
    LocaleKey.monitAddSuccess: '成功添加监控任务: %a',
    LocaleKey.monitAddFail: '添加失败: %a',
    LocaleKey.monitFileNotSelected: '未选择文件',
    LocaleKey.monitDeleteDialogTitle: '确认删除',
    LocaleKey.monitDeleteDialogContent:
        '确定要删除监控任务: %a 吗？此操作会一并删除相应的备份文件夹和所有备份内容！',
    LocaleKey.monitCancel: '取消',
    LocaleKey.monitDelete: '删除',
    LocaleKey.monitDeleteSuccess: '已删除监控任务: %a',
    LocaleKey.monitSearchHint: "按关键字筛选...",
    LocaleKey.monitNoResults: "未找到匹配搜索的任务",
    LocaleKey.monitAddTaskAction: "添加文件",
    LocaleKey.monitCleanInvalidAction: "清理无效任务",

    LocaleKey.monitCleanInvalidTasksDialogTitle: "清理无效监控任务",
    LocaleKey.monitInvalidTaskDialogItem: "文件路径：%a，备份路径：%a",
    LocaleKey.monitCleanInvalidTaskDialogBackupDirNotSet: "未设置备份路径",
    LocaleKey.monitCleanInvalidTaskDialogNoInvalidTasks: "未发现无效监控任务",
    LocaleKey.monitCleanInvalidTaskDialogCleaned: "无效监控任务已成功清理",

    LocaleKey.settingTitle: "设置",
    LocaleKey.settingLanguage: '语言',
    LocaleKey.settingTitleBar: "Vertree 设置",
    LocaleKey.settingEnvironmentGroup: "环境准备",
    LocaleKey.settingEnvironmentDescription:
        "依赖安装、环境配置和需要手动处理的系统集成都集中放在这里。完成后，这些引导卡片会自动消失。",
    LocaleKey.settingTraySupportTitle: "托盘支持",
    LocaleKey.settingWin11MenuEnvironmentTitle: "Windows 11 新菜单环境",
    LocaleKey.settingAppearanceGroup: "界面与外观",
    LocaleKey.settingIntegrationsGroup: "系统集成",
    LocaleKey.settingResourcesGroup: "资源与文件",
    LocaleKey.settingContextMenuGroup: "右键菜单选项",
    LocaleKey.settingLinuxContextMenuGroup: "GNOME Files 右键菜单",
    LocaleKey.settingThemeModeLabel: "主题模式",
    LocaleKey.settingThemeModeSystem: "跟随系统",
    LocaleKey.settingThemeModeLight: "浅色",
    LocaleKey.settingThemeModeDark: "暗色",
    LocaleKey.settingContextMenuToggle: "右键菜单选项",
    LocaleKey.settingContextMenuLegacySuffix: "（旧版）",
    LocaleKey.settingLegacyMenuCollapseToggle: "将旧版右键菜单收起到 Vertree 二级菜单",
    LocaleKey.settingAddBackupMenu: "将“备份该文件”增加到右键菜单",
    LocaleKey.settingAddExpressBackupMenu: "将“快速备份该文件”增加到右键菜单",
    LocaleKey.settingAddMonitorMenu: "将“监控该文件”增加到右键菜单",
    LocaleKey.settingAddShareMenu: "将“局域网分享下载”增加到右键菜单",
    LocaleKey.settingAddViewtreeMenu: "将“浏览该文件版本树”增加到右键菜单",
    LocaleKey.settingLinuxContextMenuToggle: "启用 GNOME Files 右键菜单",
    LocaleKey.settingLinuxContextMenuToggleInstallHint:
        "启用 GNOME Files 右键菜单（需先安装 nautilus-python）",

    LocaleKey.settingMonitGroup: "监控文件设置",
    LocaleKey.settingMonitRate: "备份文件时间间隔（单位分钟）",
    LocaleKey.settingMonitMaxSize: "备份文件最多数量（会滚动删除旧文件）",
    LocaleKey.settingHttpApiGroup: "本机 HTTP API",
    LocaleKey.settingEnableLocalHttpApi: "启用仅本机可访问的 HTTP API",
    LocaleKey.settingHttpApiStatus: "API 状态：%a",
    LocaleKey.settingHttpApiRunning: "运行中",
    LocaleKey.settingHttpApiStopped: "未启动",
    LocaleKey.settingHttpApiDocs: "打开 API 文档",
    LocaleKey.settingHttpApiCopyToken: "复制 API Token",
    LocaleKey.settingHttpApiTokenCopied: "API Token 已复制",
    LocaleKey.settingLaunchToTray: "启动后隐藏到托盘",
    LocaleKey.settingLaunchMinimized: "启动后最小化",
    LocaleKey.settingLaunchToTrayUnsupported: "启动后最小化到托盘（需先启用托盘支持）",
    LocaleKey.settingLaunchToTraySetupHint: "当前 GNOME 会话尚未启用托盘支持，请先按提示完成配置。",
    LocaleKey.settingEnableAutostart: "开机自启 Vertree（推荐）",
    LocaleKey.settingOpenConfig: "打开 config.json",
    LocaleKey.settingOpenLogs: "打开日志文件夹",

    LocaleKey.settingVisitWebsite: "访问官方网站",
    LocaleKey.settingDonate: "捐助和支持",
    LocaleKey.settingVersionInfo: "版本信息",
    LocaleKey.settingCommandCopied: "已复制命令",
    LocaleKey.settingDetectingPlatformIntegration: "正在检测 GNOME 集成能力...",
    LocaleKey.settingSupportStatusAvailable: "已可用",
    LocaleKey.settingSupportStatusMissingDependency: "缺少支持组件",
    LocaleKey.settingSupportStatusInstalledButDisabled: "已安装但未启用",
    LocaleKey.settingSupportStatusUnavailable: "当前会话不可用",
    LocaleKey.settingSupportStatusUnknown: "状态未知",
    LocaleKey.settingSupportStatusChecking: "检测中",
    LocaleKey.settingGnomeMenuUpdated: "GNOME Files 右键菜单已更新",
    LocaleKey.settingGnomeMenuUnavailable:
        "GNOME Files 扩展不可用，请先安装 nautilus-python",
    LocaleKey.settingGnomeMenuRestartHint: "GNOME Files 扩展已更新，可能需要重启“文件”应用后生效",
    LocaleKey.settingWin11MenuNeedsIdentity:
        "Win11 新菜单注册失败，请确认已安装完整 Vertree 并允许管理员授权",
    LocaleKey.settingWin11IdentityRequired:
        "Windows 11 新菜单默认可由安装版直接注册；如果 Explorer 没有刷新，可再执行一次刷新命令。",
    LocaleKey.settingCopyRegisterCommand: "复制注册命令",
    LocaleKey.settingCopyRefreshCommand: "复制刷新命令",
    LocaleKey.settingCopyConfigCommand: "复制配置命令",
    LocaleKey.settingCopyAssistCommand: "复制辅助命令",
    LocaleKey.settingOpenUrlFailed: "无法打开 %a",
    LocaleKey.settingLocalHttpApiToggleFailed: "Local HTTP API 启停失败: %a",
    LocaleKey.settingOpenGithub: "查看 GitHub 仓库",
    LocaleKey.settingNotifyAddBackup: "已添加 '备份当前文件版本' 到右键菜单",
    LocaleKey.settingNotifyRemoveBackup: "已从右键菜单移除 '备份当前文件版本' 功能按钮",
    LocaleKey.settingNotifyAddMonitor: "已添加 '监控该文件' 到右键菜单",
    LocaleKey.settingNotifyRemoveMonitor: "已从右键菜单移除 '监控该文件' 功能按钮",
    LocaleKey.settingNotifyAddShare: "已添加 '局域网分享下载' 到右键菜单",
    LocaleKey.settingNotifyRemoveShare: "已从右键菜单移除 '局域网分享下载' 功能按钮",
    LocaleKey.settingNotifyAddView: "已添加 '浏览文件版本树' 到右键菜单",
    LocaleKey.settingNotifyRemoveView: "已从右键菜单移除 '浏览文件版本树' 功能按钮",
    LocaleKey.settingNotifyEnableAutostart: "已启用开机自启",
    LocaleKey.settingNotifyDisableAutostart: "已禁用开机自启",
    LocaleKey.settingNotifyAddExpress: "已添加 '快速备份该文件' 到右键菜单",
    LocaleKey.settingNotifyRemoveExpress: "已从右键菜单移除 '快速备份该文件' 功能按钮",
    LocaleKey.settingHasNewVertion: "有新版本：%a",

    LocaleKey.vertreeTitle: "Vertree维树",
    LocaleKey.vertreeFileTreeTitle: "%a.%a 文件版本树",
    LocaleKey.vertreeOverviewTitle: "版本树概览",
    LocaleKey.vertreeFocusVersion: "焦点版本",
    LocaleKey.vertreeLatestVersion: "最新版本",
    LocaleKey.vertreeTotalNodes: "节点总数",
    LocaleKey.vertreeTotalBranches: "分支节点",
    LocaleKey.vertreeCanvasHint: "拖动画布可平移，滚轮可缩放，右键节点可查看更多操作",

    LocaleKey.monitcardMonitorStatus: "%a的监控已经%a",
    LocaleKey.monitcardBackupFolder: "备份文件夹：%a",
    LocaleKey.monitcardOpenBackupFolder: "打开备份文件夹",
    LocaleKey.monitcardDelete: "删除监控任务",
    LocaleKey.monitcardPause: "暂停",
    LocaleKey.monitcardClean: "清理备份文件夹",
    LocaleKey.monitcardCleanSuccess: "清理备份文件夹 %a 成功",
    LocaleKey.monitcardCleanFail: "清理备份文件夹 %a 失败",
    LocaleKey.monitcardCleanDialogTitle: "确认清理备份文件夹",
    LocaleKey.monitcardCleanDialogContent: "确定要清理备份文件夹 %a 中的所有文件吗？此操作不可撤销。",
    LocaleKey.monitcardCleanDialogCancel: "取消",
    LocaleKey.monitcardCleanDialogConfirm: "确认",
    LocaleKey.monitcardStatusRunning: "监控中..",
    LocaleKey.monitcardStatusStopped: "已暂停",
    LocaleKey.monitcardStatusEnabled: "开启",
    LocaleKey.monitcardStatusDisabled: "关闭",

    LocaleKey.filetreeInputLabelTitle: "请输入备注",
    LocaleKey.filetreeInputLabelHint: "请输入备注（可选）",
    LocaleKey.filetreeInputCancel: "取消",
    LocaleKey.filetreeInputConfirm: "确认",
    LocaleKey.filetreeBackupBlockedHasChild: "当前版本已有长子，不允许备份",

    LocaleKey.fileleafNoLabel: "无备注",
    LocaleKey.fileleafLastModified: "最后修改",
    LocaleKey.fileleafOpenTitle: "打开文件 %a.%a ?",
    LocaleKey.fileleafOpenContent: "即将打开 \"%a.%a\" %a 版",
    LocaleKey.fileleafCancel: "取消",
    LocaleKey.fileleafConfirm: "确认",
    LocaleKey.fileleafMenuBackup: "备份版本",
    LocaleKey.fileleafMenuBranch: "新建分支",
    LocaleKey.fileleafMenuMonit: "监控变更",
    LocaleKey.fileleafMenuProperty: "属性",
    LocaleKey.fileleafMenuShare: "分享到局域网",
    LocaleKey.fileleafMenuPreview: "预览",
    LocaleKey.previewOpenSystem: "用系统程序打开",
    LocaleKey.previewFailed: "无法加载预览，可以使用系统程序打开文件。",
    LocaleKey.previewBrowserHint: "Linux 使用本机浏览器显示预览。预览时请保持此窗口打开，关闭后将停止提供文件。",
    LocaleKey.previewOpenBrowser: "在浏览器中预览",
    LocaleKey.fileleafSharePreparing: "正在准备局域网分享…",
    LocaleKey.fileleafShareCreateFailed: "创建局域网分享失败：%a",
    LocaleKey.fileleafShareReady: "%a 的局域网下载已生成，点击查看。",
    LocaleKey.fileleafShareDialogTitle: "%a 的局域网分享",
    LocaleKey.fileleafShareDialogHint:
        "接收方可以扫码或打开短分享链接。页面会优先自动探测可达的局域网地址，再触发下载。",
    LocaleKey.fileleafShareExpiresAt: "失效时间",
    LocaleKey.fileleafShareLandingLink: "短分享链接",
    LocaleKey.fileleafShareCandidates: "局域网直连候选地址",
    LocaleKey.fileleafShareBrowserHint: "如果浏览器无法在分享页里自动选路，可以直接使用下面任一局域网下载链接。",
    LocaleKey.fileleafShareCopiedLink: "链接已复制",
    LocaleKey.fileleafShareCopyLink: "复制链接",
    LocaleKey.fileleafShareOpenLanding: "打开分享页",
    LocaleKey.fileleafShareOpenFailed: "无法打开分享页",
    LocaleKey.fileleafMonitTitle: "确认文件监控",
    LocaleKey.fileleafMonitContent: "确定要开始监控文件 \"%a.%a\" 吗？",
    LocaleKey.fileleafNotifyFailed: "Vertree监控失败，",
    LocaleKey.fileleafNotifySuccess: "Vertree已开始监控文件",
    LocaleKey.fileleafNotifyHint: "点击我打开备份目录",

    LocaleKey.fileleafPropertyTitle: "文件属性",
    LocaleKey.fileleafPropertyFullname: "全名:",
    LocaleKey.fileleafPropertyName: "名称:",
    LocaleKey.fileleafPropertyLabel: "备注:",
    LocaleKey.fileleafPropertyInputLabel: "请输入备注",
    LocaleKey.fileleafPropertyVersion: "版本:",
    LocaleKey.fileleafPropertyExt: "扩展名:",
    LocaleKey.fileleafPropertyPath: "路径:",
    LocaleKey.fileleafPropertySize: "文件大小:",
    LocaleKey.fileleafPropertyCreated: "创建时间:",
    LocaleKey.fileleafPropertyModified: "修改时间:",
    LocaleKey.fileleafPropertyClose: "关闭",
    LocaleKey.fileleafBranchLabel: "分支",
    LocaleKey.fileleafRevisionLabel: "版本",

    LocaleKey.trayToggleHide: "隐藏到托盘",
    LocaleKey.trayToggleHideTooltip: "将窗口隐藏到托盘",
    LocaleKey.trayToggleShow: "显示主窗口",
    LocaleKey.trayToggleShowTooltip: "显示主窗口",
    LocaleKey.trayBackup: "备份文件",
    LocaleKey.trayBackupTooltip: "选择文件进行备份",
    LocaleKey.trayExpressBackup: "快速备份",
    LocaleKey.trayExpressBackupTooltip: "选择文件进行快速备份",
    LocaleKey.trayMonit: "监控文件",
    LocaleKey.trayMonitTooltip: "选择文件加入监控",
    LocaleKey.trayShare: "局域网分享",
    LocaleKey.trayShareTooltip: "选择文件生成局域网下载链接",
    LocaleKey.trayViewTree: "查看版本树",
    LocaleKey.trayViewTreeTooltip: "选择文件查看版本树",
    LocaleKey.traySetting: "设置",
    LocaleKey.traySettingTooltip: "App设置",
    LocaleKey.trayExit: "退出",
    LocaleKey.trayExitTooltip: "退出APP",
  };

  static const Map<LocaleKey, String> _ja = {
    LocaleKey.registryPreviewKeyName: 'ファイルをプレビュー · Vertree',
    LocaleKey.settingAddPreviewMenu: 'ファイルをプレビュー',
    LocaleKey.settingMenuUpdateFailed: 'コンテキストメニューを更新できませんでした。',
    LocaleKey.appTitle: "Vertree",
    LocaleKey.registryBackupKeyName: "バックアップファイル VerTree",
    LocaleKey.registryExpressBackupKeyName: "クイックバックアップファイル VerTree",
    LocaleKey.registryMonitorKeyName: "ファイル変更監視 VerTree",
    LocaleKey.registryShareKeyName: "LAN ダウンロード共有 VerTree",
    LocaleKey.registryViewTreeKeyName: "ファイルバージョンツリー表示 VerTree",

    LocaleKey.appConfirmExitTitle: "終了の確認",
    LocaleKey.appConfirmExitContent: "アプリを終了してもよろしいですか？",
    LocaleKey.appMinimize: "最小化",
    LocaleKey.appExit: "終了",

    LocaleKey.appTrayNotificationTitle: "Vertree はバックグラウンドで実行中",
    LocaleKey.appTrayNotificationContent: "ファイルバージョンツリーマネージャー 🌲（クリックして開く）",

    LocaleKey.appMonitStartedTitle: "Vertree は監視を開始しました",
    LocaleKey.appMonitStartedContent: "クリックして監視タスクを表示",

    LocaleKey.appBackupFailed: "Vertree のバックアップに失敗しました",
    LocaleKey.appBackupSuccessTitle: "Vertree はファイルをバックアップしました",
    LocaleKey.appBackupSuccessContent: "クリックして新しいファイルを開く",

    LocaleKey.appEnterLabelTitle: "バックアップのメモを入力してください（任意）",
    LocaleKey.appEnterLabelHint: "メモ（任意）",
    LocaleKey.appCancelBackup: "バックアップをキャンセル",
    LocaleKey.appConfirm: "確認",

    LocaleKey.appCancelNotificationTitle: "Vertree バックアップがキャンセルされました",
    LocaleKey.appCancelNotificationContent: "ユーザーがバックアップ操作をキャンセルしました",

    LocaleKey.appLabelDialogError: "メモ入力ダイアログの作成に失敗しました：",

    LocaleKey.appEnableMonitTitle: "監視を有効にしますか？",
    LocaleKey.appEnableMonitContent: "バックアップ後の新しいバージョンを監視しますか？",
    LocaleKey.appYes: "はい",
    LocaleKey.appNo: "いいえ",

    LocaleKey.appMonitFailedTitle: "Vertree の監視に失敗しました",
    LocaleKey.appMonitSuccessTitle: "Vertree はファイルの監視を開始しました",
    LocaleKey.appMonitSuccessContent: "クリックしてバックアップフォルダーを開く",
    LocaleKey.appAdminPermissionTooFrequent:
        "管理者権限の要求回数が多すぎます。しばらくしてから再試行してください。",

    LocaleKey.brandTitle: 'Vertree',
    LocaleKey.brandSlogan: 'Vertree、ツリー型のファイルバージョン管理🌲、すべての変更を安全に！',
    LocaleKey.brandMonitorPage: 'モニター画面',
    LocaleKey.brandSettingPage: '設定画面',
    LocaleKey.brandExit: '終了',
    LocaleKey.brandInitTitle: '初期設定',
    LocaleKey.brandInitContent: 'Vertreeに右クリックメニューと自動起動を許可しますか？',
    LocaleKey.brandCancel: 'キャンセル',
    LocaleKey.brandConfirm: '確認',
    LocaleKey.brandInitDoneTitle: 'Vertreeの初期設定が完了しました！',
    LocaleKey.brandInitDoneBody: 'さあ、始めましょう！',
    LocaleKey.brandExpressMenuPromptTitle: '「クイックバックアップ」右クリックメニューを有効にしますか？',
    LocaleKey.brandExpressMenuPromptContent:
        'この操作はシステムの右クリックメニューを変更し、管理者権限が必要になる場合があります。',
    LocaleKey.brandExpressMenuPromptLater: '後で',
    LocaleKey.brandExpressMenuPromptEnable: '有効にする',
    LocaleKey.brandSetupPartialFailedBody:
        '初期設定の一部に失敗しました。設定画面から再試行し、プラットフォーム連携の状態を確認してください。',
    LocaleKey.brandAnnouncementTitle: 'お知らせ',
    LocaleKey.brandAnnouncementClose: '閉じる',
    LocaleKey.brandAnnouncementDontShowAgain: '今後は表示しない',
    LocaleKey.brandAnnouncementGo: '開く',
    LocaleKey.brandAnnouncementOpenFailed: 'お知らせのリンクを開けませんでした',
    LocaleKey.brandAnnouncementExpiresAt: '%a まで表示',

    LocaleKey.monitTitle: 'Vertree モニター',
    LocaleKey.monitEmpty: '監視タスクはありません',
    LocaleKey.monitAddSuccess: '監視タスクを追加しました: %a',
    LocaleKey.monitAddFail: 'タスクの追加に失敗しました: %a',
    LocaleKey.monitFileNotSelected: 'ファイルが選択されていません',
    LocaleKey.monitDeleteDialogTitle: '削除の確認',
    LocaleKey.monitDeleteDialogContent:
        '監視タスク %a を削除しますか？対応するバックアップフォルダとすべてのバックアップ内容も削除されます！',

    LocaleKey.monitCancel: 'キャンセル',
    LocaleKey.monitDelete: '削除',
    LocaleKey.monitDeleteSuccess: '監視タスクを削除しました: %a',
    LocaleKey.monitSearchHint: "キーワードで絞り込む...",
    LocaleKey.monitNoResults: "一致するタスクが見つかりません",
    LocaleKey.monitAddTaskAction: "ファイルを追加",
    LocaleKey.monitCleanInvalidAction: "無効なタスクを整理",

    LocaleKey.monitCleanInvalidTasksDialogTitle: "無効な監視タスクのクリーンアップ",
    LocaleKey.monitInvalidTaskDialogItem: "ファイルパス：%a、バックアップパス：%a",
    LocaleKey.monitCleanInvalidTaskDialogBackupDirNotSet: "バックアップパスが設定されていません",
    LocaleKey.monitCleanInvalidTaskDialogNoInvalidTasks: "無効な監視タスクは見つかりませんでした",
    LocaleKey.monitCleanInvalidTaskDialogCleaned: "無効な監視タスクが正常にクリーンアップされました",

    LocaleKey.settingTitle: "設定",
    LocaleKey.settingLanguage: '言語',
    LocaleKey.settingTitleBar: "Vertree 設定",
    LocaleKey.settingEnvironmentGroup: "環境セットアップ",
    LocaleKey.settingEnvironmentDescription:
        "依存関係の導入、デスクトップ連携、手動セットアップが必要な項目をここにまとめています。環境が整うと、これらの案内カードは自動で消えます。",
    LocaleKey.settingTraySupportTitle: "トレイ対応",
    LocaleKey.settingWin11MenuEnvironmentTitle: "Windows 11 コンテキストメニュー環境",
    LocaleKey.settingAppearanceGroup: "外観",
    LocaleKey.settingIntegrationsGroup: "システム連携",
    LocaleKey.settingResourcesGroup: "リソース",
    LocaleKey.settingContextMenuGroup: "右クリックメニュー項目",
    LocaleKey.settingLinuxContextMenuGroup: "GNOME Files 右クリックメニュー",
    LocaleKey.settingThemeModeLabel: "テーマモード",
    LocaleKey.settingThemeModeSystem: "システムに従う",
    LocaleKey.settingThemeModeLight: "ライト",
    LocaleKey.settingThemeModeDark: "ダーク",
    LocaleKey.settingContextMenuToggle: "右クリックメニュー項目",
    LocaleKey.settingContextMenuLegacySuffix: "（旧版）",
    LocaleKey.settingLegacyMenuCollapseToggle: "旧版メニューを Vertree サブメニューに折りたたむ",
    LocaleKey.settingAddBackupMenu: "「このファイルをバックアップ」を右クリックメニューに追加",
    LocaleKey.settingAddExpressBackupMenu: "「このファイルを即時バックアップ」を右クリックメニューに追加",
    LocaleKey.settingAddMonitorMenu: "「このファイルを監視」を右クリックメニューに追加",
    LocaleKey.settingAddShareMenu: "「LAN ダウンロード共有」を右クリックメニューに追加",
    LocaleKey.settingAddViewtreeMenu: "「バージョンツリーを表示」を右クリックメニューに追加",
    LocaleKey.settingLinuxContextMenuToggle: "GNOME Files の右クリックメニューを有効にする",
    LocaleKey.settingLinuxContextMenuToggleInstallHint:
        "GNOME Files の右クリックメニューを有効にする（nautilus-python が必要）",
    LocaleKey.settingMonitGroup: "ファイル監視",
    LocaleKey.settingMonitRate: "バックアップ間隔（分）",
    LocaleKey.settingMonitMaxSize: "保持するバックアップ数の上限（古いファイルから削除）",
    LocaleKey.settingHttpApiGroup: "ローカル HTTP API",
    LocaleKey.settingEnableLocalHttpApi: "ループバック限定のローカル HTTP API を有効にする",
    LocaleKey.settingHttpApiStatus: "API 状態: %a",
    LocaleKey.settingHttpApiRunning: "稼働中",
    LocaleKey.settingHttpApiStopped: "停止中",
    LocaleKey.settingHttpApiDocs: "API ドキュメントを開く",
    LocaleKey.settingHttpApiCopyToken: "API トークンをコピー",
    LocaleKey.settingHttpApiTokenCopied: "API トークンをコピーしました",
    LocaleKey.settingLaunchToTray: "起動後にトレイへ隠す",
    LocaleKey.settingLaunchMinimized: "起動時に最小化",
    LocaleKey.settingLaunchToTrayUnsupported: "起動時にトレイへ最小化する（トレイ対応が必要）",
    LocaleKey.settingLaunchToTraySetupHint:
        "現在の GNOME セッションではまだトレイ対応が有効になっていません。案内に従って先に設定してください。",
    LocaleKey.settingEnableAutostart: "起動時に Vertree を自動実行（推奨）",
    LocaleKey.settingOpenConfig: "config.json を開く",
    LocaleKey.settingOpenLogs: "ログフォルダを開く",
    LocaleKey.settingVisitWebsite: "公式サイトを訪問",
    LocaleKey.settingDonate: "寄付とサポート",
    LocaleKey.settingCommandCopied: "コマンドをコピーしました",
    LocaleKey.settingDetectingPlatformIntegration: "デスクトップ連携の状態を確認しています...",
    LocaleKey.settingSupportStatusAvailable: "利用可能",
    LocaleKey.settingSupportStatusMissingDependency: "依存関係が不足",
    LocaleKey.settingSupportStatusInstalledButDisabled: "導入済みだが無効",
    LocaleKey.settingSupportStatusUnavailable: "このセッションでは利用不可",
    LocaleKey.settingSupportStatusUnknown: "状態不明",
    LocaleKey.settingSupportStatusChecking: "確認中",
    LocaleKey.settingGnomeMenuUpdated: "GNOME Files の右クリックメニューを更新しました",
    LocaleKey.settingGnomeMenuUnavailable:
        "GNOME Files 拡張が利用できません。先に nautilus-python をインストールしてください。",
    LocaleKey.settingGnomeMenuRestartHint:
        "GNOME Files 連携を更新しました。反映には「ファイル」アプリの再起動が必要な場合があります。",
    LocaleKey.settingWin11MenuNeedsIdentity:
        "Windows 11 メニューの登録に失敗しました。Vertree が完全にインストールされ、管理者権限を許可したか確認してください",
    LocaleKey.settingWin11IdentityRequired:
        "Windows 11 の新しいメニューは通常のインストーラー版でも直接登録できます。Explorer が更新されない場合だけ更新コマンドを実行してください。",
    LocaleKey.settingCopyRegisterCommand: "登録コマンドをコピー",
    LocaleKey.settingCopyRefreshCommand: "更新コマンドをコピー",
    LocaleKey.settingCopyConfigCommand: "設定コマンドをコピー",
    LocaleKey.settingCopyAssistCommand: "補助コマンドをコピー",
    LocaleKey.settingOpenUrlFailed: "%a を開けませんでした",
    LocaleKey.settingLocalHttpApiToggleFailed:
        "Local HTTP API の切り替えに失敗しました: %a",
    LocaleKey.settingOpenGithub: "GitHub リポジトリを見る",
    LocaleKey.settingNotifyAddBackup: "「このファイルバージョンをバックアップ」が右クリックメニューに追加されました",
    LocaleKey.settingNotifyRemoveBackup:
        "「このファイルバージョンをバックアップ」が右クリックメニューから削除されました",
    LocaleKey.settingNotifyAddMonitor: "「このファイルを監視」が右クリックメニューに追加されました",
    LocaleKey.settingNotifyRemoveMonitor: "「このファイルを監視」が右クリックメニューから削除されました",
    LocaleKey.settingNotifyAddShare: "「LAN ダウンロード共有」が右クリックメニューに追加されました",
    LocaleKey.settingNotifyRemoveShare: "「LAN ダウンロード共有」が右クリックメニューから削除されました",
    LocaleKey.settingNotifyAddView: "「バージョンツリーを表示」が右クリックメニューに追加されました",
    LocaleKey.settingNotifyRemoveView: "「バージョンツリーを表示」が右クリックメニューから削除されました",
    LocaleKey.settingNotifyEnableAutostart: "自動起動が有効になりました",
    LocaleKey.settingNotifyDisableAutostart: "自動起動が無効になりました",
    LocaleKey.settingNotifyAddExpress: "「このファイルを即時バックアップ」が右クリックメニューに追加されました",
    LocaleKey.settingNotifyRemoveExpress:
        "「このファイルを即時バックアップ」が右クリックメニューから削除されました",

    LocaleKey.vertreeTitle: "Vertreeバージョンツリー",
    LocaleKey.vertreeFileTreeTitle: "%a.%a ファイルバージョンツリー",
    LocaleKey.vertreeOverviewTitle: "バージョンツリー概要",
    LocaleKey.vertreeFocusVersion: "注目バージョン",
    LocaleKey.vertreeLatestVersion: "最新バージョン",
    LocaleKey.vertreeTotalNodes: "総ノード数",
    LocaleKey.vertreeTotalBranches: "分岐ノード数",
    LocaleKey.vertreeCanvasHint: "ドラッグで移動、ホイールで拡大縮小、ノードを右クリックで操作",

    LocaleKey.monitcardMonitorStatus: "%aの監視は%aされました",

    LocaleKey.monitcardBackupFolder: "バックアップフォルダ：%a",
    LocaleKey.monitcardOpenBackupFolder: "バックアップフォルダを開く",
    LocaleKey.monitcardDelete: "監視タスクを削除",
    LocaleKey.monitcardPause: "一時停止",

    LocaleKey.monitcardClean: "バックアップフォルダをクリーンアップ",
    LocaleKey.monitcardCleanSuccess: "バックアップフォルダ %a のクリーンアップに成功しました",
    LocaleKey.monitcardCleanFail: "バックアップフォルダ %a のクリーンアップに失敗しました",
    LocaleKey.monitcardCleanDialogTitle: "バックアップフォルダのクリーンアップ確認",
    LocaleKey.monitcardCleanDialogContent:
        "バックアップフォルダ %a 内のすべてのファイルをクリーンアップしますか？この操作は元に戻せません。",
    LocaleKey.monitcardCleanDialogCancel: "キャンセル",
    LocaleKey.monitcardCleanDialogConfirm: "確認",
    LocaleKey.monitcardStatusEnabled: "有効",
    LocaleKey.monitcardStatusDisabled: "無効",

    LocaleKey.filetreeInputLabelTitle: "ラベルを入力してください",
    LocaleKey.filetreeInputLabelHint: "ラベルを入力してください（任意）",
    LocaleKey.filetreeInputCancel: "キャンセル",
    LocaleKey.filetreeInputConfirm: "確認",
    LocaleKey.filetreeBackupBlockedHasChild:
        "このバージョンにはすでに直系の子があるため、バックアップできません",

    LocaleKey.fileleafNoLabel: "備考なし",
    LocaleKey.fileleafLastModified: "最終更新",
    LocaleKey.fileleafOpenTitle: "ファイル %a.%a を開きますか？",
    LocaleKey.fileleafOpenContent: "「%a.%a」バージョン %a を開こうとしています",
    LocaleKey.fileleafCancel: "キャンセル",
    LocaleKey.fileleafConfirm: "確認",
    LocaleKey.fileleafMenuBackup: "バックアップバージョン",
    LocaleKey.fileleafMenuBranch: "ブランチを作成",
    LocaleKey.fileleafMenuMonit: "変更を監視",
    LocaleKey.fileleafMenuProperty: "プロパティ",
    LocaleKey.fileleafMenuShare: "LAN で共有",
    LocaleKey.fileleafMenuPreview: "プレビュー",
    LocaleKey.previewOpenSystem: "既定のアプリで開く",
    LocaleKey.previewFailed: "プレビューを読み込めません。既定のアプリで開けます。",
    LocaleKey.previewBrowserHint:
        "Linux ではローカルブラウザーで表示します。このダイアログを閉じるとファイルの配信を終了します。",
    LocaleKey.previewOpenBrowser: "ブラウザーでプレビュー",
    LocaleKey.fileleafSharePreparing: "LAN 共有を準備しています...",
    LocaleKey.fileleafShareCreateFailed: "LAN 共有を作成できませんでした: %a",
    LocaleKey.fileleafShareReady: "%a の LAN ダウンロードができました。クリックして確認できます。",
    LocaleKey.fileleafShareDialogTitle: "%a の LAN 共有",
    LocaleKey.fileleafShareDialogHint:
        "QR コードを共有するか、短い共有リンクを送ってください。ブラウザは利用可能な LAN アドレスを自動的に試し、ダウンロードを開始します。",
    LocaleKey.fileleafShareExpiresAt: "有効期限",
    LocaleKey.fileleafShareLandingLink: "短い共有リンク",
    LocaleKey.fileleafShareCandidates: "LAN 直リンク候補",
    LocaleKey.fileleafShareBrowserHint:
        "ブラウザが共有ページで自動判定できない場合は、以下の LAN リンクを直接使ってください。",
    LocaleKey.fileleafShareCopiedLink: "リンクをコピーしました",
    LocaleKey.fileleafShareCopyLink: "リンクをコピー",
    LocaleKey.fileleafShareOpenLanding: "共有ページを開く",
    LocaleKey.fileleafShareOpenFailed: "共有ページを開けませんでした",
    LocaleKey.fileleafMonitTitle: "ファイル監視の確認",
    LocaleKey.fileleafMonitContent: "ファイル「%a.%a」の監視を開始しますか？",
    LocaleKey.fileleafNotifyFailed: "Vertreeの監視に失敗しました、",
    LocaleKey.fileleafNotifySuccess: "Vertreeがファイルの監視を開始しました",
    LocaleKey.fileleafNotifyHint: "クリックしてバックアップフォルダを開く",

    LocaleKey.fileleafPropertyTitle: "ファイルプロパティ",
    LocaleKey.fileleafPropertyFullname: "フルネーム：",
    LocaleKey.fileleafPropertyName: "名前：",
    LocaleKey.fileleafPropertyLabel: "ラベル：",
    LocaleKey.fileleafPropertyInputLabel: "ラベルを入力してください",
    LocaleKey.fileleafPropertyVersion: "バージョン：",
    LocaleKey.fileleafPropertyExt: "拡張子：",
    LocaleKey.fileleafPropertyPath: "パス：",
    LocaleKey.fileleafPropertySize: "ファイルサイズ：",
    LocaleKey.fileleafPropertyCreated: "作成日時：",
    LocaleKey.fileleafPropertyModified: "更新日時：",
    LocaleKey.fileleafPropertyClose: "閉じる",
    LocaleKey.fileleafBranchLabel: "ブランチ",
    LocaleKey.fileleafRevisionLabel: "バージョン",

    LocaleKey.trayToggleHide: "トレイに隠す",
    LocaleKey.trayToggleHideTooltip: "ウィンドウをトレイに隠します",
    LocaleKey.trayToggleShow: "メインウィンドウを表示",
    LocaleKey.trayToggleShowTooltip: "メインウィンドウを表示します",
    LocaleKey.trayBackup: "ファイルをバックアップ",
    LocaleKey.trayBackupTooltip: "バックアップするファイルを選択",
    LocaleKey.trayExpressBackup: "クイックバックアップ",
    LocaleKey.trayExpressBackupTooltip: "クイックバックアップするファイルを選択",
    LocaleKey.trayMonit: "ファイルを監視",
    LocaleKey.trayMonitTooltip: "監視対象に追加するファイルを選択",
    LocaleKey.trayShare: "LAN 共有",
    LocaleKey.trayShareTooltip: "LAN ダウンロードリンクを作るファイルを選択",
    LocaleKey.trayViewTree: "バージョンツリーを表示",
    LocaleKey.trayViewTreeTooltip: "バージョンツリーを確認するファイルを選択",
    LocaleKey.traySetting: "設定",
    LocaleKey.traySettingTooltip: "アプリ設定を開く",
    LocaleKey.trayExit: "終了",
    LocaleKey.trayExitTooltip: "アプリを終了",
  };
}
