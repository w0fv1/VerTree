import 'dart:io';

import 'package:vertree/component/app_launch_args.dart';
import 'package:vertree/component/app_cli.dart';

typedef FileActionCallback = void Function(String path);
typedef UserNotificationCallback = void Function(String title, String body);

class AppCommandHandler {
  const AppCommandHandler({
    required this.onBackup,
    required this.onExpressBackup,
    required this.onMonit,
    required this.onShare,
    required this.onViewTree,
    required this.onNotify,
    required this.onLogInfo,
    required this.onLogError,
  });

  final FileActionCallback onBackup;
  final FileActionCallback onExpressBackup;
  final FileActionCallback onMonit;
  final FileActionCallback onShare;
  final FileActionCallback onViewTree;
  final UserNotificationCallback onNotify;
  final void Function(String message) onLogInfo;
  final void Function(String message) onLogError;

  bool isActionable(List<String> args) => parseAppCliArgs(args) != null;

  void process(List<String> args) {
    try {
      final request = parseAppCliArgs(args);
      if (request == null) {
        if (containsStartupLaunchArg(args) &&
            stripRuntimeLaunchArgs(args).isEmpty) {
          return;
        }
        onLogInfo("不需要处理的参数：$args");
        return;
      }

      final path = request.path;
      final entity = FileSystemEntity.typeSync(path);
      if (entity == FileSystemEntityType.notFound) {
        onLogError("传入的 path 不存在: $path");
        onNotify("发生错误", "传入的 path 不存在: $path");
        return;
      }
      if (entity == FileSystemEntityType.directory) {
        onLogError("传入的 path 是一个文件夹，不对文件夹进行处理: $path");
        return;
      }

      switch (request.action) {
        case AppCliAction.backup:
          onBackup(path);
          break;
        case AppCliAction.expressBackup:
          onExpressBackup(path);
          break;
        case AppCliAction.monit:
          onMonit(path);
          break;
        case AppCliAction.share:
          onShare(path);
          break;
        case AppCliAction.viewtree:
          onViewTree(path);
          break;
      }
    } catch (e) {
      onLogError('Vertree处理参数失败: $e');
    }
  }
}
