import 'package:vertree/component/app_launch_args.dart';

class AppCliRequest {
  const AppCliRequest({required this.action, required this.path});

  final AppCliAction action;
  final String path;
}

enum AppCliAction {
  preview,
  backup,
  expressBackup,
  monit,
  share,
  viewtree;

  static AppCliAction? fromToken(String raw) {
    final token = raw.trim().toLowerCase();
    switch (token) {
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
    }
    return null;
  }
}

AppCliRequest? parseAppCliArgs(List<String> rawArgs) {
  if (rawArgs.isEmpty) {
    return null;
  }

  final args = stripRuntimeLaunchArgs(rawArgs);
  if (args.isEmpty) {
    return null;
  }

  if (args.length == 1 &&
      !_looksLikeOption(args.first) &&
      AppCliAction.fromToken(args.first) == null) {
    return AppCliRequest(action: AppCliAction.viewtree, path: args.first);
  }

  if (args.length == 2) {
    final action = AppCliAction.fromToken(args.first);
    if (action != null) {
      return AppCliRequest(action: action, path: args.last);
    }
  }

  if (args.length == 3 && _isInvocationSource(args.first)) {
    final action = AppCliAction.fromToken(args[1]);
    if (action != null) {
      return AppCliRequest(action: action, path: args.last);
    }
  }

  return null;
}

bool _looksLikeOption(String value) => value.startsWith('-');

bool _isInvocationSource(String value) {
  switch (value) {
    case '--menu':
    case '--service':
      return true;
  }
  return false;
}
