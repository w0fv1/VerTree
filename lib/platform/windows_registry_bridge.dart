import 'dart:io';
import 'package:vertree/platform/windows_menu_model.dart';

import 'package:vertree/component/elevated_task.dart' deferred as elevated_task;
import 'package:vertree/component/ver_tree_registry_helper.dart'
    deferred as registry;
import 'package:vertree/utils/windows_package_identity.dart'
    deferred as package_identity;

class WindowsRegistryBridge {
  static bool _loaded = false;
  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    await elevated_task.loadLibrary();
    await registry.loadLibrary();
    await package_identity.loadLibrary();
    _loaded = true;
  }

  static Future<bool> tryHandleElevatedTask(List<String> args) async {
    if (!Platform.isWindows) return false;
    await elevated_task.loadLibrary();
    return elevated_task.ElevatedTaskRunner.tryHandleElevatedTask(args);
  }

  static Future<void> reAddContextMenu() async {
    if (!Platform.isWindows) return;
    await _ensureLoaded();
    registry.VerTreeRegistryService.reAddContextMenu();
  }

  static Future<bool> isActionEnabled(WindowsMenuAction action) async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.isActionEnabled(action);
  }

  static Future<bool> setActionEnabled(
    WindowsMenuAction action,
    bool enabled,
  ) async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.setActionEnabled(action, enabled);
  }

  static Future<bool> setLegacyMenuLayout(bool collapsed) async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.setLegacyMenuLayout(collapsed);
  }

  static Future<bool> checkBackupKeyExists() =>
      isActionEnabled(WindowsMenuAction.backup);
  static Future<bool> addBackupContextMenu() =>
      setActionEnabled(WindowsMenuAction.backup, true);
  static Future<bool> removeBackupContextMenu() =>
      setActionEnabled(WindowsMenuAction.backup, false);

  static Future<bool> checkExpressBackupKeyExists() =>
      isActionEnabled(WindowsMenuAction.expressBackup);
  static Future<bool> addExpressBackupContextMenu() =>
      setActionEnabled(WindowsMenuAction.expressBackup, true);
  static Future<bool> removeExpressBackupContextMenu() =>
      setActionEnabled(WindowsMenuAction.expressBackup, false);

  static Future<bool> checkMonitorKeyExists() =>
      isActionEnabled(WindowsMenuAction.monitor);
  static Future<bool> addMonitorContextMenu() =>
      setActionEnabled(WindowsMenuAction.monitor, true);
  static Future<bool> removeMonitorContextMenu() =>
      setActionEnabled(WindowsMenuAction.monitor, false);

  static Future<bool> checkShareKeyExists() =>
      isActionEnabled(WindowsMenuAction.share);
  static Future<bool> addShareContextMenu() =>
      setActionEnabled(WindowsMenuAction.share, true);
  static Future<bool> removeShareContextMenu() =>
      setActionEnabled(WindowsMenuAction.share, false);

  static Future<bool> checkViewTreeKeyExists() =>
      isActionEnabled(WindowsMenuAction.viewTree);
  static Future<bool> addViewTreeContextMenu() =>
      setActionEnabled(WindowsMenuAction.viewTree, true);
  static Future<bool> removeViewTreeContextMenu() =>
      setActionEnabled(WindowsMenuAction.viewTree, false);

  static Future<bool> checkPreviewKeyExists() =>
      isActionEnabled(WindowsMenuAction.preview);
  static Future<bool> addPreviewContextMenu() =>
      setActionEnabled(WindowsMenuAction.preview, true);
  static Future<bool> removePreviewContextMenu() =>
      setActionEnabled(WindowsMenuAction.preview, false);

  static Future<bool> enableAutoStart() async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.enableAutoStart();
  }

  static Future<bool> disableAutoStart() async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.disableAutoStart();
  }

  static Future<bool> isAutoStartEnabled() async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.isAutoStartEnabled();
  }

  static Future<bool> applyLegacyMenus(bool enabled) async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.applyLegacyMenus(enabled);
  }

  static Future<bool> applyLegacyMenusWithLayout(
    bool enabled, {
    required bool collapsed,
  }) async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.applyLegacyMenusWithLayout(
      enabled,
      collapsed: collapsed,
    );
  }

  static Future<bool> checkLegacyMenuRootExists() async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.checkLegacyMenuRootExists();
  }

  static Future<bool> migrateLegacyMenuLayoutConfig() async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.migrateLegacyMenuLayoutConfig();
  }

  static Future<bool> applyInitialSetup() async {
    if (!Platform.isWindows) return true;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.applyInitialSetup();
  }

  static Future<bool> addWin11ContextMenuHandler() async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.addWin11ContextMenuHandler();
  }

  static Future<bool> removeWin11ContextMenuHandler() async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.removeWin11ContextMenuHandler();
  }

  static Future<bool> checkWin11ContextMenuHandler() async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return registry.VerTreeRegistryService.checkWin11ContextMenuHandler();
  }

  static Future<bool> isWin11PackagedOrRegistered() async {
    if (!Platform.isWindows) return false;
    await _ensureLoaded();
    return package_identity.WindowsPackageIdentity.isPackagedOrRegistered();
  }
}
