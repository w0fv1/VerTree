import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toastification/toastification.dart';
import 'package:vertree/component/notifier.dart';

void main() {
  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    const ToastificationWrapper(child: MaterialApp(home: Scaffold())),
  );
  tearDown(() => toastification.dismissAll(delayForAnimation: false));

  testWidgets('toast expires while the mouse remains over it', (tester) async {
    await mount(tester);
    showToast('Preparing');
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('Preparing')));
    await mouse.moveTo(tester.getCenter(find.text('Preparing')));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Preparing'), findsNothing);
    await mouse.removePointer();
  });

  for (final fails in [false, true]) {
    testWidgets(
      'task completion (fails=$fails) removes only its progress notice',
      (tester) async {
        await mount(tester);
        final task = Completer<int>();
        final result = withProgressToast('Preparing', () => task.future);
        final assertion = expectLater(
          result,
          fails ? throwsStateError : completion(42),
        );
        showToast('Unrelated');
        await tester.pumpAndSettle();
        expect(find.text('Preparing'), findsOneWidget);
        if (fails) {
          task.completeError(StateError('Share failed'));
        } else {
          task.complete(42);
        }
        await assertion;
        await tester.pumpAndSettle();
        expect(find.text('Preparing'), findsNothing);
        expect(find.text('Unrelated'), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'immediate completion cannot leave a toast queued for insertion',
    (tester) async {
      await mount(tester);
      expect(await withProgressToast('Preparing', () async => 42), 42);
      await tester.pumpAndSettle();
      expect(find.text('Preparing'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    },
  );
}
