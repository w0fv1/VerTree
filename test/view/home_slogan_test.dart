import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/adapters/ui/desktop_theme.dart';
import 'package:vertree/component/brand_slogans.dart';
import 'package:vertree/view/component/home_actions.dart';
import 'package:vertree/view/component/home_slogan.dart';

import '../component/brand_slogans_test.dart' show SlotRandom;

Future<void> showSlogan(
  WidgetTester tester,
  BrandSloganSession session, {
  String language = 'zhCn',
  bool dark = false,
  double width = 440,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HomeSlogan(session: session, language: language),
              const SizedBox(height: 24),
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
  testWidgets(
    'all ten Chinese slogans replace the old copy without resizing home buttons',
    (tester) async {
      double? firstHeight;
      for (var index = 0; index < 10; index++) {
        final session = BrandSloganSession(random: SlotRandom(index));
        await showSlogan(tester, session, width: 320);
        final slogan = find.byKey(const ValueKey('home-slogan'));
        expect(find.text(BrandSlogans.zhCn[index]), findsOneWidget);
        expect(find.textContaining('树状文件版本管理'), findsNothing);
        expect(find.textContaining('🌲'), findsNothing);
        expect(tester.widget<Text>(slogan).textAlign, TextAlign.center);
        expect(tester.getCenter(slogan).dx, closeTo(160, 0.01));
        final height = tester.getSize(slogan).height;
        firstHeight ??= height;
        expect(
          height,
          closeTo(firstHeight, 0.01),
          reason: 'All normal Chinese slogans fit on one line',
        );
        for (final action in ['monitor', 'settings', 'exit']) {
          expect(
            tester.getSize(find.byKey(ValueKey('home-$action'))).height,
            32,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'theme rebuild, navigation back and translation keep the startup choice',
    (tester) async {
      final random = SlotRandom(7);
      final session = BrandSloganSession(random: random);
      await showSlogan(tester, session);
      expect(find.text(BrandSlogans.zhCn[7]), findsOneWidget);
      await showSlogan(tester, session, dark: true);
      expect(find.text(BrandSlogans.zhCn[7]), findsOneWidget);
      // Dispose/recreate the presentation; the application-owned session survives.
      await tester.pumpWidget(const SizedBox.shrink());
      await showSlogan(tester, session);
      expect(find.text(BrandSlogans.zhCn[7]), findsOneWidget);
      for (final language in ['en', 'ja', 'zhCn']) {
        await showSlogan(tester, session, language: language);
        expect(
          find.text(BrandSlogans.forLanguage(language)[7]),
          findsOneWidget,
        );
      }
      expect(random.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'translated and enlarged copy wraps, without clipping or overflow',
    (tester) async {
      for (final language in ['zhCn', 'en', 'ja']) {
        for (var index = 0; index < 10; index++) {
          await showSlogan(
            tester,
            BrandSloganSession(random: SlotRandom(index)),
            language: language,
            width: 320,
            textScale: 2,
          );
          final slogan = find.byKey(const ValueKey('home-slogan'));
          final text = tester.widget<Text>(slogan);
          final bounds = tester.getRect(slogan);
          expect(text.maxLines, isNull);
          expect(text.overflow, isNull);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(320));
          expect(
            find.text(BrandSlogans.forLanguage(language)[index]),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
