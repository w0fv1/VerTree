import 'dart:io';

import 'package:test/test.dart';
import 'package:vertree/component/app_command_handler.dart';

void main() {
  late Directory directory;
  late AppCommandHandler handler;
  late List<String> previews;
  late List<String> otherActions;
  late List<String> errors;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('vertree-command-test-');
    previews = [];
    otherActions = [];
    errors = [];
    handler = AppCommandHandler(
      onPreview: previews.add,
      onBackup: otherActions.add,
      onExpressBackup: otherActions.add,
      onMonit: otherActions.add,
      onShare: otherActions.add,
      onViewTree: otherActions.add,
      onNotify: (_, _) {},
      onLogInfo: (_) {},
      onLogError: errors.add,
    );
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('Explorer and CLI preview invocations open only the requested file', () {
    final file = File('${directory.path}/预览 测试 & report.docx')
      ..writeAsStringSync('sample');
    for (final args in [
      ['preview', file.path],
      ['--menu', 'preview', file.path],
      ['--preview', file.path],
    ]) {
      handler.process(args);
    }
    expect(previews, [file.path, file.path, file.path]);
    expect(otherActions, isEmpty);
    expect(errors, isEmpty);
    expect(file.readAsStringSync(), 'sample');
  });

  test('missing files and directories do not open a preview', () {
    handler.process(['preview', '${directory.path}/missing.docx']);
    handler.process(['preview', directory.path]);
    expect(previews, isEmpty);
    expect(otherActions, isEmpty);
    expect(errors, hasLength(2));
  });

  test('existing path-only invocation still opens the version tree', () {
    final file = File('${directory.path}/existing.txt')..writeAsStringSync('');
    handler.process([file.path]);
    expect(otherActions, [file.path]);
    expect(previews, isEmpty);
  });
}
