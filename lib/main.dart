import 'dart:io';

import 'package:vertree/app/desktop_app.dart';
import 'package:vertree/platform/bootstrap/linux_bootstrap.dart';
import 'package:vertree/platform/bootstrap/macos_bootstrap.dart';
import 'package:vertree/platform/bootstrap/windows_bootstrap.dart';

Future<void> main(List<String> args) async {
  if (Platform.isWindows) {
    await runVertreeApp(const WindowsBootstrap(), args);
    return;
  }

  if (Platform.isMacOS) {
    await runVertreeApp(const MacOSBootstrap(), args);
    return;
  }

  if (Platform.isLinux) {
    await runVertreeApp(LinuxBootstrap.currentSession(), args);
    return;
  }

  await runVertreeApp(LinuxBootstrap.currentSession(), args);
}
