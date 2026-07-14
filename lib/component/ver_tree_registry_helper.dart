import 'dart:io';
import 'package:vertree/component/app_launch_args.dart';
import 'package:vertree/component/elevated_task.dart';
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/component/file_utils.dart';
import 'package:vertree/main.dart';
import 'package:vertree/utils/windows_package_identity.dart';

import '../utils/windows_registry_util.dart';
import 'package:path/path.dart' as path;

class VerTreeRegistryService {
  static const String registryBackupKeyName = "RegistryVerTreeBackup";
  static const String registryExpressBackupKeyName =
      "RegistryVerTreeExpressBackup";
  static const String registryMonitorKeyName = "RegistryVerTreeMonitor";
  static const String registryShareKeyName = "RegistryVerTreeShare";
  static const String registryViewTreeKeyName = "RegistryVerTreeViewTree";
  static const String legacyMenuRootKeyName = "RegistryVerTreeLegacyRoot";
  static const String legacyMenuCollapsedConfigKey = "legacyMenuCollapsed";

  static const String appName = "VerTree";

  static const String runRegistryPath =
      r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const String win11HandlerName = 'Vertree';
  static const String win11HandlerClsid =
      '{BFD9F3B4-3C8C-4B1C-8E57-1F4BA6A96F3E}';

  static String exePath = Platform.resolvedExecutable;

  static String get _autoStartCommand =>
      buildWindowsLaunchCommand(exePath, arguments: const [startupLaunchArg]);

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

  static void reAddContextMenu() {
    final success = _refreshRegisteredContextMenus();
    if (!success) {
      logger.error('刷新已注册右键菜单文案失败');
    }
  }

  static bool addVerTreeBackupContextMenu({bool allowElevation = true}) {
    final exePath = Platform.resolvedExecutable;
    final iconPath = path.join(
      FileUtils.appDirPath(),
      'data',
      'flutter_assets',
      'assets',
      'img',
      'icon',
      'save.ico',
    );
    final menuText = appLocale.getText(LocaleKey.registryBackupKeyName);
    final command = '"$exePath" backup "%1"';

    bool success = RegistryHelper.addContextMenuOption(
      registryBackupKeyName,
      menuText,
      command,
      iconPath: iconPath,
    );
    return success;
  }

  static bool addVerTreeMonitorContextMenu({bool allowElevation = true}) {
    final exePath = Platform.resolvedExecutable;
    final iconPath = path.join(
      FileUtils.appDirPath(),
      'data',
      'flutter_assets',
      'assets',
      'img',
      'icon',
      'monit.ico',
    );
    final menuText = appLocale.getText(LocaleKey.registryMonitorKeyName);
    final command = '"$exePath" monit "%1"';

    bool success = RegistryHelper.addContextMenuOption(
      registryMonitorKeyName,
      menuText,
      command,
      iconPath: iconPath,
    );
    return success;
  }

  static bool addVerTreeViewContextMenu({bool allowElevation = true}) {
    final exePath = Platform.resolvedExecutable;
    final iconPath = path.join(
      FileUtils.appDirPath(),
      'data',
      'flutter_assets',
      'assets',
      'img',
      'logo',
      'logo.ico',
    );
    final menuText = appLocale.getText(LocaleKey.registryViewTreeKeyName);
    final command = '"$exePath" "%1"';

    bool success = RegistryHelper.addContextMenuOption(
      registryViewTreeKeyName,
      menuText,
      command,
      iconPath: iconPath,
    );
    return success;
  }

  static bool addVerTreeShareContextMenu({bool allowElevation = true}) {
    final exePath = Platform.resolvedExecutable;
    final iconPath = path.join(
      FileUtils.appDirPath(),
      'data',
      'flutter_assets',
      'assets',
      'img',
      'icon',
      'share.ico',
    );
    final menuText = appLocale.getText(LocaleKey.registryShareKeyName);
    final command = '"$exePath" share "%1"';

    bool success = RegistryHelper.addContextMenuOption(
      registryShareKeyName,
      menuText,
      command,
      iconPath: iconPath,
    );
    return success;
  }

