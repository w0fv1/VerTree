import 'dart:developer' as developer;
import 'package:win32/win32.dart';
import 'package:win32_registry/win32_registry.dart';

import 'windows_shell_notify.dart';

class RegistryHelper {
  static const String currentUserClassesShellPath = r'Software\Classes\*\shell';
  static const String allUsersClassesShellPath = r'Software\Classes\*\shell';
  static const String allUsersClassesRootPath = r'Software\Classes';
  static const String approvedShellExtPath =
      r'Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved';
  static const int _hrFileNotFound = 0x80070002;
  static const int _hrPathNotFound = 0x80070003;
  static const int _hrAccessDenied = 0x80070005;

  static int _normalizeHr(int hr) => hr & 0xFFFFFFFF;

  static bool _isKeyMissingError(Object error) {
    if (error is WindowsException) {
      final hr = _normalizeHr(error.hr);
      return hr == _hrFileNotFound || hr == _hrPathNotFound;
    }
    return false;
  }

  static bool _isAccessDeniedError(Object error) {
    if (error is WindowsException) {
      return _normalizeHr(error.hr) == _hrAccessDenied;
    }
    return false;
  }

  static bool checkRegistryKeyExists(RegistryHive hive, String path) {
    try {
      final key = Registry.openPath(
        hive,
        path: path,
        desiredAccessRights: AccessRights.readOnly,
      );
      key.close();
      return true;
    } catch (e) {
      if (_isKeyMissingError(e)) {
        return false;
      }
      developer.log('检查注册表path: "$path" 失败: $e');
      return false;
    }
  }

  static bool checkRegistryMenuExistsByMenuName(String menuName) {
    return checkRegistryKeyExists(
      RegistryHive.currentUser,
      '$currentUserClassesShellPath\\$menuName',
    );
  }

  static bool checkRegistryMenuExistsByKey(String keyName) {
    return checkRegistryKeyExists(
      RegistryHive.currentUser,
      '$currentUserClassesShellPath\\$keyName',
    );
  }

  static bool checkMachineRegistryMenuExistsByKey(String keyName) {
    return checkRegistryKeyExists(
      RegistryHive.localMachine,
      '$allUsersClassesShellPath\\$keyName',
    );
  }

  static bool checkRegistryMenuExistsByKeyAtPath(
    String parentPath,
    String keyName,
  ) {
    return checkRegistryKeyExists(
      RegistryHive.currentUser,
      '$parentPath\\$keyName',
    );
  }

  static bool checkMachineRegistryMenuExistsByKeyAtPath(
    String parentPath,
    String keyName,
  ) {
    return checkRegistryKeyExists(
      RegistryHive.localMachine,
      '$parentPath\\$keyName',
    );
  }

  static RegistryKey? _openOrCreatePath(
    RegistryHive hive,
    String fullPath, {
    required AccessRights desiredAccessRights,
  }) {
    final normalized = fullPath
        .split('\\')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (normalized.isEmpty) {
      return null;
    }

    RegistryKey? current;
    var currentPath = normalized.first;
    try {
      current = Registry.openPath(
        hive,
        path: currentPath,
        desiredAccessRights: desiredAccessRights,
      );
      for (final segment in normalized.skip(1)) {
        final next = current!.createKey(segment);
        current.close();
        current = next;
        currentPath = '$currentPath\\$segment';
      }
      return current;
    } catch (e) {
      current?.close();
      developer.log('打开或创建注册表路径失败: "$fullPath" error=$e');
      return null;
    }
  }

  static bool addOrUpdateRegistryKey(
    String path,
    String keyName,
    String value,
  ) {
    try {
      final key = Registry.openPath(
        RegistryHive.localMachine,
        path: path,
        desiredAccessRights: AccessRights.allAccess,
      );
      key.createValue(RegistryValue.string(keyName, value));
      key.close();
      return true;
    } catch (e) {
      if (_isAccessDeniedError(e)) {
        return false;
      }
      developer.log('添加或更新注册表项失败: $e');
      return false;
    }
  }

