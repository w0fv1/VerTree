import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/adapters/ui/desktop_theme.dart';
import 'package:vertree/component/brand_slogans.dart';
import 'package:vertree/view/component/home_actions.dart';
import 'package:vertree/view/component/responsive_home_card.dart';

Future<void> showCard(
  WidgetTester tester, {
  double width = 600,
  double height = 560,
  String slogan = '让每一次迭代都有迹可循',
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: ResponsiveHomeCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 240,
                height: 180,
                child: Icon(Icons.account_tree, size: 100),
              ),
              const SizedBox(height: 12),
              const Text('Vertree维树'),
              const SizedBox(height: 10),
              Text(slogan, textAlign: TextAlign.center),
              const SizedBox(height: ResponsiveHomeCard.brandActionsSpacing),
              HomeActions(
                monitorLabel: '监控',
                settingsLabel: '设置',
                exitLabel: '退出',
                onMonitor: () {},
                onSettings: () {},
                onExit: () {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('proportion, minimum and maximum respect available space', () {
    expect(ResponsiveHomeCard.widthFor(600), closeTo(419.52, 0.01));
    expect(ResponsiveHomeCard.widthFor(480), 360);
    expect(ResponsiveHomeCard.widthFor(1400), 640);
    expect(ResponsiveHomeCard.widthFor(320), 272);
    expect(ResponsiveHomeCard.widthFor(32), 0);
  });
  for (final width in [280.0, 360.0, 480.0, 600.0, 800.0, 1280.0]) {
    testWidgets('card at $width is centered and never overflows', (
      tester,
    ) async {
      await showCard(tester, width: width);
      final card = tester.getRect(find.byKey(const ValueKey('home-card')));
      expect(card.width, closeTo(ResponsiveHomeCard.widthFor(width), 0.01));
      expect(card.center.dx, closeTo(width / 2, 0.01));
      expect(card.left, greaterThanOrEqualTo(24));
      expect(card.right, lessThanOrEqualTo(width - 24));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('all ten slogans keep card width and compact buttons', (
    tester,
  ) async {
    for (final slogan in BrandSlogans.zhCn) {
      await showCard(tester, slogan: slogan);
      expect(
        tester.getSize(find.byKey(const ValueKey('home-card'))).width,
        closeTo(419.52, 0.01),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('home-monitor'))).height,
        32,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('home-settings'))).height,
        32,
      );
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('brand and actions keep a 40px gap without enlarging buttons', (
    tester,
  ) async {
    for (final width in [360.0, 600.0, 900.0]) {
      await showCard(tester, width: width);
      final slogan = tester.getRect(find.text('让每一次迭代都有迹可循'));
      final actions = tester.getRect(find.byType(HomeActions));
      expect(actions.top - slogan.bottom, closeTo(40, 0.01));
      for (final name in ['monitor', 'settings', 'exit']) {
        expect(tester.getSize(find.byKey(ValueKey('home-$name'))).height, 32);
      }
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('short windows and enlarged text scroll instead of clipping', (
    tester,
  ) async {
    await showCard(tester, width: 360, height: 260, textScale: 2);
    await tester.ensureVisible(find.byKey(const ValueKey('home-exit')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(const ValueKey('home-exit'))).bottom,
      lessThanOrEqualTo(260),
    );
  });
}
