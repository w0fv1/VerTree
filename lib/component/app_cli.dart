import 'package:vertree/component/app_launch_args.dart';

class AppCliRequest {
  const AppCliRequest({
    required this.action,
    required this.path,
    this.paths = const [],
    this.selectionFile,
  });
  final AppCliAction action;
  final String path;
  final List<String> paths;
  final String? selectionFile;
  bool get isFileTools =>
      action == AppCliAction.fileTools ||
      action == AppCliAction.fastDelete ||
      action == AppCliAction.fileUsage;
}

enum AppCliAction {
  preview,
  backup,
  expressBackup,
  monit,
  share,
  viewtree,
  fileTools,
  fastDelete,
  fileUsage;

  static AppCliAction? fromToken(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'preview':
      case '--preview':
        return AppCliAction.preview;
      case 'backup':
      case '--backup':
        return AppCliAction.backup;
      case 'express-backup':
      case 'express_backup':
      case '--express-backup':
        return AppCliAction.expressBackup;
      case 'monit':
      case 'monitor':
      case '--monit':
      case '--monitor':
        return AppCliAction.monit;
      case 'share':
      case '--share':
        return AppCliAction.share;
      case 'viewtree':
      case 'tree':
      case 'open':
      case '--viewtree':
        return AppCliAction.viewtree;
      case 'file-tools':
        return AppCliAction.fileTools;
      case 'fast-delete':
        return AppCliAction.fastDelete;
      case 'unlock':
      case 'file-usage':
        return AppCliAction.fileUsage;
    }
    return null;
  }
}

AppCliRequest? parseAppCliArgs(List<String> rawArgs) {
  final args = stripRuntimeLaunchArgs(rawArgs);
  if (args.isEmpty) return null;
  final toolArgs = _isInvocationSource(args.first)
      ? args.skip(1).toList()
      : args;
  if (toolArgs.isNotEmpty) {
    final action = AppCliAction.fromToken(toolArgs.first);
    if (action == AppCliAction.fileTools && toolArgs.length == 1) {
      return const AppCliRequest(action: AppCliAction.fileTools, path: '');
    }
    if (action == AppCliAction.fastDelete || action == AppCliAction.fileUsage) {
      if (toolArgs.length == 3 && toolArgs[1] == '--selection-file') {
        return AppCliRequest(
          action: action!,
          path: '',
          selectionFile: toolArgs[2],
        );
      }
      if (toolArgs.length >= 2 &&
          toolArgs.length <= 1025 &&
          !toolArgs.skip(1).any((value) => value.startsWith('--'))) {
        return AppCliRequest(
          action: action!,
          path: toolArgs[1],
          paths: List.unmodifiable(toolArgs.skip(1)),
        );
      }
      return null;
    }
  }
  if (args.length == 1 &&
      !args.first.startsWith('-') &&
      AppCliAction.fromToken(args.first) == null) {
    return AppCliRequest(action: AppCliAction.viewtree, path: args.first);
  }
  if (args.length == 2) {
    final action = AppCliAction.fromToken(args.first);
    if (action != null && action != AppCliAction.fileTools) {
      return AppCliRequest(action: action, path: args.last);
    }
  }
  if (args.length == 3 && _isInvocationSource(args.first)) {
    final action = AppCliAction.fromToken(args[1]);
    if (action != null && action != AppCliAction.fileTools) {
      return AppCliRequest(action: action, path: args.last);
    }
  }
  return null;
}

bool _isInvocationSource(String value) =>
    value == '--menu' || value == '--service';