  static bool addVerTreeExpressBackupContextMenu({bool allowElevation = true}) {
    final exePath = Platform.resolvedExecutable;
    final iconPath = path.join(
      FileUtils.appDirPath(),
      'data',
      'flutter_assets',
      'assets',
      'img',
      'icon',
      'express-save.ico',
    );
    final menuText = appLocale.getText(LocaleKey.registryExpressBackupKeyName);
    final command = '"$exePath" express-backup "%1"';

    bool success = RegistryHelper.addContextMenuOption(
      registryExpressBackupKeyName,
      menuText,
      command,
      iconPath: iconPath,
    );
    return success;
  }

  static bool removeVerTreeExpressBackupContextMenu({
    bool allowElevation = true,
  }) {
    if (!checkExpressBackupKeyExists()) {
      return true;
    }
    bool success = RegistryHelper.removeContextMenuOptionByKey(
      registryExpressBackupKeyName,
    );
    return success;
  }

  static bool removeVerTreeViewContextMenu({bool allowElevation = true}) {
    if (!checkViewTreeKeyExists()) {
      return true;
    }
    bool success = RegistryHelper.removeContextMenuOptionByKey(
      registryViewTreeKeyName,
    );
    return success;
  }

  static bool removeVerTreeShareContextMenu({bool allowElevation = true}) {
    if (!checkShareKeyExists()) {
      return true;
    }
    bool success = RegistryHelper.removeContextMenuOptionByKey(
      registryShareKeyName,
    );
    return success;
  }

  static bool removeVerTreeMonitorContextMenu({bool allowElevation = true}) {
    if (!checkMonitorKeyExists()) {
      return true;
    }
    bool success = RegistryHelper.removeContextMenuOptionByKey(
      registryMonitorKeyName,
    );
    return success;
  }

  static bool removeVerTreeBackupContextMenu({bool allowElevation = true}) {
    if (!checkBackupKeyExists()) {
      return true;
    }
    bool success = RegistryHelper.removeContextMenuOptionByKey(
      registryBackupKeyName,
    );
    return success;
  }

  static bool checkBackupKeyExists() {
    return _checkLegacyEntryExists(registryBackupKeyName);
  }

  static bool checkExpressBackupKeyExists() {
    return _checkLegacyEntryExists(registryExpressBackupKeyName);
  }

  static bool checkMonitorKeyExists() {
    return _checkLegacyEntryExists(registryMonitorKeyName);
  }

  static bool checkShareKeyExists() {
    return _checkLegacyEntryExists(registryShareKeyName);
  }

  static bool checkViewTreeKeyExists() {
    return _checkLegacyEntryExists(registryViewTreeKeyName);
  }

  static bool checkLegacyMenuRootExists() {
    return RegistryHelper.checkRegistryMenuExistsByKey(legacyMenuRootKeyName) ||
        RegistryHelper.checkMachineRegistryMenuExistsByKey(
          legacyMenuRootKeyName,
        );
  }

