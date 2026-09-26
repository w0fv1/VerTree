import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/adapters/ui/desktop_theme.dart';
import 'package:vertree/view/component/home_actions.dart';

Finder action(String name) => find.byKey(ValueKey('home-$name'));

Future<void> showActions(
  WidgetTester tester, {
  List<String> labels = const ['监控', '设置', '退出'],
  double textScale = 1,
  double deviceScale = 1,
  double width = 600,
  bool dark = false,
  VoidCallback? onMonitor,
  VoidCallback? onSettings,
  VoidCallback? onExit,
}) async {
  tester.view.devicePixelRatio = deviceScale;
  tester.view.physicalSize = Size(width * deviceScale, 500 * deviceScale);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? buildDarkTheme() : buildLightTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: HomeActions(
            monitorLabel: labels[0],
            settingsLabel: labels[1],
            exitLabel: labels[2],
            onMonitor: onMonitor ?? () {},
            onSettings: onSettings ?? () {},
            onExit: onExit ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const languages = [
    ['监控', '设置', '退出'],
    ['Monitor', 'Settings', 'Exit'],
    ['モニター', '設定', '終了'],
  ];
  for (final labels in languages) {
    for (final textScale in [1.0, 1.5]) {
      testWidgets(
        '${labels[0]} scale $textScale: icon and label centered together',
        (tester) async {
          await showActions(
            tester,
            labels: labels,
            textScale: textScale,
            deviceScale: textScale == 1 ? 1.25 : 2,
          );
          final centerY = tester.getCenter(action('monitor')).dy;
          for (final name in ['monitor', 'settings']) {
            final bounds = tester.getRect(action(name));
            final icon = tester.getRect(action('$name-icon'));
            final label = tester.getRect(action('$name-label'));
            final group = icon.expandToInclude(label);
            final cjk = RegExp(
              r'[\u3040-\u30ff\u3400-\u9fff]',
            ).hasMatch(labels.first);
            // Line-box geometry deliberately differs from optical ink centre.
            // Actual YaHei ink is checked in home_actions_ink_test.dart.
            expect(icon.center.dy, closeTo(bounds.center.dy, 0.01));
            expect(
              label.center.dy,
              closeTo(bounds.center.dy - (cjk ? 1.25 : 0), 0.01),
            );
            expect(group.center.dx, closeTo(bounds.center.dx, 0.01));

            expect(bounds.center.dy, closeTo(centerY, 0.01));
            expect(
              group.left - bounds.left,
              closeTo(bounds.right - group.right, 0.01),
            );
            expect(label.left - icon.right, closeTo(6, 0.01));
          }
          expect(tester.getCenter(action('exit')).dy, closeTo(centerY, 0.01));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('compact default size is independent of window width and DPI', (
    tester,
  ) async {
    Size? initialSize;
    for (final width in [320.0, 600.0, 1600.0]) {
      for (final dpi in [1.0, 1.25, 1.5, 2.0]) {
        await showActions(tester, width: width, deviceScale: dpi);
        for (final name in ['monitor', 'settings']) {
          final bounds = tester.getRect(action(name));
          final group = tester
              .getRect(action('$name-icon'))
              .expandToInclude(tester.getRect(action('$name-label')));
          expect(bounds.height, closeTo(32, 0.01));
          expect(bounds.width, lessThan(96));
          expect(bounds.width - group.width, closeTo(32, 0.01));
          initialSize ??= bounds.size;
          expect(bounds.size, initialSize);
        }
        expect(tester.getSize(action('exit')), const Size.square(32));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
    'compact buttons still grow for accessibility text rather than clip',
    (tester) async {
      await showActions(tester, textScale: 3, width: 600);
      for (final name in ['monitor', 'settings']) {
        final button = tester.getRect(action(name));
        final label = tester.getRect(action('$name-label'));
        expect(button.height, greaterThan(32));
        expect(label.top, greaterThanOrEqualTo(button.top + 2.5));
        expect(label.bottom, lessThanOrEqualTo(button.bottom - 4));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('exit is icon only, no outline or fill, tooltip is retained', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await showActions(tester, dark: dark);
      final exit = tester.widget<IconButton>(action('exit'));
      expect(exit.tooltip, '退出');
      expect(find.text('退出'), findsNothing);
      expect(find.byTooltip('退出'), findsOneWidget);
      expect(tester.getSize(action('exit')), const Size.square(32));
      for (final states in <Set<WidgetState>>[
        {},
        {WidgetState.hovered},
        {WidgetState.focused},
        {WidgetState.pressed},
      ]) {
        expect(exit.style!.side!.resolve(states), BorderSide.none);
        expect(
          exit.style!.backgroundColor!.resolve(states),
          Colors.transparent,
        );
      }
      final icon = find.descendant(
        of: action('exit'),
        matching: find.byIcon(Icons.exit_to_app_rounded),
      );
      expect(tester.getCenter(icon), tester.getCenter(action('exit')));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('all actions invoke only their own callback', (tester) async {
    final calls = <String>[];
    await showActions(
      tester,
      onMonitor: () => calls.add('monitor'),
      onSettings: () => calls.add('settings'),
      onExit: () => calls.add('exit'),
    );
    expect(calls, isEmpty);
    for (final name in ['monitor', 'settings', 'exit']) {
      await tester.tap(action(name));
      await tester.pumpAndSettle();
    }
    expect(calls, ['monitor', 'settings', 'exit']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text wraps without clipping in a narrow window', (
    tester,
  ) async {
    await showActions(tester, width: 260, textScale: 2);
    for (final name in ['monitor', 'settings', 'exit']) {
      final bounds = tester.getRect(action(name));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(260));
      expect(bounds.height, greaterThanOrEqualTo(32));
    }
    expect(tester.takeException(), isNull);
  });
}
