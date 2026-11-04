import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart:developer' as developer;

class FileUtils {
  static Future<void> revealFile(String path) async {
    final file = File(path).absolute;
    if (!await file.exists()) throw FileSystemException('文件不存在', file.path);
    final result = Platform.isWindows
        ? await Process.run('explorer.exe', [
            '/select,',
            p.normalize(file.path),
          ])
        : Platform.isMacOS
        ? await Process.run('open', ['-R', file.path])
        : await Process.run('xdg-open', [file.parent.path]);
    if (!Platform.isWindows && result.exitCode != 0) {
      throw FileSystemException('${result.stderr}'.trim(), file.path);
    }
  }

  static String appDirPath() {
    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;

    return p.normalize(exeDir);
  }

  static String _normalizePath(String path) {
    return p.normalize(path);
  }

  static void openFolder(String folderPath) {
    try {
      String normalizedPath = _normalizePath(folderPath);

      if (!Directory(normalizedPath).existsSync()) {
        developer.log("文件夹不存在: $normalizedPath");
        return;
      }

      if (Platform.isWindows) {
        Process.run('explorer.exe', [normalizedPath]);
      } else if (Platform.isMacOS) {
        Process.run('open', [normalizedPath]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [normalizedPath]);
      }
    } catch (e) {
      developer.log("打开文件夹失败: $e");
    }
  }

  static void openFile(String filePath) {
    try {
      String normalizedPath = _normalizePath(filePath);

      if (!File(normalizedPath).existsSync()) {
        developer.log("文件不存在: $normalizedPath");
        return;
      }

      if (Platform.isWindows) {
        Process.run('explorer.exe', [normalizedPath]);
      } else if (Platform.isMacOS) {
        Process.run('open', [normalizedPath]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [normalizedPath]);
      }
    } catch (e) {
      developer.log("打开文件失败: $e");
    }
  }
}
