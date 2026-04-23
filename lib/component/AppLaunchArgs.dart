const String startupLaunchArg = '--startup';
const String noAnnouncementLaunchArg = '--no-announcement';

bool containsStartupLaunchArg(Iterable<String> rawArgs) {
  return _containsLaunchArg(rawArgs, startupLaunchArg);
}

bool containsNoAnnouncementLaunchArg(Iterable<String> rawArgs) {
  return _containsLaunchArg(rawArgs, noAnnouncementLaunchArg);
}

List<String> stripRuntimeLaunchArgs(Iterable<String> rawArgs) {
  final args = <String>[];
  for (final rawArg in rawArgs) {
    final normalized = rawArg.trim();
    if (normalized.isEmpty) {
      continue;
    }
    final lowered = normalized.toLowerCase();
    if (lowered == startupLaunchArg || lowered == noAnnouncementLaunchArg) {
      continue;
    }
    args.add(normalized);
  }
  return args;
}

bool _containsLaunchArg(Iterable<String> rawArgs, String targetArg) {
  for (final rawArg in rawArgs) {
    if (rawArg.trim().toLowerCase() == targetArg) {
      return true;
    }
  }
  return false;
}

String buildWindowsLaunchCommand(
  String executablePath, {
  List<String> arguments = const [],
}) {
  final command = StringBuffer('"$executablePath"');
  for (final argument in arguments) {
    if (argument.isEmpty) {
      continue;
    }
    command.write(' ');
    command.write(_quoteWindowsArg(argument));
  }
  return command.toString();
}

String _quoteWindowsArg(String value) {
  final escaped = value.replaceAll('"', r'\"');
  if (escaped.contains(' ') ||
      escaped.contains('\t') ||
      escaped.contains('\n')) {
    return '"$escaped"';
  }
  return escaped;
}
