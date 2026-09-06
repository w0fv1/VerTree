import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/utils/windows_shell_notify.dart';
import 'package:win32/win32.dart';
import 'package:win32_registry/win32_registry.dart';

class ElevatedTaskRunner {
  static const int _seeMaskNoCloseProcess = 0x00000040;
  static const Duration _rateLimitWindow = Duration(seconds: 10);
  static const int _maxElevationsPerWindow = 2;
  static const String _rateLimitStateFileName =
      'vertree_admin_elevation_attempts.json';
  static String? lastError;
  static const String taskArg = '--elevated-task';
  static const String payloadArg = '--payload';

  static const String opEnableAutoStart = 'enable_autostart';
  static const String opDisableAutoStart = 'disable_autostart';
  static const String opRemoveWin11Menu = 'remove_win11_menu';
  static const String opRemoveLegacyMenus = 'remove_legacy_menus';

  static const String _classesShellPath = r'Software\Classes\*\shell';
  static List<DateTime> _fallbackRecentAttempts = <DateTime>[];

  static bool tryHandleElevatedTask(List<String> args) {
    final operation = _readOptionValue(args, taskArg);
    if (operation == null) {
      return false;
    }

    if (!Platform.isWindows) {
      exit(1);
    }

    final payload = _readPayload(args);
    final success = _executeOperation(operation, payload);
    exit(success ? 0 : 1);
  }

  static bool runTaskSync(String operation, {Map<String, dynamic>? payload}) {
    lastError = null;
    if (!Platform.isWindows) {
      lastError = 'Not running on Windows.';
      return false;
    }
    if (!_consumeElevationQuota()) {
      return false;
    }

    try {
      final executablePath = Platform.resolvedExecutable;
      final encodedPayload = base64UrlEncode(
        utf8.encode(jsonEncode(payload ?? const <String, dynamic>{})),
      );
      final elevatedArgs = <String>[
        taskArg,
        operation,
        payloadArg,
        encodedPayload,
      ];
      return _runElevated(executablePath, elevatedArgs);
    } catch (_) {
      lastError = 'Unexpected error while launching elevated task.';
      return false;
    }
  }

  static bool _runElevated(String executablePath, List<String> args) {
    final verbPtr = 'runas'.toNativeUtf16();
    final filePtr = executablePath.toNativeUtf16();
    final parameters = args.map(_quoteWindowsArg).join(' ');
    final parametersPtr = parameters.toNativeUtf16();
    final shellInfo = calloc<SHELLEXECUTEINFO>();
    final exitCodePtr = calloc<Uint32>();

    try {
      shellInfo.ref.cbSize = sizeOf<SHELLEXECUTEINFO>();
      shellInfo.ref.fMask = _seeMaskNoCloseProcess;
      shellInfo.ref.lpVerb = verbPtr;
      shellInfo.ref.lpFile = filePtr;
      shellInfo.ref.lpParameters = parametersPtr;
      shellInfo.ref.nShow = SW_SHOWNORMAL;

      final launched = ShellExecuteEx(shellInfo) != FALSE;
      if (!launched) {
        final win32Error = GetLastError();
        lastError = win32Error == ERROR_CANCELLED
            ? 'Administrator prompt was cancelled by the user.'
            : 'ShellExecuteEx failed. Win32Error=$win32Error';
        return false;
      }

      final processHandle = shellInfo.ref.hProcess;
      if (processHandle == NULL || processHandle == 0) {
        lastError = 'Elevated process handle is null.';
        return false;
      }

      WaitForSingleObject(processHandle, INFINITE);
      final gotExitCode =
          GetExitCodeProcess(processHandle, exitCodePtr) != FALSE;
      CloseHandle(processHandle);

      if (!gotExitCode) {
        lastError = 'GetExitCodeProcess failed. Win32Error=${GetLastError()}';
        return false;
      }
      if (exitCodePtr.value != 0) {
        lastError = 'Elevated task exited with code ${exitCodePtr.value}.';
        return false;
      }
      return true;
    } finally {
      calloc.free(exitCodePtr);
      calloc.free(shellInfo);
      calloc.free(parametersPtr);
      calloc.free(filePtr);
      calloc.free(verbPtr);
    }
  }

  static String? _readOptionValue(List<String> args, String optionName) {
    final optionIndex = args.indexOf(optionName);
    if (optionIndex == -1 || optionIndex + 1 >= args.length) {
      return null;
    }
    return args[optionIndex + 1];
  }

