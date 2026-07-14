import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class WindowsShellNotify {
  static const int _shcneAssocChanged = 0x08000000;
  static const int _shcnfIdList = 0x0000;
  static const int _shcnfFlushNowait = 0x2000;

  static final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');

  static final void Function(
    int wEventId,
    int uFlags,
    Pointer<Void> dwItem1,
    Pointer<Void> dwItem2,
  )
  _shChangeNotify = _shell32
      .lookupFunction<
        Void Function(Int32, Uint32, Pointer<Void>, Pointer<Void>),
        void Function(int, int, Pointer<Void>, Pointer<Void>)
      >('SHChangeNotify');

  static void associationsChanged() {
    try {
      _shChangeNotify(
        _shcneAssocChanged,
        _shcnfIdList | _shcnfFlushNowait,
        nullptr,
        nullptr,
      );
    } catch (_) {
      const int smtoAbortIfHung = 0x0002;
      final resultPtr = calloc<IntPtr>();
      try {
        SendMessageTimeout(
          HWND_BROADCAST,
          WM_SETTINGCHANGE,
          0,
          0,
          smtoAbortIfHung,
          100,
          resultPtr,
        );
      } finally {
        calloc.free(resultPtr);
      }
    }
  }
}
