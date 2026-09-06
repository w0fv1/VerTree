import 'dart:io';

import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:vertree/platform/linux_gnome_integration.dart';
import 'package:vertree/platform/windows_registry_bridge.dart';

class PlatformIntegration {
  static const MethodChannel _autoStartChannel = MethodChannel(
    'vertree/auto_start',
  );
  static const MethodChannel _dockChannel = MethodChannel('vertree/dock');
  static bool get isWindows => Platform.isWindows;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isLinux => Platform.isLinux;
  static bool get isLinuxGnome =>
      isLinux && LinuxGnomeIntegration.isGnomeSession;
  static bool? _linuxGnomeTrayAvailable;

  static bool get supportsContextMenus => isWindows || isLinuxGnome;
  static bool get supportsWin11Menu => isWindows;
  static bool get supportsAutoStart => isWindows || isMacOS || isLinux;
  static bool get defaultLaunchToTray => !isLinux;
  static bool get supportsTrayOnlyBackgroundMode =>
      !isLinuxGnome || (_linuxGnomeTrayAvailable ?? false);

  static Future<void> init() async {
    if (isLinux) {
      launchAtStartup.setup(
        appName: 'vertree',
        appPath: Platform.resolvedExecutable,
      );
    }
    await refreshLinuxCapabilityCache();
  }

  static Future<void> refreshLinuxCapabilityCache() async {
    if (!isLinuxGnome) {
      _linuxGnomeTrayAvailable = null;
      return;
    }
    _linuxGnomeTrayAvailable = await LinuxGnomeIntegration.isTrayAvailable();
  }

  static Future<void> reAddContextMenu() async {
    if (!isWindows) return;
    await WindowsRegistryBridge.reAddContextMenu();
  }

  static Future<bool> checkBackupKeyExists() async {
    if (isWindows) {
      return WindowsRegistryBridge.checkBackupKeyExists();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.hasAction(
        LinuxGnomeIntegration.actionBackup,
      );
    }
    return false;
  }

  static Future<bool> checkPreviewKeyExists() =>
      WindowsRegistryBridge.checkPreviewKeyExists();
  static Future<bool> addPreviewContextMenu() =>
      WindowsRegistryBridge.addPreviewContextMenu();
  static Future<bool> removePreviewContextMenu() =>
      WindowsRegistryBridge.removePreviewContextMenu();
  static Future<bool> setLegacyMenuLayout(bool collapsed) =>
      WindowsRegistryBridge.setLegacyMenuLayout(collapsed);

  static Future<bool> checkExpressBackupKeyExists() async {
    if (isWindows) {
      return WindowsRegistryBridge.checkExpressBackupKeyExists();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.hasAction(
        LinuxGnomeIntegration.actionExpressBackup,
      );
    }
    return false;
  }

  static Future<bool> checkMonitorKeyExists() async {
    if (isWindows) {
      return WindowsRegistryBridge.checkMonitorKeyExists();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.hasAction(
        LinuxGnomeIntegration.actionMonitor,
      );
    }
    return false;
  }

  static Future<bool> checkShareKeyExists() async {
    if (isWindows) {
      return WindowsRegistryBridge.checkShareKeyExists();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.hasAction(LinuxGnomeIntegration.actionShare);
    }
    return false;
  }

  static Future<bool> checkViewTreeKeyExists() async {
    if (isWindows) {
      return WindowsRegistryBridge.checkViewTreeKeyExists();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.hasAction(
        LinuxGnomeIntegration.actionViewTree,
      );
    }
    return false;
  }

  static Future<bool> addBackupContextMenu() async {
    if (isWindows) {
      return WindowsRegistryBridge.addBackupContextMenu();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.addAction(
        LinuxGnomeIntegration.actionBackup,
      );
    }
    return false;
  }

  static Future<bool> removeBackupContextMenu() async {
    if (isWindows) {
      return WindowsRegistryBridge.removeBackupContextMenu();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.removeAction(
        LinuxGnomeIntegration.actionBackup,
      );
    }
    return false;
  }

  static Future<bool> addExpressBackupContextMenu() async {
    if (isWindows) {
      return WindowsRegistryBridge.addExpressBackupContextMenu();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.addAction(
        LinuxGnomeIntegration.actionExpressBackup,
      );
    }
    return false;
  }

  static Future<bool> removeExpressBackupContextMenu() async {
    if (isWindows) {
      return WindowsRegistryBridge.removeExpressBackupContextMenu();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.removeAction(
        LinuxGnomeIntegration.actionExpressBackup,
      );
    }
    return false;
  }

  static Future<bool> addMonitorContextMenu() async {
    if (isWindows) {
      return WindowsRegistryBridge.addMonitorContextMenu();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.addAction(
        LinuxGnomeIntegration.actionMonitor,
      );
    }
    return false;
  }