  static bool deleteRegistryKey(String path, String keyName) {
    try {
      final key = Registry.openPath(
        RegistryHive.localMachine,
        path: path,
        desiredAccessRights: AccessRights.allAccess,
      );
      key.deleteValue(keyName);
      key.close();
      return true;
    } catch (e) {
      if (_isAccessDeniedError(e)) {
        return false;
      }
      developer.log('删除注册表项失败: $e');
      return false;
    }
  }

  static bool addContextMenuOption(
    String keyName,
    String muiVerb,
    String command, {
    String? iconPath,
  }) {
    return addContextMenuOptionAtPath(
      currentUserClassesShellPath,
      keyName,
      muiVerb,
      command: command,
      iconPath: iconPath,
    );
  }

  static bool addContextMenuOptionAtPath(
    String parentPath,
    String keyName,
    String muiVerb, {
    String? command,
    String? iconPath,
    bool isSubmenu = false,
    RegistryHive hive = RegistryHive.currentUser,
  }) {
    try {
      String registryPath = '$parentPath\\$keyName';
      String commandPath = '$registryPath\\command';

      developer.log(
        '尝试创建右键菜单: registryPath="$registryPath", commandPath="$commandPath"',
      );

      final shellKey = _openOrCreatePath(
        hive,
        parentPath,
        desiredAccessRights: AccessRights.allAccess,
      );
      if (shellKey == null) {
        return false;
      }

      final menuKey = shellKey.createKey(keyName);
      menuKey.createValue(RegistryValue.string('MUIVerb', muiVerb));

      if (iconPath != null && iconPath.isNotEmpty) {
        menuKey.createValue(RegistryValue.string('Icon', iconPath));
        developer.log('已为 "$keyName" 设置图标: $iconPath');
      }

      if (isSubmenu) {
        menuKey.createValue(RegistryValue.string('SubCommands', ''));
        menuKey.createKey('shell').close();
      }

      menuKey.close();
      shellKey.close();

      developer.log('成功创建 registryPath: $registryPath');

      if (!isSubmenu && command != null && command.isNotEmpty) {
        final menuCommandKey = _openOrCreatePath(
          hive,
          registryPath,
          desiredAccessRights: AccessRights.allAccess,
        );
        if (menuCommandKey == null) {
          return false;
        }
        final commandKey = menuCommandKey.createKey('command');
        commandKey.createValue(RegistryValue.string('', command));
        commandKey.close();
        menuCommandKey.close();

        developer.log('成功创建 commandPath: $commandPath -> $command');
      }

      return true;
    } catch (e) {
      if (_isAccessDeniedError(e)) {
        return false;
      }
      developer.log('添加右键菜单失败: $e');
      return false;
    }
  }

  static bool removeContextMenuOptionByMenuName(String menuName) {
    try {
      String registryPath = '$currentUserClassesShellPath\\$menuName';

      final key = Registry.openPath(
        RegistryHive.currentUser,
        path: currentUserClassesShellPath,
        desiredAccessRights: AccessRights.allAccess,
      );

      try {
        key.deleteKey(menuName, recursive: true);
      } catch (e) {
        if (!_isKeyMissingError(e)) {
          rethrow;
        }
      }
      key.close();

      developer.log('成功删除右键菜单项: $registryPath');
      return true;
    } catch (e) {
      if (_isAccessDeniedError(e)) {
        return false;
      }
      developer.log('删除右键菜单失败: $e');
      return false;
    }
  }

  static bool removeContextMenuOptionByKey(String keyName) {
    return removeContextMenuOptionByKeyAtPath(
      currentUserClassesShellPath,
      keyName,
    );
  }

  static bool removeContextMenuOptionByKeyAtPath(
    String parentPath,
    String keyName, {
    RegistryHive hive = RegistryHive.currentUser,
  }) {
    try {
      final parentKey = _openOrCreatePath(
        hive,
        parentPath,
        desiredAccessRights: AccessRights.allAccess,
      );
      if (parentKey == null) {
        return false;
      }

      try {
        parentKey.deleteKey(keyName, recursive: true);
      } catch (e) {
        if (!_isKeyMissingError(e)) {
          rethrow;
        }
      }
      parentKey.close();

      developer.log('成功通过键名 "$keyName" 删除右键菜单项');
      return true;
    } catch (e) {
      if (_isAccessDeniedError(e)) {
        return false;
      }
      developer.log('通过键名 "$keyName" 删除右键菜单项失败: $e');
      return false;
    }
  }