  static bool checkAnyTopLevelLegacyMenuExists() {
    return RegistryHelper.checkRegistryMenuExistsByKey(registryBackupKeyName) ||
        RegistryHelper.checkRegistryMenuExistsByKey(
          registryExpressBackupKeyName,
        ) ||
        RegistryHelper.checkRegistryMenuExistsByKey(registryMonitorKeyName) ||
        RegistryHelper.checkRegistryMenuExistsByKey(registryShareKeyName) ||
        RegistryHelper.checkRegistryMenuExistsByKey(registryViewTreeKeyName) ||
        RegistryHelper.checkMachineRegistryMenuExistsByKey(
          registryBackupKeyName,
        ) ||
        RegistryHelper.checkMachineRegistryMenuExistsByKey(
          registryExpressBackupKeyName,
        ) ||
        RegistryHelper.checkMachineRegistryMenuExistsByKey(
          registryMonitorKeyName,
        ) ||
        RegistryHelper.checkMachineRegistryMenuExistsByKey(
          registryShareKeyName,
        ) ||
        RegistryHelper.checkMachineRegistryMenuExistsByKey(
          registryViewTreeKeyName,
        );
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

  static bool applyInitialSetup() {
    final entries = _legacyMenuEntries();
    final packaged = WindowsPackageIdentity.isPackagedOrRegistered();

    bool success = true;
    for (final entry in entries) {
      success =
          RegistryHelper.addContextMenuOption(
            entry['keyName']!,
            entry['menuText']!,
            entry['command']!,
            iconPath: entry['iconPath'],
          ) &&
          success;
    }

    success =
        RegistryHelper.enableAutoStart(
          runRegistryPath,
          appName,
          _autoStartCommand,
        ) &&
        success;

    if (!packaged) {
      success = addWin11ContextMenuHandler(allowElevation: false) && success;
    }

    if (success) {
      return true;
    }

    logger.info('初始化普通权限失败，尝试一次性提权配置...');
    final payload = <String, dynamic>{
      'contextMenus': entries,
      'autostart': {
        'enable': true,
        'runRegistryPath': runRegistryPath,
        'appName': appName,
        'appCommand': _autoStartCommand,
      },
    };
    final elevatedSuccess = ElevatedTaskRunner.runTaskSync(
      ElevatedTaskRunner.opApplySetup,
      payload: payload,
    );

    if (elevatedSuccess) {
      logger.info('初始化提权执行成功');
    } else {
      logger.error(
        '初始化提权执行失败: ${ElevatedTaskRunner.lastError ?? "unknown error"}',
      );
    }
    return elevatedSuccess;
  }

  static bool applyLegacyMenus(bool enable) {
    return applyLegacyMenusWithLayout(
      enable,
      collapsed: configer.get<bool>(legacyMenuCollapsedConfigKey, false),
    );
  }

  static bool applyLegacyMenusWithLayout(
    bool enable, {
    required bool collapsed,
  }) {
    final entries = _legacyMenuEntries(collapsed: collapsed);
    bool success = true;

    if (enable) {
      success =
          _removeLegacyMenuRepresentations(removeMachineEntries: false) &&
          success;
      for (final entry in entries) {
        final applied = _applyContextMenuPayload(entry);
        success = applied && success;
        if (!applied) {
          break;
        }
      }
      if (!success) {
        return false;
      }
      if (_hasMachineLevelLegacyMenuRemnants()) {
        final cleanupSuccess = _removeLegacyMachineMenuRepresentations();
        if (!cleanupSuccess) {
          logger.error('检测到旧的 HKLM 旧版右键菜单残留，自动清理失败');
        } else {
          logger.info('已清理旧的 HKLM 旧版右键菜单残留');
        }
      }
      return true;
    }

    success = _removeLegacyMenuRepresentations(removeMachineEntries: false);
    final machineCleanupSuccess = _removeLegacyMachineMenuRepresentations();
    success = machineCleanupSuccess && success;
    if (success) {
      return true;
    }
    return false;
  }

  static bool addWin11ContextMenuHandler({bool allowElevation = true}) {
    final cleaned = _hasLegacyWin11ContextMenuHandler()
        ? _removeLegacyWin11ContextMenuHandler(allowElevation: allowElevation)
        : true;
    if (WindowsPackageIdentity.isPackagedOrRegistered()) {
      return cleaned;
    }
    if (!_hasWin11PackagingAssets()) {
      logger.error('Win11 新菜单注册失败：未找到 sparse package 资源');
      return false;
    }

    final registered = _runWin11PackagingScript(
      'refresh_win11_menu.ps1',
      arguments: ['-ExternalLocation', FileUtils.appDirPath()],
    );
    return cleaned && registered;
  }

  static bool removeWin11ContextMenuHandler({bool allowElevation = true}) {
    final packagedOrRegistered =
        WindowsPackageIdentity.isPackagedOrRegistered();
    final hasLegacyHandler = _hasLegacyWin11ContextMenuHandler();
    if (!packagedOrRegistered && !hasLegacyHandler) {
      return true;
    }

    bool success = true;
    if (packagedOrRegistered) {
      if (_hasWin11PackagingAssets()) {
        success =
            _runWin11PackagingScript('uninstall_sparse_package.ps1') && success;
      }
    }
    if (hasLegacyHandler) {
      success =
          _removeLegacyWin11ContextMenuHandler(
            allowElevation: allowElevation,
          ) &&
          success;
    }
    return success;
  }

  static bool _removeLegacyWin11ContextMenuHandler({
    bool allowElevation = true,
  }) {
    bool success = RegistryHelper.removeWin11ContextMenuHandler(
      win11HandlerName,
      win11HandlerClsid,
    );
    return _retryWithElevation(
      actionName: '清理旧 Win11 菜单注册',
      success: success,
      allowElevation: allowElevation,
      operation: ElevatedTaskRunner.opRemoveWin11Menu,
      payload: {'handlerName': win11HandlerName, 'clsid': win11HandlerClsid},
    );
  }

  static bool checkWin11ContextMenuHandler() {
    return WindowsPackageIdentity.isPackagedOrRegistered();
  }

  static bool migrateLegacyMenuLayoutConfig() {
    final groupedLegacyMenu = checkLegacyMenuRootExists();

    if (groupedLegacyMenu) {
      if (configer.get<bool>(legacyMenuCollapsedConfigKey, false) != true) {
        configer.set<bool>(legacyMenuCollapsedConfigKey, true);
      }
      return true;
    }

    if (configer.get<bool>(legacyMenuCollapsedConfigKey, false) != false) {
      configer.set<bool>(legacyMenuCollapsedConfigKey, false);
    }
    return true;
  }

  static bool _refreshRegisteredContextMenus() {
    final collapsed = RegistryHelper.checkRegistryMenuExistsByKey(
      legacyMenuRootKeyName,
    );
    final entries = _registeredLegacyMenuEntries(collapsed: collapsed);
    if (entries.isEmpty) {
      return true;
    }

    bool success = true;
    for (final entry in entries) {
      final applied = _applyContextMenuPayload(entry);
      success = applied && success;
      if (!applied) {
        break;
      }
    }

    return success;
  }

  static Map<String, dynamic> _contextMenuPayload(
    String keyName,
    String menuText,
    String? command,
    String? iconPath, {
    String? parentPath,
    bool isSubmenu = false,
  }) {
    return {
      'keyName': keyName,
      'menuText': menuText,
      'command': command,
      'iconPath': iconPath,
      'parentPath': parentPath,
      'isSubmenu': isSubmenu,
    };
  }

  static String _iconPath(String fileName, {bool isLogo = false}) {
    return path.join(
      FileUtils.appDirPath(),
      'data',
      'flutter_assets',
      'assets',
      'img',
      isLogo ? 'logo' : 'icon',
      fileName,
    );
  }

  static List<Map<String, dynamic>> _legacyMenuEntries({
    bool collapsed = false,
  }) {
    final childParentPath = collapsed
        ? '${RegistryHelper.currentUserClassesShellPath}\\$legacyMenuRootKeyName\\shell'
        : null;
    final entries = <Map<String, dynamic>>[
      if (collapsed)
        _contextMenuPayload(
          legacyMenuRootKeyName,
          'Vertree',
          null,
          _iconPath('logo.ico', isLogo: true),
          parentPath: RegistryHelper.currentUserClassesShellPath,
          isSubmenu: true,
        ),
      _contextMenuPayload(
        registryBackupKeyName,
        appLocale.getText(LocaleKey.registryBackupKeyName),
        '"$exePath" backup "%1"',
        _iconPath('save.ico'),
        parentPath: childParentPath,
      ),
      _contextMenuPayload(
        registryMonitorKeyName,
        appLocale.getText(LocaleKey.registryMonitorKeyName),
        '"$exePath" monit "%1"',
        _iconPath('monit.ico'),
        parentPath: childParentPath,
      ),
      _contextMenuPayload(
        registryViewTreeKeyName,
        appLocale.getText(LocaleKey.registryViewTreeKeyName),
        '"$exePath" "%1"',
        _iconPath('logo.ico', isLogo: true),
        parentPath: childParentPath,
      ),
      _contextMenuPayload(
        registryShareKeyName,
        appLocale.getText(LocaleKey.registryShareKeyName),
        '"$exePath" share "%1"',
        _iconPath('share.ico'),
        parentPath: childParentPath,
      ),
      _contextMenuPayload(
        registryExpressBackupKeyName,
        appLocale.getText(LocaleKey.registryExpressBackupKeyName),
        '"$exePath" express-backup "%1"',
        _iconPath('express-save.ico'),
        parentPath: childParentPath,
      ),
    ];
    return entries;
  }

  static List<Map<String, dynamic>> _registeredLegacyMenuEntries({
    required bool collapsed,
  }) {
    if (collapsed) {
      return _legacyMenuEntries(collapsed: true);
    }
    return _legacyMenuEntries().where((entry) {
      final keyName = entry['keyName'] as String?;
      return keyName != null &&
          RegistryHelper.checkRegistryMenuExistsByKey(keyName);
    }).toList();
  }

  static List<Map<String, String?>> _legacyMenuRemovalPayloads({
    required String hive,
  }) {
    return [
      {'keyName': registryBackupKeyName, 'hive': hive},
      {'keyName': registryMonitorKeyName, 'hive': hive},
      {'keyName': registryViewTreeKeyName, 'hive': hive},
      {'keyName': registryShareKeyName, 'hive': hive},
      {'keyName': registryExpressBackupKeyName, 'hive': hive},
      {'keyName': legacyMenuRootKeyName, 'hive': hive},
    ];
  }

  static bool _removeLegacyMenuRepresentations({
    required bool removeMachineEntries,
  }) {
    bool success = true;
    for (final entry in _legacyMenuRemovalPayloads(hive: 'user')) {
      final keyName = entry['keyName'];
      if (keyName == null) continue;
      success = RegistryHelper.removeContextMenuOptionByKey(keyName) && success;
    }
    if (removeMachineEntries) {
      success = _removeLegacyMachineMenuRepresentations() && success;
    }
    return success;
  }

  static bool _removeLegacyMachineMenuRepresentations() {
    if (!_hasMachineLevelLegacyMenuRemnants()) {
      return true;
    }
    final machineKeys = _legacyMenuRemovalPayloads(
      hive: 'machine',
    ).map((entry) => entry['keyName']).whereType<String>().toList();
    final success = ElevatedTaskRunner.runTaskSync(
      ElevatedTaskRunner.opRemoveLegacyMenus,
      payload: {'keys': machineKeys, 'hive': 'machine'},
    );
    if (!success) {
      logger.error(
        '清理 HKLM 旧版右键菜单残留失败: ${ElevatedTaskRunner.lastError ?? "unknown error"}',
      );
    }
    return success;
  }

  static bool _applyContextMenuPayload(Map<String, dynamic> entry) {
    final keyName = entry['keyName'] as String?;
    final menuText = entry['menuText'] as String?;
    final command = entry['command'] as String?;
    final iconPath = entry['iconPath'] as String?;
    final parentPath = entry['parentPath'] as String?;
    final isSubmenu = entry['isSubmenu'] == true;
    if (keyName == null || menuText == null) {
      return false;
    }
    return RegistryHelper.addContextMenuOptionAtPath(
      parentPath ?? RegistryHelper.currentUserClassesShellPath,
      keyName,
      menuText,
      command: command,
      iconPath: iconPath,
      isSubmenu: isSubmenu,
    );
  }

  static bool _checkLegacyEntryExists(String keyName) {
    if (RegistryHelper.checkRegistryMenuExistsByKey(keyName)) {
      return true;
    }
    if (RegistryHelper.checkRegistryMenuExistsByKeyAtPath(
      '${RegistryHelper.currentUserClassesShellPath}\\$legacyMenuRootKeyName\\shell',
      keyName,
    )) {
      return true;
    }
    if (RegistryHelper.checkMachineRegistryMenuExistsByKey(keyName)) {
      return true;
    }
    return RegistryHelper.checkMachineRegistryMenuExistsByKeyAtPath(
      '${RegistryHelper.allUsersClassesShellPath}\\$legacyMenuRootKeyName\\shell',
      keyName,
    );
  }

  static bool _hasMachineLevelLegacyMenuRemnants() {
    return RegistryHelper.checkMachineRegistryMenuExistsByKey(
          legacyMenuRootKeyName,
        ) ||
        RegistryHelper.checkMachineRegistryMenuExistsByKey(
          registryBackupKeyName,
        ) ||
        RegistryHelper.checkMachineRegistryMenuExistsByKey(
          registryExpressBackupKeyName,
        ) ||
        RegistryHelper.checkMachineRegistryMenuExistsByKey(
          registryMonitorKeyName,
        ) ||
        RegistryHelper.checkMachineRegistryMenuExistsByKey(
          registryShareKeyName,
        ) ||
        RegistryHelper.checkMachineRegistryMenuExistsByKey(
          registryViewTreeKeyName,
        );
  }

  static bool _hasLegacyWin11ContextMenuHandler() {
    return RegistryHelper.checkWin11ContextMenuHandler(
      win11HandlerName,
      win11HandlerClsid,
    );
  }

  static String _win11PackagingDir() {
    return path.join(FileUtils.appDirPath(), 'win11_packaging');
  }

  static bool _hasWin11PackagingAssets() {
    final packagingDir = _win11PackagingDir();
    return File(
          path.join(packagingDir, 'install_sparse_package.ps1'),
        ).existsSync() &&
        File(path.join(packagingDir, 'refresh_win11_menu.ps1')).existsSync() &&
        File(
          path.join(packagingDir, 'sparse', 'AppxManifest.xml'),
        ).existsSync();
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

  static const String backupMenuName = "备份文件 VerTree";
  static const String expressBackupMenuName = "快速备份文件 VerTree";
  static const String monitorMenuName = "监控文件变动 VerTree";
  static const String viewTreeMenuName = "查看文件版本树 VerTree";
  static bool clearObsoleteRegistry() {
    bool success = true;

    if (checkContextMenuExists(backupMenuName)) {
      success &= RegistryHelper.removeContextMenuOptionByMenuName(
        backupMenuName,
      );
    }

    if (checkContextMenuExists(monitorMenuName)) {
      success &= RegistryHelper.removeContextMenuOptionByMenuName(
        monitorMenuName,
      );
    }

    if (checkContextMenuExists(viewTreeMenuName)) {
      success &= RegistryHelper.removeContextMenuOptionByMenuName(
        viewTreeMenuName,
      );
    }

    if (checkContextMenuExists(expressBackupMenuName)) {
      success &= RegistryHelper.removeContextMenuOptionByMenuName(
        expressBackupMenuName,
      );
    }

    return success;
  }

  static bool checkContextMenuExists(String menuName) {
    return RegistryHelper.checkRegistryMenuExistsByMenuName(menuName);
  }
}
