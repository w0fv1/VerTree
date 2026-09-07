import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:tray_manager/tray_manager.dart' as lean_tray;
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/component/themed_assets.dart';
import 'package:vertree/platform/platform_integration.dart';
import 'package:vertree/view/page/brand_page.dart';
import 'package:vertree/view/page/setting_page.dart';
import 'package:window_manager/window_manager.dart';

class TrayManager with lean_tray.TrayListener {
  TrayManager({
    required this.appLocale,
    required this.onLog,
    required this.showMainWindow,
    required this.toggleMainWindowVisibility,
    required this.quitApplication,
    required this.backup,
    required this.expressBackup,
    required this.monit,
    required this.share,
    required this.viewtree,
  });
  final AppLocale appLocale;
  final void Function(String) onLog;
  final Future<void> Function({Widget? page, bool animate}) showMainWindow;
  final Future<void> Function({Widget? page}) toggleMainWindowVisibility;
  final Future<void> Function() quitApplication;
  final FutureOr<void> Function(String) backup,
      expressBackup,
      monit,
      share,
      viewtree;

  bool _initialized = false;
  bool _eventsBound = false;
  bool _linuxEventsBound = false;
  Timer? _refreshTimer;
  String? _iconPath;
  nativeapi.Image? _iconImage;
  nativeapi.TrayIcon? _trayIcon;
  nativeapi.Menu? _menu;
  List<nativeapi.MenuItem> _menuItems = [];
  nativeapi.MenuItem? _toggleWindowMenuItem;
  String? _menuLocaleName;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _rebuildQueued = false;

  ValueNotifier<bool> shouldForegroundOnContextMenu = ValueNotifier(false);

