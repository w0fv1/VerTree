import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:vertree/main.dart';

class FileUtils {
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
        logger.error("文件夹不存在: $normalizedPath");
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
      logger.error("打开文件夹失败: $e");
    }
  }

  static void openFile(String filePath) {
    try {
      String normalizedPath = _normalizePath(filePath);

      if (!File(normalizedPath).existsSync()) {
        logger.error("文件不存在: $normalizedPath");
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
      logger.error("打开文件失败: $e");
    }
  }
}
