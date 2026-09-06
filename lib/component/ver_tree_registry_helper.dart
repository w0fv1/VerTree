import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:vertree/component/app_launch_args.dart';
import 'package:vertree/component/elevated_task.dart';
import 'package:vertree/component/file_utils.dart';
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/main.dart';
import 'package:vertree/platform/windows_menu_model.dart';
import 'package:vertree/utils/windows_package_identity.dart';
import 'package:vertree/utils/windows_registry_util.dart';
import 'package:vertree/utils/windows_shell_notify.dart';

class VerTreeRegistryService {
  static const legacyMenuCollapsedConfigKey = 'legacyMenuCollapsed';
  static const _selectionKey = 'windowsLegacyMenuActions';
  static const appName = 'VerTree';
  static const runRegistryPath =
      r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const win11HandlerName = 'Vertree';
  static const win11HandlerClsid = '{BFD9F3B4-3C8C-4B1C-8E57-1F4BA6A96F3E}';
  static String get _autoStartCommand => buildWindowsLaunchCommand(
    Platform.resolvedExecutable,
    arguments: const [startupLaunchArg],
  );

  static Set<WindowsMenuAction> _selection() {
    final saved = configer.toJson()[_selectionKey];
    if (saved is List) {
      return WindowsMenuAction.values
          .where((action) => saved.contains(action.name))
          .toSet();
    }
    return WindowsMenuPlan.migrateSelection(
      WindowsMenuAction.values.where(
        (action) =>
            _registered(action.keyName) ||
            (action.legacyKeyName != null &&
                _registered(action.legacyKeyName!)),
      ),
    );
  }

  static bool _registered(String key) =>
      RegistryHelper.checkRegistryMenuExistsByKey(key) ||
      RegistryHelper.checkRegistryMenuExistsByKeyAtPath(
        '${RegistryHelper.currentUserClassesShellPath}\\${WindowsMenuPlan.rootKey}\\shell',
        key,
      ) ||
      RegistryHelper.checkMachineRegistryMenuExistsByKey(key) ||
      RegistryHelper.checkMachineRegistryMenuExistsByKeyAtPath(
        '${RegistryHelper.allUsersClassesShellPath}\\${WindowsMenuPlan.rootKey}\\shell',
        key,
      );

  static bool checkLegacyMenuRootExists() =>
      RegistryHelper.checkRegistryMenuExistsByKey(WindowsMenuPlan.rootKey) ||
      RegistryHelper.checkMachineRegistryMenuExistsByKey(
        WindowsMenuPlan.rootKey,
      );

  static bool get _collapsed =>
      configer.toJson()[legacyMenuCollapsedConfigKey] as bool? ??
      checkLegacyMenuRootExists();

  static bool isActionEnabled(WindowsMenuAction action) =>
      _selection().contains(action);

  static bool setActionEnabled(WindowsMenuAction action, bool enabled) {
    final selected = _selection();
    if (enabled) {
      selected.add(action);
    } else {
      selected.remove(action);
    }
    return _apply(selected, collapsed: _collapsed);
  }

  static bool applyLegacyMenus(bool enabled) =>
      applyLegacyMenusWithLayout(enabled, collapsed: _collapsed);

  static bool applyLegacyMenusWithLayout(
    bool enabled, {
    required bool collapsed,
  }) => _apply(
    enabled ? WindowsMenuAction.values.toSet() : {},
    collapsed: collapsed,
  );

  static bool setLegacyMenuLayout(bool collapsed) =>
      _apply(_selection(), collapsed: collapsed);

  static bool migrateLegacyMenuLayoutConfig() {
    if (!configer.toJson().containsKey(legacyMenuCollapsedConfigKey)) {
      configer.set(legacyMenuCollapsedConfigKey, checkLegacyMenuRootExists());
    }
    return true;
  }

  static void reAddContextMenu() {
    if (!_apply(_selection(), collapsed: _collapsed, cleanMachine: false)) {
      logger.error('同步右键菜单失败');
    }
  }

  static String _title(WindowsMenuAction action) => appLocale.getText(
    switch (action) {
      WindowsMenuAction.preview => LocaleKey.registryPreviewKeyName,
      WindowsMenuAction.backup => LocaleKey.registryBackupKeyName,
      WindowsMenuAction.expressBackup => LocaleKey.registryExpressBackupKeyName,
      WindowsMenuAction.monitor => LocaleKey.registryMonitorKeyName,
      WindowsMenuAction.share => LocaleKey.registryShareKeyName,
      WindowsMenuAction.viewTree => LocaleKey.registryViewTreeKeyName,
    },
  );

  static bool _apply(
    Set<WindowsMenuAction> selected, {
    required bool collapsed,
    bool cleanMachine = true,
  }) {
    final plan = WindowsMenuPlan(selected, collapsed: collapsed);
    final root = RegistryHelper.currentUserClassesShellPath;
    final success = plan.apply(
      write: (entry) {
        final parts = entry.key.split('\\');
        final keyName = parts.removeLast();
        final action = entry.action;
        return RegistryHelper.addContextMenuOptionAtPath(
          [root, ...parts].join('\\'),
          keyName,
          action == null ? 'Vertree' : _title(action),
          command: action == null
              ? null
              : '"${Platform.resolvedExecutable}" ${action.verb} "%1"',
          iconPath: path.joinAll([
            FileUtils.appDirPath(),
            'data',
            'flutter_assets',
            'assets',
            'img',
            ...(action?.icon ?? 'logo/logo.ico').split('/'),
          ]),
          isSubmenu: entry.isSubmenu,
        );
      },
      remove: (key) {
        final parts = key.split('\\');
        final keyName = parts.removeLast();
        return RegistryHelper.removeContextMenuOptionByKeyAtPath(
          [root, ...parts].join('\\'),
          keyName,
        );
      },
    );
    if (!success) return false;
    if (cleanMachine && !_cleanMachineMenus()) return false;
    configer.set(_selectionKey, selected.map((action) => action.name).toList());
    configer.set(legacyMenuCollapsedConfigKey, collapsed);
    WindowsShellNotify.associationsChanged();
    return true;
  }

