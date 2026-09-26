import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/component/app_cli.dart';
import 'package:vertree/file_access/infrastructure/windows_file_worker.dart';
import 'package:vertree/foundation/operation_control.dart';
import 'package:vertree/platform/windows_menu_model.dart';

void main() {
  test(
    'file-tools CLI handles multi-file, folder and Explorer manifest routes',
    () {
      final multi = parseAppCliArgs([
        'fast-delete',
        r'C:\fixture\one',
        r'C:\fixture\folder',
      ]);
      expect(multi?.action, AppCliAction.fastDelete);
      expect(multi?.paths, [r'C:\fixture\one', r'C:\fixture\folder']);
      final explorer = parseAppCliArgs([
        '--menu',
        'unlock',
        '--selection-file',
        r'C:\temp\selection.json',
      ]);
      expect(explorer?.action, AppCliAction.fileUsage);
      expect(explorer?.selectionFile, r'C:\temp\selection.json');
      expect(parseAppCliArgs(['file-tools'])?.isFileTools, isTrue);
      expect(parseAppCliArgs(['fast-delete']), isNull);
      expect(parseAppCliArgs(['fast-delete', '--unexpected']), isNull);
      expect(
        parseAppCliArgs(['backup', r'C:\fixture\file'])?.action,
        AppCliAction.backup,
      );
    },
  );
  test(
    'file tools have distinct Explorer COM handlers; legacy verbs do not',
    () {
      expect(WindowsMenuAction.fileUsage.explorerCommandClsid, isNotNull);
      expect(
        WindowsMenuAction.fastDelete.explorerCommandClsid,
        isNot(WindowsMenuAction.fileUsage.explorerCommandClsid),
      );
      expect(WindowsMenuAction.preview.explorerCommandClsid, isNull);
      expect(
        WindowsMenuAction.values.where((item) => item.isFileTool).length,
        2,
      );
    },
  );
  test('shared device budget serializes jobs on the same disk', () async {
    final worker = WindowsFileWorker(executable: 'not-started-in-this-test');
    final firstControl = OperationControl(), secondControl = OperationControl();
    final entered = Completer<void>(), release = Completer<void>();
    var secondStarted = false;
    final first = worker.withDeviceBudget(['disk:0'], 4, firstControl, (
      count,
    ) async {
      expect(count, 4);
      entered.complete();
      await release.future;
    });
    await entered.future;
    final second = worker.withDeviceBudget(['disk:0'], 4, secondControl, (
      _,
    ) async {
      secondStarted = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(secondStarted, isFalse);
    release.complete();
    await first;
    await second;
    expect(secondStarted, isTrue);
    await firstControl.dispose();
    await secondControl.dispose();
    await worker.dispose();
  });
  test('device budget does not launch a cancelled queued operation', () async {
    final worker = WindowsFileWorker(executable: 'not-started-in-this-test');
    final firstControl = OperationControl(), secondControl = OperationControl();
    final entered = Completer<void>(), release = Completer<void>();
    final first = worker.withDeviceBudget(['disk:0'], 8, firstControl, (
      _,
    ) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final second = worker.withDeviceBudget(
      ['disk:1'],
      8,
      secondControl,
      (_) async => fail('Cancelled work was started'),
    );
    final assertion = expectLater(second, throwsA(isA<OperationCancelled>()));
    secondControl.cancel();
    await assertion;
    release.complete();
    await first;
    await firstControl.dispose();
    await secondControl.dispose();
    await worker.dispose();
  });
}