  static bool removeMachineContextMenuOptionByKey(String keyName) {
    return removeContextMenuOptionByKeyAtPath(
      allUsersClassesShellPath,
      keyName,
      hive: RegistryHive.localMachine,
    );
  }

  static bool removeMachineContextMenuOptionByKeyAtPath(
    String parentPath,
    String keyName,
  ) {
    return removeContextMenuOptionByKeyAtPath(
      parentPath,
      keyName,
      hive: RegistryHive.localMachine,
    );
  }

  static bool enableAutoStart(
    String runRegistryPath,
    String appName,
    String appCommand,
  ) {
    try {
      final key = Registry.openPath(
        RegistryHive.localMachine,
        path: runRegistryPath,
        desiredAccessRights: AccessRights.allAccess,
      );
      key.createValue(RegistryValue.string(appName, appCommand));
      key.close();
      developer.log('成功设置应用 "$appName" 开机自启');
      return true;
    } catch (e) {
      if (_isAccessDeniedError(e)) {
        return false;
      }
      developer.log('设置开机自启失败: $e');
      return false;
    }
  }

  static bool disableAutoStart(String runRegistryPath, String appName) {
    try {
      final key = Registry.openPath(
        RegistryHive.localMachine,
        path: runRegistryPath,
        desiredAccessRights: AccessRights.allAccess,
      );
      try {
        key.deleteValue(appName);
      } catch (e) {
        if (!_isKeyMissingError(e)) {
          rethrow;
        }
      }
      key.close();
      developer.log('成功移除应用 "$appName" 的开机自启');
      return true;
    } catch (e) {
      if (_isAccessDeniedError(e)) {
        return false;
      }
      developer.log('移除开机自启失败: $e');
      return false;
    }
  }

  static bool isAutoStartEnabled(String runRegistryPath, String appName) {
    try {
      final key = Registry.openPath(
        RegistryHive.localMachine,
        path: runRegistryPath,
        desiredAccessRights: AccessRights.readOnly,
      );
      final exists = key.getValue(appName) != null;
      key.close();
      return exists;
    } catch (e) {
      if (_isAccessDeniedError(e) || _isKeyMissingError(e)) {
        return false;
      }
      developer.log('检查开机自启状态失败: $e');
      return false;
    }
  }

  static bool addWin11ContextMenuHandler(
    String handlerName,
    String clsid,
    String serverPath,
  ) {
    try {
      final approvedKey = Registry.openPath(
        RegistryHive.localMachine,
        path: approvedShellExtPath,
        desiredAccessRights: AccessRights.allAccess,
      );
      approvedKey.createValue(RegistryValue.string(clsid, handlerName));
      approvedKey.close();

      final clsidRoot = Registry.openPath(
        RegistryHive.localMachine,
        path: '$allUsersClassesRootPath\\CLSID',
        desiredAccessRights: AccessRights.allAccess,
      );
      final clsidKey = clsidRoot.createKey(clsid);
      clsidKey.createValue(RegistryValue.string('', handlerName));
      try {
        clsidKey.deleteKey('LocalServer32', recursive: true);
      } catch (_) {}

      final serverKey = clsidKey.createKey('InprocServer32');
      serverKey.createValue(RegistryValue.string('', serverPath));
      serverKey.createValue(
        RegistryValue.string('ThreadingModel', 'Apartment'),
      );
      serverKey.close();
      clsidKey.close();
      clsidRoot.close();

      try {
        final legacyHandlerKey = Registry.openPath(
          RegistryHive.localMachine,
          path: '$allUsersClassesRootPath\\*\\shellex\\ContextMenuHandlers',
          desiredAccessRights: AccessRights.allAccess,
        );
        legacyHandlerKey.deleteKey(handlerName, recursive: true);
        legacyHandlerKey.close();
      } catch (e) {
        if (!_isKeyMissingError(e) && !_isAccessDeniedError(e)) {
          developer.log('清理旧 Win11 handler 失败: $e');
        }
      }

      final shellKey = Registry.openPath(
        RegistryHive.localMachine,
        path: '$allUsersClassesRootPath\\*\\shell',
        desiredAccessRights: AccessRights.allAccess,
      );
      final menuKey = shellKey.createKey(handlerName);
      menuKey.createValue(RegistryValue.string('MUIVerb', handlerName));
      menuKey.createValue(
        RegistryValue.string('ExplorerCommandHandler', clsid),
      );
      menuKey.close();
      shellKey.close();

      WindowsShellNotify.associationsChanged();
      return true;
    } catch (e) {
      if (_isAccessDeniedError(e)) {
        return false;
      }
      developer.log('添加 Win11 右键菜单处理器失败: $e');
      return false;
    }
  }

