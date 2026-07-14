import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:win32_registry/win32_registry.dart';

class WindowsPackageIdentity {
  static const String packageName = 'w0fv1.vertree';
  static const int _appmodelErrorNoPackage = 15700;
  static const int _errorInsufficientBuffer = 122;

  static bool isPackaged() {
    final lengthPtr = calloc<Uint32>();
    try {
      final result = GetCurrentPackageFullName(lengthPtr, nullptr);
      if (result == _appmodelErrorNoPackage) {
        return false;
      }
      if (result == _errorInsufficientBuffer && lengthPtr.value > 0) {
        final buffer = calloc<Uint16>(lengthPtr.value).cast<Utf16>();
        try {
          final second = GetCurrentPackageFullName(lengthPtr, buffer);
          return second == ERROR_SUCCESS;
        } finally {
          calloc.free(buffer);
        }
      }
      return result == ERROR_SUCCESS;
    } finally {
      calloc.free(lengthPtr);
    }
  }

  static bool isSparsePackageRegistered() {
    const packageRoots = <String>[
      r'Software\Classes\ActivatableClasses\Package',
      r'Software\Classes\PackagedCom\Package',
      r'Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages',
    ];
    for (final packageRoot in packageRoots) {
      try {
        final key = Registry.openPath(
          RegistryHive.currentUser,
          path: packageRoot,
          desiredAccessRights: AccessRights.readOnly,
        );
        final names = key.subkeyNames;
        key.close();
        for (final name in names) {
          if (name.startsWith('${packageName}_')) {
            return true;
          }
        }
      } catch (_) {}
    }

    return _isSparsePackageRegisteredByRegQuery();
  }

  static bool isPackagedOrRegistered() {
    return isPackaged() || isSparsePackageRegistered();
  }

  static bool _isSparsePackageRegisteredByRegQuery() {
    final queries = <List<String>>[
      [
        'query',
        r'HKCU\Software\Classes\PackagedCom\Package',
        '/f',
        '${packageName}_',
        '/s',
      ],
      [
        'query',
        r'HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages',
        '/f',
        '${packageName}_',
        '/s',
      ],
    ];
    for (final args in queries) {
      try {
        final result = Process.runSync('reg', args);
        if (result.exitCode == 0) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }
}