  static Future<bool> removeMonitorContextMenu() async {
    if (isWindows) {
      return WindowsRegistryBridge.removeMonitorContextMenu();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.removeAction(
        LinuxGnomeIntegration.actionMonitor,
      );
    }
    return false;
  }

  static Future<bool> addShareContextMenu() async {
    if (isWindows) {
      return WindowsRegistryBridge.addShareContextMenu();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.addAction(LinuxGnomeIntegration.actionShare);
    }
    return false;
  }

  static Future<bool> removeShareContextMenu() async {
    if (isWindows) {
      return WindowsRegistryBridge.removeShareContextMenu();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.removeAction(
        LinuxGnomeIntegration.actionShare,
      );
    }
    return false;
  }

  static Future<bool> addViewTreeContextMenu() async {
    if (isWindows) {
      return WindowsRegistryBridge.addViewTreeContextMenu();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.addAction(
        LinuxGnomeIntegration.actionViewTree,
      );
    }
    return false;
  }

  static Future<bool> removeViewTreeContextMenu() async {
    if (isWindows) {
      return WindowsRegistryBridge.removeViewTreeContextMenu();
    }
    if (isLinux) {
      return LinuxGnomeIntegration.removeAction(
        LinuxGnomeIntegration.actionViewTree,
      );
    }
    return false;
  }

  static Future<bool> applyLegacyMenus(
    bool enabled, {
    bool collapsed = false,
  }) async {
    if (isWindows) {
      return WindowsRegistryBridge.applyLegacyMenusWithLayout(
        enabled,
        collapsed: collapsed,
      );
    }
    if (isLinux) {
      return LinuxGnomeIntegration.applyAll(enabled);
    }
    return false;
  }

  static Future<bool> isAutoStartEnabled() async {
    if (isWindows) {
      return WindowsRegistryBridge.isAutoStartEnabled();
    }
    if (isMacOS) {
      return _invokeMacAutoStart('isEnabled');
    }
    if (isLinux) {
      return launchAtStartup.isEnabled();
    }
    return false;
  }

  static Future<bool> enableAutoStart() async {
    if (isWindows) {
      return WindowsRegistryBridge.enableAutoStart();
    }
    if (isMacOS) {
      return _invokeMacAutoStart('enable');
    }
    if (isLinux) {
      return launchAtStartup.enable();
    }
    return false;
  }

  static Future<bool> disableAutoStart() async {
    if (isWindows) {
      return WindowsRegistryBridge.disableAutoStart();
    }
    if (isMacOS) {
      return _invokeMacAutoStart('disable');
    }
    if (isLinux) {
      return launchAtStartup.disable();
    }
    return false;
  }

  static Future<bool> _invokeMacAutoStart(String method) async {
    try {
      final value = await _autoStartChannel.invokeMethod<bool>(method);
      return value ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> refreshMacOSDockIcon() async {
    if (!isMacOS) return;
    try {
      await _dockChannel.invokeMethod<bool>('refresh');
    } catch (_) {}
  }

  static Future<bool> applyInitialSetup() async {
    if (isWindows) {
      return WindowsRegistryBridge.applyInitialSetup();
    }
    var success = true;

    if (supportsAutoStart) {
      success = await enableAutoStart() && success;
    }

    if (isLinux) {
      final gnomeSupported = await LinuxGnomeIntegration.isSupported();
      if (gnomeSupported) {
        success = await LinuxGnomeIntegration.applyAll(true) && success;
      }
      return success;
    }

    if (isMacOS) {
      return success;
    }

    return false;
  }

  static Future<bool> isWin11PackagedOrRegistered() async {
    if (!isWindows) return false;
    return WindowsRegistryBridge.isWin11PackagedOrRegistered();
  }

  static Future<bool> addWin11ContextMenuHandler() async {
    if (!isWindows) return false;
    return WindowsRegistryBridge.addWin11ContextMenuHandler();
  }

  static Future<bool> removeWin11ContextMenuHandler() async {
    if (!isWindows) return false;
    return WindowsRegistryBridge.removeWin11ContextMenuHandler();
  }

  static Future<bool> checkWin11ContextMenuHandler() async {
    if (!isWindows) return false;
    return WindowsRegistryBridge.checkWin11ContextMenuHandler();
  }

  static Future<bool> checkLegacyMenuRootExists() async {
    if (!isWindows) return false;
    return WindowsRegistryBridge.checkLegacyMenuRootExists();
  }

  static Future<bool> migrateLegacyMenuLayoutConfig() async {
    if (!isWindows) return false;
    return WindowsRegistryBridge.migrateLegacyMenuLayoutConfig();
  }
}