  static bool _cleanMachineMenus() {
    final keys = WindowsMenuPlan.topLevelKeys
        .where(RegistryHelper.checkMachineRegistryMenuExistsByKey)
        .toList();
    if (keys.isEmpty) return true;
    return ElevatedTaskRunner.runTaskSync(
      ElevatedTaskRunner.opRemoveLegacyMenus,
      payload: {'keys': keys, 'hive': 'machine'},
    );
  }

  static bool applyInitialSetup() {
    final menus = applyLegacyMenusWithLayout(true, collapsed: _collapsed);
    final autoStart = enableAutoStart();
    return menus && autoStart;
  }

  static bool addWin11ContextMenuHandler({bool allowElevation = true}) {
    if (RegistryHelper.checkWin11ContextMenuHandler(
      win11HandlerName,
      win11HandlerClsid,
    )) {
      final cleaned = RegistryHelper.removeWin11ContextMenuHandler(
        win11HandlerName,
        win11HandlerClsid,
      );
      if (!_retryWithElevation(
        actionName: '清理旧 Win11 菜单注册',
        success: cleaned,
        allowElevation: allowElevation,
        operation: ElevatedTaskRunner.opRemoveWin11Menu,
        payload: {'handlerName': win11HandlerName, 'clsid': win11HandlerClsid},
      )) {
        return false;
      }
    }
    if (!WindowsPackageIdentity.isPackagedOrRegistered() &&
        !_runWin11PackagingScript(
          'install_sparse_package.ps1',
          arguments: ['-ExternalLocation', FileUtils.appDirPath(), '-Force'],
        )) {
      return false;
    }
    configer.set('win11MenuEnabled', true);
    WindowsShellNotify.associationsChanged();
    return true;
  }

  static bool removeWin11ContextMenuHandler({bool allowElevation = true}) {
    // Package identity is managed by the installer; the shell extension reads this flag.
    configer.set('win11MenuEnabled', false);
    WindowsShellNotify.associationsChanged();
    return true;
  }

  static bool checkWin11ContextMenuHandler() =>
      WindowsPackageIdentity.isPackagedOrRegistered();
  static String _win11PackagingDir() =>
      path.join(FileUtils.appDirPath(), 'win11_packaging');
  static bool _retryWithElevation({
    required String actionName,
    required bool success,
    required bool allowElevation,
    required String operation,
    Map<String, dynamic>? payload,
  }) {
    if (success || !allowElevation) {
      return success;
    }

    logger.info('$actionName 普通权限失败，尝试请求管理员权限...');
    final elevatedSuccess = ElevatedTaskRunner.runTaskSync(
      operation,
      payload: payload,
    );
    if (elevatedSuccess) {
      logger.info('$actionName 提权执行成功');
    } else {
      logger.error(
        '$actionName 提权执行失败: ${ElevatedTaskRunner.lastError ?? "unknown error"}',
      );
    }
    return elevatedSuccess;
  }

  static bool enableAutoStart({bool allowElevation = true}) {
    bool success = RegistryHelper.enableAutoStart(
      runRegistryPath,
      appName,
      _autoStartCommand,
    );
    success = _retryWithElevation(
      actionName: '启用开机自启',
      success: success,
      allowElevation: allowElevation,
      operation: ElevatedTaskRunner.opEnableAutoStart,
      payload: {
        'runRegistryPath': runRegistryPath,
        'appName': appName,
        'appCommand': _autoStartCommand,
      },
    );
    return success;
  }

  static bool disableAutoStart({bool allowElevation = true}) {
    if (!isAutoStartEnabled()) {
      return true;
    }
    bool success = RegistryHelper.disableAutoStart(runRegistryPath, appName);
    success = _retryWithElevation(
      actionName: '禁用开机自启',
      success: success,
      allowElevation: allowElevation,
      operation: ElevatedTaskRunner.opDisableAutoStart,
      payload: {'runRegistryPath': runRegistryPath, 'appName': appName},
    );
    return success;
  }

  static bool isAutoStartEnabled() {
    return RegistryHelper.isAutoStartEnabled(runRegistryPath, appName);
  }

  static bool _runWin11PackagingScript(
    String scriptName, {
    List<String> arguments = const [],
  }) {
    final scriptPath = path.join(_win11PackagingDir(), scriptName);
    if (!File(scriptPath).existsSync()) {
      logger.error('Win11 新菜单脚本不存在: $scriptPath');
      return false;
    }

    try {
      final result = Process.runSync('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
        ...arguments,
      ]);
      if (result.exitCode == 0) {
        logger.info('Win11 新菜单脚本执行成功: $scriptName');
        return true;
      }

      logger.error(
        'Win11 新菜单脚本执行失败: $scriptName exitCode=${result.exitCode} stdout=${result.stdout} stderr=${result.stderr}',
      );
      return false;
    } catch (e) {
      logger.error('Win11 新菜单脚本启动失败: $scriptName error=$e');
      return false;
    }
  }
}
