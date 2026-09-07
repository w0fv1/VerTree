import 'dart:io';

import 'package:win32/win32.dart' as win32;

/// Call only after application-owned shutdown work has completed.
Never exitAfterCleanup() {
  if (Platform.isWindows) {
    // Both runner teardown and CRT/DLL detach have produced native exceptions
    // on exit. End this process without re-entering those plugin finalizers.
    // This is a self-process handle; no other application is affected.
    win32.TerminateProcess(win32.GetCurrentProcess(), 0);
  }
  exit(0);
}