  static Map<String, dynamic> _readPayload(List<String> args) {
    final rawPayload = _readOptionValue(args, payloadArg);
    if (rawPayload == null || rawPayload.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final normalized = base64Url.normalize(rawPayload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded);
      if (json is Map<String, dynamic>) {
        return json;
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  static bool _executeOperation(
    String operation,
    Map<String, dynamic> payload,
  ) {
    switch (operation) {
      case opEnableAutoStart:
        return _enableAutoStart(payload);
      case opDisableAutoStart:
        return _disableAutoStart(payload);
      case opRemoveWin11Menu:
        return _removeWin11Menu(payload);
      case opRemoveLegacyMenus:
        return _removeLegacyMenus(payload);
      default:
        return false;
    }
  }

  static bool _removeContextMenuByKey(Map<String, dynamic> payload) {
    final hive = _parseHive(payload['hive']);
    final parentPath =
        _asNonEmptyString(payload['parentPath']) ?? _classesShellPath;
    final keyName = _asNonEmptyString(payload['keyName']);
    if (keyName == null) {
      return false;
    }

    try {
      final shellKey = _openOrCreatePath(
        hive,
        parentPath,
        desiredAccessRights: AccessRights.allAccess,
      );
      if (shellKey == null) {
        return false;
      }
      try {
        shellKey.deleteKey(keyName, recursive: true);
      } on WindowsException catch (error) {
        final hr = error.hr & 0xFFFFFFFF;
        if (hr != 0x80070002 && hr != 0x80070003) rethrow;
      } finally {
        shellKey.close();
      }
      return true;
    } catch (_) {
      return false;
    }
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
    } catch (_) {
      current?.close();
      return null;
    }
  }

  static bool _enableAutoStart(Map<String, dynamic> payload) {
    final registryPath = _asNonEmptyString(payload['runRegistryPath']);
    final appName = _asNonEmptyString(payload['appName']);
    final appCommand =
        _asNonEmptyString(payload['appCommand']) ??
        _quotedExecutablePath(_asNonEmptyString(payload['appPath']));
    if (registryPath == null || appName == null || appCommand == null) {
      return false;
    }

    try {
      final key = Registry.openPath(
        RegistryHive.localMachine,
        path: registryPath,
        desiredAccessRights: AccessRights.allAccess,
      );
      key.createValue(RegistryValue.string(appName, appCommand));
      key.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _disableAutoStart(Map<String, dynamic> payload) {
    final registryPath = _asNonEmptyString(payload['runRegistryPath']);
    final appName = _asNonEmptyString(payload['appName']);
    if (registryPath == null || appName == null) {
      return false;
    }

    try {
      final key = Registry.openPath(
        RegistryHive.localMachine,
        path: registryPath,
        desiredAccessRights: AccessRights.allAccess,
      );
      try {
        key.deleteValue(appName);
      } catch (_) {}
      key.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _removeLegacyMenus(Map<String, dynamic> payload) {
    final keys = payload['keys'];
    final hive = _asString(payload['hive']);
    if (keys is! List) {
      return false;
    }
    bool success = true;
    for (final entry in keys) {
      if (entry is! String || entry.isEmpty) {
        success = false;
        continue;
      }
      success =
          _removeContextMenuByKey({'keyName': entry, 'hive': hive}) && success;
    }
    return success;
  }

  static RegistryHive _parseHive(Object? value) {
    return _asString(value) == 'machine'
        ? RegistryHive.localMachine
        : RegistryHive.currentUser;
  }

  static bool _removeWin11Menu(Map<String, dynamic> payload) {
    final handlerName = _asNonEmptyString(payload['handlerName']);
    final clsid = _asNonEmptyString(payload['clsid']);
    if (handlerName == null || clsid == null) {
      return false;
    }
    try {
      try {
        final approvedKey = Registry.openPath(
          RegistryHive.localMachine,
          path:
              r'Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved',
          desiredAccessRights: AccessRights.allAccess,
        );
        approvedKey.deleteValue(clsid);
        approvedKey.close();
      } catch (_) {}

      try {
        final shellKey = Registry.openPath(
          RegistryHive.localMachine,
          path: r'Software\Classes\*\shell',
          desiredAccessRights: AccessRights.allAccess,
        );
        shellKey.deleteKey(handlerName, recursive: true);
        shellKey.close();
      } catch (_) {}

      try {
        final legacyHandlerKey = Registry.openPath(
          RegistryHive.localMachine,
          path: r'Software\Classes\*\shellex\ContextMenuHandlers',
          desiredAccessRights: AccessRights.allAccess,
        );
        legacyHandlerKey.deleteKey(handlerName, recursive: true);
        legacyHandlerKey.close();
      } catch (_) {}

      try {
        final clsidKey = Registry.openPath(
          RegistryHive.localMachine,
          path: r'Software\Classes\CLSID',
          desiredAccessRights: AccessRights.allAccess,
        );
        clsidKey.deleteKey(clsid, recursive: true);
        clsidKey.close();
      } catch (_) {}

      WindowsShellNotify.associationsChanged();
      return true;
    } catch (_) {
      return false;
    }
  }

  static String? _asString(Object? value) {
    if (value is String) {
      return value;
    }
    return null;
  }

  static String? _asNonEmptyString(Object? value) {
    final text = _asString(value);
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  static String? _quotedExecutablePath(String? executablePath) {
    if (executablePath == null || executablePath.isEmpty) {
      return null;
    }
    return '"$executablePath"';
  }

  static String _quoteWindowsArg(String value) {
    if (value.isEmpty) {
      return '""';
    }
    final escaped = value.replaceAll('"', r'\"');
    if (escaped.contains(' ') ||
        escaped.contains('\t') ||
        escaped.contains('\n')) {
      return '"$escaped"';
    }
    return escaped;
  }

  static bool _consumeElevationQuota() {
    final now = DateTime.now().toUtc();
    final attempts = _loadRecentAttempts(now);
    if (attempts.length >= _maxElevationsPerWindow) {
      lastError = 'Administrator elevation requested too frequently.';
      _showTooFrequentElevationDialog();
      return false;
    }

    attempts.add(now);
    _storeRecentAttempts(attempts);
    return true;
  }

  static List<DateTime> _loadRecentAttempts(DateTime now) {
    final fallbackAttempts = _filterRecentAttempts(
      _fallbackRecentAttempts,
      now,
    );
    try {
      final file = File(
        path.join(Directory.systemTemp.path, _rateLimitStateFileName),
      );
      if (!file.existsSync()) {
        _fallbackRecentAttempts = fallbackAttempts;
        return List<DateTime>.from(fallbackAttempts);
      }

      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! List) {
        _fallbackRecentAttempts = fallbackAttempts;
        return List<DateTime>.from(fallbackAttempts);
      }

      final attempts = <DateTime>[];
      for (final item in decoded) {
        final parsed = DateTime.tryParse(item?.toString() ?? '');
        if (parsed != null) {
          attempts.add(parsed.toUtc());
        }
      }

      final filtered = _filterRecentAttempts(attempts, now);
      _fallbackRecentAttempts = filtered;
      return filtered;
    } catch (_) {
      _fallbackRecentAttempts = fallbackAttempts;
      return List<DateTime>.from(fallbackAttempts);
    }
  }

  static List<DateTime> _filterRecentAttempts(
    List<DateTime> attempts,
    DateTime now,
  ) {
    return attempts
        .map((value) => value.toUtc())
        .where((value) => now.difference(value) < _rateLimitWindow)
        .toList()
      ..sort();
  }

  static void _storeRecentAttempts(List<DateTime> attempts) {
    _fallbackRecentAttempts = List<DateTime>.from(attempts);
    try {
      final file = File(
        path.join(Directory.systemTemp.path, _rateLimitStateFileName),
      );
      file.writeAsStringSync(
        jsonEncode(attempts.map((value) => value.toIso8601String()).toList()),
        flush: true,
      );
    } catch (_) {}
  }

  static void _showTooFrequentElevationDialog() {
    final locale = AppLocale();
    final textPtr = locale
        .getText(LocaleKey.appAdminPermissionTooFrequent)
        .toNativeUtf16();
    final titlePtr = locale.getText(LocaleKey.appTitle).toNativeUtf16();
    try {
      MessageBox(NULL, textPtr, titlePtr, MB_OK | MB_ICONWARNING | MB_TOPMOST);
    } finally {
      calloc.free(titlePtr);
      calloc.free(textPtr);
    }
  }
}