  Future<void> init() async {
    if (Platform.isLinux &&
        !PlatformIntegration.supportsTrayOnlyBackgroundMode) {
      _refreshTimer?.cancel();
      return;
    }
    if (Platform.isLinux) {
      if (!_linuxEventsBound) {
        lean_tray.trayManager.addListener(this);
        _linuxEventsBound = true;
      }
      _initialized = true;
      await initTray();
      _refreshTimer?.cancel();
      return;
    }
    if (!nativeapi.TrayManager.instance.isSupported) {
      return;
    }
    _trayIcon ??= nativeapi.TrayIcon();
    if (!_eventsBound) {
      _bindTrayEvents(_trayIcon!);
      _eventsBound = true;
    }
    _initialized = true;
    await initTray();
    _refreshTimer?.cancel();
    if (!Platform.isLinux) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(refreshTray());
      });
    }
  }

  void _bindTrayEvents(nativeapi.TrayIcon trayIcon) {
    trayIcon.contextMenuTrigger = nativeapi.ContextMenuTrigger.none;
    trayIcon.on<nativeapi.TrayIconClickedEvent>((_) {
      unawaited(showMainWindow(page: BrandPage()));
    });
    trayIcon.on<nativeapi.TrayIconRightClickedEvent>((_) {
      trayIcon.openContextMenu();
    });
    trayIcon.on<nativeapi.TrayIconDoubleClickedEvent>((_) {
      unawaited(showMainWindow(page: BrandPage()));
    });
  }

  Future<void> initTray() async {
    if (Platform.isLinux &&
        !PlatformIntegration.supportsTrayOnlyBackgroundMode) {
      return;
    }
    _iconPath = Platform.isWindows
        ? 'assets/img/logo/logo.ico'
        : 'assets/img/logo/logo.png';
    if (Platform.isLinux) {
      await refreshTray();
      return;
    }
    _iconImage = _iconPath == null
        ? null
        : nativeapi.Image.fromAsset(_iconPath!);
    await refreshTray();
  }

  Future<bool> _isWindowVisible() async {
    try {
      final visible = await windowManager.isVisible();
      final minimized = await windowManager.isMinimized();
      return visible && !minimized;
    } catch (_) {
      return false;
    }
  }

  nativeapi.MenuItem _buildMenuItem({
    required String key,
    required String label,
    String? toolTip,
    String? iconAsset,
    required Future<void> Function() action,
    nativeapi.MenuItemType type = nativeapi.MenuItemType.normal,
  }) {
    final item = nativeapi.MenuItem(label, type);
    item.tooltip = toolTip ?? '';
    if (iconAsset != null) {
      item.icon = nativeapi.Image.fromAsset(iconAsset);
    }
    item.on<nativeapi.MenuItemClickedEvent>((_) {
      unawaited(action());
    });
    return item;
  }

  lean_tray.MenuItem _buildLinuxMenuItem({
    required String key,
    required String label,
    String? toolTip,
    String? iconAsset,
    required Future<void> Function() action,
    bool isSeparator = false,
  }) {
    if (isSeparator) {
      return lean_tray.MenuItem.separator();
    }
    return lean_tray.MenuItem(
      key: key,
      label: label,
      toolTip: toolTip,
      icon: iconAsset,
      onClick: (_) {
        unawaited(action());
      },
    );
  }

  Future<(nativeapi.Menu, List<nativeapi.MenuItem>)> _buildMenu() async {
    final menu = nativeapi.Menu();
    final items = <nativeapi.MenuItem>[];
    final isWindowVisible = await _isWindowVisible();

    final toggleWindowMenuItem = _buildMenuItem(
      key: 'toggleWindow',
      label: isWindowVisible
          ? appLocale.getText(LocaleKey.trayToggleHide)
          : appLocale.getText(LocaleKey.trayToggleShow),
      toolTip: isWindowVisible
          ? appLocale.getText(LocaleKey.trayToggleHideTooltip)
          : appLocale.getText(LocaleKey.trayToggleShowTooltip),
      action: () => toggleMainWindowVisibility(page: BrandPage()),
    );
    _toggleWindowMenuItem = toggleWindowMenuItem;
    items.add(toggleWindowMenuItem);
    items.add(
      _buildMenuItem(
        key: 'separator-1',
        label: '',
        action: () async {},
        type: nativeapi.MenuItemType.separator,
      ),
    );

    items.add(
      _buildMenuItem(
        key: 'backup',
        label: appLocale.getText(LocaleKey.trayBackup),
        toolTip: appLocale.getText(LocaleKey.trayBackupTooltip),
        iconAsset: 'assets/img/icon/save.png',
        action: () => _pickFileAndRun(backup, bringToFront: true),
      ),
    );
    items.add(
      _buildMenuItem(
        key: 'expressBackup',
        label: appLocale.getText(LocaleKey.trayExpressBackup),
        toolTip: appLocale.getText(LocaleKey.trayExpressBackupTooltip),
        iconAsset: 'assets/img/icon/express-save.png',
        action: () => _pickFileAndRun(expressBackup),
      ),
    );
    items.add(
      _buildMenuItem(
        key: 'monit',
        label: appLocale.getText(LocaleKey.trayMonit),
        toolTip: appLocale.getText(LocaleKey.trayMonitTooltip),
        iconAsset: 'assets/img/icon/monit.png',
        action: () => _pickFileAndRun(monit),
      ),
    );
    items.add(
      _buildMenuItem(
        key: 'share',
        label: appLocale.getText(LocaleKey.trayShare),
        toolTip: appLocale.getText(LocaleKey.trayShareTooltip),
        iconAsset: Platform.isWindows ? kShareActionIco : kShareActionPng,
        action: () => _pickFileAndRun(share),
      ),
    );
    items.add(
      _buildMenuItem(
        key: 'viewtree',
        label: appLocale.getText(LocaleKey.trayViewTree),
        toolTip: appLocale.getText(LocaleKey.trayViewTreeTooltip),
        iconAsset: 'assets/img/icon/save.png',
        action: () => _pickFileAndRun(viewtree),
      ),
    );
    items.add(
      _buildMenuItem(
        key: 'separator-2',
        label: '',
        action: () async {},
        type: nativeapi.MenuItemType.separator,
      ),
    );
    items.add(
      _buildMenuItem(
        key: 'setting',
        label: appLocale.getText(LocaleKey.traySetting),
        toolTip: appLocale.getText(LocaleKey.traySettingTooltip),
        iconAsset: Platform.isWindows
            ? 'assets/img/icon/setting.ico'
            : 'assets/img/icon/setting.png',
        action: () => showMainWindow(page: SettingPage(), animate: false),
      ),
    );
    items.add(
      _buildMenuItem(
        key: 'exit',
        label: appLocale.getText(LocaleKey.trayExit),
        toolTip: appLocale.getText(LocaleKey.trayExitTooltip),
        iconAsset: Platform.isWindows
            ? 'assets/img/icon/exit.ico'
            : 'assets/img/icon/exit.png',
        action: quitApplication,
      ),
    );

    for (final item in items) {
      menu.addItem(item);
    }

    return (menu, items);
  }

  void _invalidateMenuCache() {
    _menu = null;
    _menuItems = [];
    _toggleWindowMenuItem = null;
    _menuLocaleName = null;
  }

  Future<void> _ensureMenuBuilt() async {
    if (_menu != null && _menuItems.isNotEmpty) {
      return;
    }
    final (menu, items) = await _buildMenu();
    _menu = menu;
    _menuItems = items;
    _menuLocaleName = appLocale.lang.name;
  }

  Future<void> _updateMenuState() async {
    final toggleWindowMenuItem = _toggleWindowMenuItem;
    if (toggleWindowMenuItem == null) {
      return;
    }
    final isWindowVisible = await _isWindowVisible();
    toggleWindowMenuItem.label = isWindowVisible
        ? appLocale.getText(LocaleKey.trayToggleHide)
        : appLocale.getText(LocaleKey.trayToggleShow);
    toggleWindowMenuItem.tooltip = isWindowVisible
        ? appLocale.getText(LocaleKey.trayToggleHideTooltip)
        : appLocale.getText(LocaleKey.trayToggleShowTooltip);
  }

  Future<lean_tray.Menu> _buildLinuxMenu() async {
    final isWindowVisible = await _isWindowVisible();
    return lean_tray.Menu(
      items: [
        _buildLinuxMenuItem(
          key: 'toggleWindow',
          label: isWindowVisible
              ? appLocale.getText(LocaleKey.trayToggleHide)
              : appLocale.getText(LocaleKey.trayToggleShow),
          toolTip: isWindowVisible
              ? appLocale.getText(LocaleKey.trayToggleHideTooltip)
              : appLocale.getText(LocaleKey.trayToggleShowTooltip),
          action: () => toggleMainWindowVisibility(page: BrandPage()),
        ),
        _buildLinuxMenuItem(
          key: 'separator-1',
          label: '',
          action: () async {},
          isSeparator: true,
        ),
        _buildLinuxMenuItem(
          key: 'backup',
          label: appLocale.getText(LocaleKey.trayBackup),
          toolTip: appLocale.getText(LocaleKey.trayBackupTooltip),
          iconAsset: 'assets/img/icon/save.png',
          action: () => _pickFileAndRun(backup, bringToFront: true),
        ),
        _buildLinuxMenuItem(
          key: 'expressBackup',
          label: appLocale.getText(LocaleKey.trayExpressBackup),
          toolTip: appLocale.getText(LocaleKey.trayExpressBackupTooltip),
          iconAsset: 'assets/img/icon/express-save.png',
          action: () => _pickFileAndRun(expressBackup),
        ),
        _buildLinuxMenuItem(
          key: 'monit',
          label: appLocale.getText(LocaleKey.trayMonit),
          toolTip: appLocale.getText(LocaleKey.trayMonitTooltip),
          iconAsset: 'assets/img/icon/monit.png',
          action: () => _pickFileAndRun(monit),
        ),
        _buildLinuxMenuItem(
          key: 'share',
          label: appLocale.getText(LocaleKey.trayShare),
          toolTip: appLocale.getText(LocaleKey.trayShareTooltip),
          iconAsset: kShareActionPng,
          action: () => _pickFileAndRun(share),
        ),
        _buildLinuxMenuItem(
          key: 'viewtree',
          label: appLocale.getText(LocaleKey.trayViewTree),
          toolTip: appLocale.getText(LocaleKey.trayViewTreeTooltip),
          iconAsset: 'assets/img/icon/save.png',
          action: () => _pickFileAndRun(viewtree),
        ),
        _buildLinuxMenuItem(
          key: 'separator-2',
          label: '',
          action: () async {},
          isSeparator: true,
        ),
        _buildLinuxMenuItem(
          key: 'setting',
          label: appLocale.getText(LocaleKey.traySetting),
          toolTip: appLocale.getText(LocaleKey.traySettingTooltip),
          iconAsset: 'assets/img/icon/setting.png',
          action: () => showMainWindow(page: SettingPage(), animate: false),
        ),
        _buildLinuxMenuItem(
          key: 'exit',
          label: appLocale.getText(LocaleKey.trayExit),
          toolTip: appLocale.getText(LocaleKey.trayExitTooltip),
          iconAsset: 'assets/img/icon/exit.png',
          action: quitApplication,
        ),
      ],
    );
  }

  Future<void> _ensureWindowVisible() async {
    await showMainWindow(animate: false);
  }

  Future<void> _pickFileAndRun(
    FutureOr<void> Function(String path) action, {
    bool bringToFront = false,
  }) async {
    if (bringToFront) {
      await _ensureWindowVisible();
    }
    final result = await FilePicker.platform.pickFiles();
    final filePath = result?.files.single.path;
    if (filePath == null || filePath.isEmpty) {
      return;
    }
    await action(filePath);
  }

  Future<void> refreshTray({bool forceRebuild = false}) async {
    if (!_initialized ||
        (Platform.isLinux &&
            !PlatformIntegration.supportsTrayOnlyBackgroundMode)) {
      return;
    }
    final localeChanged =
        _menuLocaleName != null && _menuLocaleName != appLocale.lang.name;
    if (forceRebuild || localeChanged) {
      _invalidateMenuCache();
    }
    if (Platform.isLinux) {
      if (_iconPath == null) {
        return;
      }
      try {
        final menu = await _buildLinuxMenu();
        await lean_tray.trayManager.setIcon(_iconPath!);
        await lean_tray.trayManager.setContextMenu(menu);
      } catch (_) {}
      return;
    }
    final trayIcon = _trayIcon;
    if (trayIcon == null) {
      return;
    }
    if (_refreshInFlight) {
      _refreshQueued = true;
      _rebuildQueued = _rebuildQueued || forceRebuild || localeChanged;
      return;
    }
    _refreshInFlight = true;
    try {
      await _ensureMenuBuilt();
      await _updateMenuState();
      if (_iconImage != null) {
        trayIcon.icon = _iconImage;
      }
      trayIcon.tooltip = 'Vertree';
      if (Platform.isLinux) {
        trayIcon.title = 'Vertree';
      }
      final menu = _menu;
      if (menu != null) {
        trayIcon.contextMenu = menu;
      }
      trayIcon.isVisible = true;
    } catch (_) {
    } finally {
      _refreshInFlight = false;
      if (_refreshQueued) {
        final rebuildQueued = _rebuildQueued;
        _refreshQueued = false;
        _rebuildQueued = false;
        unawaited(refreshTray(forceRebuild: rebuildQueued));
      }
    }
  }

  Future<void> hideForQuit() async {
    _initialized = false;
    _refreshTimer?.cancel();
    _refreshQueued = false;
    _rebuildQueued = false;
    if (Platform.isLinux) {
      await lean_tray.trayManager.destroy();
    } else {
      _trayIcon?.isVisible = false;
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showMainWindow(page: BrandPage(), animate: false));
  }

  @override
  void onTrayIconRightMouseDown() {}
}