  static bool removeWin11ContextMenuHandler(String handlerName, String clsid) {
    try {
      bool accessDenied = false;

      try {
        final approvedKey = Registry.openPath(
          RegistryHive.localMachine,
          path: approvedShellExtPath,
          desiredAccessRights: AccessRights.allAccess,
        );
        approvedKey.deleteValue(clsid);
        approvedKey.close();
      } catch (e) {
        if (_isAccessDeniedError(e)) {
          accessDenied = true;
        } else if (!_isKeyMissingError(e)) {
          developer.log('移除 Approved 项失败: $e');
        }
      }

      try {
        final shellKey = Registry.openPath(
          RegistryHive.localMachine,
          path: '$allUsersClassesRootPath\\*\\shell',
          desiredAccessRights: AccessRights.allAccess,
        );
        shellKey.deleteKey(handlerName, recursive: true);
        shellKey.close();
      } catch (e) {
        if (_isAccessDeniedError(e)) {
          accessDenied = true;
        } else if (!_isKeyMissingError(e)) {
          developer.log('移除 Win11 shell verb 失败: $e');
        }
      }

      try {
        final legacyHandlerKey = Registry.openPath(
          RegistryHive.localMachine,
          path: '$allUsersClassesRootPath\\*\\shellex\\ContextMenuHandlers',
          desiredAccessRights: AccessRights.allAccess,
        );
        legacyHandlerKey.deleteKey(handlerName, recursive: true);
        legacyHandlerKey.close();
      } catch (e) {
        if (_isAccessDeniedError(e)) {
          accessDenied = true;
        } else if (!_isKeyMissingError(e)) {
          developer.log('移除旧 Win11 handler 失败: $e');
        }
      }

      try {
        final clsidKey = Registry.openPath(
          RegistryHive.localMachine,
          path: '$allUsersClassesRootPath\\CLSID',
          desiredAccessRights: AccessRights.allAccess,
        );
        clsidKey.deleteKey(clsid, recursive: true);
        clsidKey.close();
      } catch (e) {
        if (_isAccessDeniedError(e)) {
          accessDenied = true;
        } else if (!_isKeyMissingError(e)) {
          developer.log('移除 CLSID 注册失败: $e');
        }
      }

      if (accessDenied) {
        return false;
      }

      WindowsShellNotify.associationsChanged();
      return true;
    } catch (e) {
      if (_isAccessDeniedError(e)) {
        return false;
      }
      developer.log('移除 Win11 右键菜单处理器失败: $e');
      return false;
    }
  }

  static bool checkWin11ContextMenuHandler(String handlerName, String clsid) {
    try {
      final key = Registry.openPath(
        RegistryHive.localMachine,
        path: '$allUsersClassesRootPath\\*\\shell\\$handlerName',
        desiredAccessRights: AccessRights.readOnly,
      );
      final value = key.getValue('ExplorerCommandHandler');
      key.close();
      final commandHandler = switch (value) {
        StringValue(:final value) => value,
        UnexpandedStringValue(:final value) => value,
        LinkValue(:final value) => value,
        _ => null,
      };
      if (commandHandler != null) {
        return commandHandler.toLowerCase() == clsid.toLowerCase();
      }
      return false;
    } catch (e) {
      if (_isKeyMissingError(e)) {
        return false;
      }
      developer.log('检查 Win11 右键菜单处理器失败: $e');
      return false;
    }
  }
}
