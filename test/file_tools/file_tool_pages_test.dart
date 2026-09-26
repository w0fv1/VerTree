import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/adapters/ui/file_tools_controller.dart';
import 'package:vertree/file_access/file_access.dart';
import 'package:vertree/foundation/app_events.dart';
import 'package:vertree/foundation/operation_control.dart';
import 'package:vertree/modules/automation/automation.dart';
import 'package:vertree/modules/deletion/deletion.dart';
import 'package:vertree/modules/file_locks/file_locks.dart';
import 'package:vertree/view/component/file_tool_widgets.dart';
import 'package:vertree/view/page/delete_page.dart';
import 'package:vertree/view/page/file_locks_page.dart';

import 'deletion_commands_test.dart' show fixturePlan, TestUsage;

String english(String zh, String en) => en;

class PageDeletionBackend implements DeletionBackend {
  int prepares = 0;
  final options = <DeletionOptions>[];
  @override
  Future<DeletionPlan> prepare(List<String> paths) async {
    prepares++;
    return fixturePlan();
  }

  @override
  Future<List<Map<String, dynamic>>> history() async =>
      throw StateError('UI must not load task history');
  @override
  Future<DeletionResult> execute(
    DeletionPlan plan,
    DeletionOptions value,
    OperationControl control,
    void Function(DeletionProgress) onProgress, {
    String? retryReport,
  }) async {
    options.add(value);
    return DeletionResult(
      outcome: 'succeeded',
      plan: plan,
      progress: DeletionProgress({'deletedFiles': 2, 'deletedDirectories': 1}),
    );
  }
}

class PageLockBackend implements FileLockBackend {
  int scans = 0;
  final ended = <int>[];
  @override
  Future<FileUsageSnapshot> scan(
    List<String> paths,
    OperationControl control,
    void Function(Map<String, dynamic>) onProgress, {
    bool elevated = false,
  }) async {
    scans++;
    return FileUsageSnapshot(
      complete: true,
      processes: [
        if (!ended.contains(100))
          FileUsageProcess({
            'pid': 100,
            'creationTime': '0000000000000001',
            'name': 'fixture-editor.exe',
            'imagePath': r'C:\fixture\editor.exe',
            'user': 'test-user',
            'actionAllowed': true,
            'files': [
              {
                'path': paths.first,
                'sources': ['handle'],
              },
            ],
          }),
        FileUsageProcess({
          'pid': 200,
          'creationTime': '0000000000000002',
          'name': 'protected-fixture.exe',
          'actionAllowed': false,
          'restriction': 'PROTECTED_PROCESS',
          'files': [],
        }),
      ],
    );
  }

  @override
  Future<Map<String, dynamic>> act(
    List<String> paths,
    FileUsageProcess process,
    FileProcessAction action,
    OperationControl control, {
    required bool confirmed,
    bool elevated = false,
  }) async {
    expect(confirmed, isTrue);
    expect(action, FileProcessAction.terminate);
    ended.add(process.pid);
    return {'status': 'exited', 'pid': process.pid};
  }
}

void main() {
  late AppEvents events;
  late AutomationJobs jobs;
  late FileMutationCoordinator writes;
  late PageDeletionBackend deletion;
  late PageLockBackend locks;
  late FileToolsController tools;
  void initialize() {
    events = AppEvents();
    jobs = AutomationJobs(events);
    writes = FileMutationCoordinator();
    deletion = PageDeletionBackend();
    locks = PageLockBackend();
    tools = FileToolsController(
      deletion: DeletionCommands(
        backend: deletion,
        writes: writes,
        usage: TestUsage(),
      ),
      locks: FileLockCommands(locks),
      jobs: jobs,
      events: events,
    );
  }

  void pageTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      initialize();
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        // The widget assertions run with a fake clock. Drain application-level
        // stream/job resources on the real async runner after removing the UI.
        await tester.runAsync(() async {
          await tools.shutdown();
          await jobs.dispose();
          await writes.close();
          await events.dispose();
        });
        expect(tester.takeException(), isNull);
      }
    });
  }

  Future<void> show(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1000, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  pageTest(
    'delete page has one clickable picker card, one bolt action and no advanced panels',
    (tester) async {
      await show(tester, DeletePane(controller: tools, text: english));
      expect(find.byKey(const ValueKey('pick-targets-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-files')), findsNothing);
      expect(find.byKey(const ValueKey('pick-folder')), findsNothing);
      expect(find.byKey(const ValueKey('delete-selection')), findsOneWidget);
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.textContaining('history'), findsNothing);
      expect(find.textContaining('session'), findsNothing);
      expect(find.byType(FileUsageProcessTile), findsNothing);
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('delete-selection')),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  pageTest(
    'one confirmation authorizes lightning defaults; cancelling changes nothing',
    (tester) async {
      await show(
        tester,
        DeletePane(
          controller: tools,
          text: english,
          initialPaths: const [r'C:\fixture\tree'],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('delete-selection')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(deletion.options, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deletion.options, isEmpty);
      await tester.tap(find.byKey(const ValueKey('delete-selection')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-delete')));
      await tester.pumpAndSettle();
      expect(deletion.options.length, 1);
      expect(deletion.options.single.removeReadOnly, isTrue);
      expect(deletion.options.single.resolveBlockers, isTrue);
      expect(deletion.options.single.workers, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Deletion complete'), findsOneWidget);
      expect(locks.ended, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  pageTest('Shell delete opens one confirmation without starting work', (
    tester,
  ) async {
    await show(
      tester,
      DeletePane(
        controller: tools,
        text: english,
        initialPaths: const [r'C:\fixture\tree'],
        confirmOnOpen: true,
      ),
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(deletion.options, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  pageTest(
    'locks page has File Locksmith rows with end task and collapsible details',
    (tester) async {
      await show(
        tester,
        FileLocksPane(
          controller: tools,
          text: english,
          initialPaths: const [r'C:\fixture\file.txt'],
        ),
      );
      expect(find.byKey(const ValueKey('refresh-usage')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-scan')), findsOneWidget);
      expect(find.byType(FileUsageProcessTile), findsNWidgets(2));
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const ValueKey('delete-selection')), findsNothing);
      expect(find.text(r'C:\fixture\editor.exe'), findsNothing);
      await tester.tap(find.byTooltip('Show details').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('PID  100'), findsOneWidget);
      expect(find.textContaining(r'C:\fixture\editor.exe'), findsOneWidget);
      final protected = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('end-process-200')),
      );
      expect(protected.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  pageTest('ending one process refreshes the list and never deletes files', (
    tester,
  ) async {
    await show(
      tester,
      FileLocksPane(
        controller: tools,
        text: english,
        initialPaths: const [r'C:\fixture\file.txt'],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('end-process-100')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(locks.ended, isEmpty);
    await tester.tap(find.byKey(const ValueKey('end-process-100')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'End task'));
    await tester.pumpAndSettle();
    expect(locks.ended, [100]);
    expect(find.text('fixture-editor.exe'), findsNothing);
    expect(find.text('protected-fixture.exe'), findsOneWidget);
    expect(deletion.prepares, 0);
    expect(deletion.options, isEmpty);
    expect(tester.takeException(), isNull);
  });

  pageTest('separate pages fit a compact desktop viewport', (tester) async {
    await show(
      tester,
      DeletePane(
        controller: tools,
        text: english,
        initialPaths: const [r'C:\fixture\tree'],
      ),
      size: const Size(600, 640),
    );
    await tester.tap(find.byKey(const ValueKey('delete-selection')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileLocksPane(
            controller: tools,
            text: english,
            initialPaths: const [r'C:\fixture\file.txt'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
