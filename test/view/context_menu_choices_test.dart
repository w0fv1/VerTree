import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/platform/windows_menu_model.dart';
import 'package:vertree/view/component/context_menu_choices.dart';
import 'package:vertree/view/component/settings_row.dart';

Finder row(String group, WindowsMenuAction action) =>
    find.byKey(ValueKey('$group-action-${action.name}'));

Future<void> showChoices(
  WidgetTester tester, {
  Lang language = Lang.zhCn,
  double width = 600,
  double textScale = 1,
  bool modernEnabled = true,
  bool legacyEnabled = true,
  Set<WindowsMenuAction> modern = const {WindowsMenuAction.preview},
  Set<WindowsMenuAction> legacy = const {WindowsMenuAction.backup},
  void Function(String group, WindowsMenuAction action, bool value)? onChange,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final locale = AppLocale()..lang = language;
  var modernSelection = Set<WindowsMenuAction>.of(modern);
  var legacySelection = Set<WindowsMenuAction>.of(legacy);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            void change(String group, WindowsMenuAction action, bool value) {
              setState(() {
                final selected = group == 'win11'
                    ? modernSelection
                    : legacySelection;
                if (value) {
                  selected.add(action);
                } else {
                  selected.remove(action);
                }
              });
              onChange?.call(group, action, value);
            }

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ContextMenuChoices(
                    group: 'win11',
                    selected: modernSelection,
                    locale: locale,
                    enabled: modernEnabled,
                    onChanged: (action, value) =>
                        change('win11', action, value),
                  ),
                  ContextMenuChoices(
                    group: 'legacy',
                    selected: legacySelection,
                    locale: locale,
                    enabled: legacyEnabled,
                    onChanged: (action, value) =>
                        change('legacy', action, value),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('modern and legacy use identical original-style switch rows', (
    tester,
  ) async {
    await showChoices(tester);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(Switch), findsNWidgets(16));
    for (final action in ContextMenuChoices.legacyOrder) {
      final modern = tester.widget<SettingsSwitchTile>(row('win11', action));
      final legacy = tester.widget<SettingsSwitchTile>(row('legacy', action));
      expect(modern.title, legacy.title);
      expect(modern.icon, legacy.icon);
      expect(modern.leading.runtimeType, legacy.leading.runtimeType);
      expect(
        tester.getSize(row('win11', action)),
        tester.getSize(row('legacy', action)),
      );
      final content = find.descendant(
        of: row('win11', action),
        matching: find.byType(SettingsRow),
      );
      expect(tester.getSize(content).height, greaterThanOrEqualTo(56));
    }
    expect(
      tester
          .widget<SettingsSwitchTile>(row('win11', WindowsMenuAction.backup))
          .title,
      '将“备份该文件”增加到右键菜单',
    );
    expect(
      tester
          .widgetList<SettingsSwitchTile>(find.byType(SettingsSwitchTile))
          .take(8)
          .map((widget) => widget.key),
      ContextMenuChoices.legacyOrder.map(
        (action) => ValueKey('win11-action-${action.name}'),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('row tap and switch each toggle once and only their own group', (
    tester,
  ) async {
    final changes = <String>[];
    await showChoices(
      tester,
      onChange: (group, action, value) {
        changes.add('$group:${action.name}:$value');
      },
    );
    final modernBackup = row('win11', WindowsMenuAction.backup);
    await tester.tap(
      find.descendant(of: modernBackup, matching: find.byType(Text)),
    );
    await tester.pumpAndSettle();
    expect(changes, ['win11:backup:true']);
    expect(tester.widget<SettingsSwitchTile>(modernBackup).value, isTrue);
    final legacyPreview = row('legacy', WindowsMenuAction.preview);
    await tester.ensureVisible(legacyPreview);
    await tester.tap(
      find.descendant(of: legacyPreview, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();
    expect(changes, ['win11:backup:true', 'legacy:preview:true']);
    expect(tester.widget<SettingsSwitchTile>(legacyPreview).value, isTrue);
    expect(
      tester
          .widget<SettingsSwitchTile>(row('win11', WindowsMenuAction.preview))
          .value,
      isTrue,
    );
    final modernSwitch = find.descendant(
      of: modernBackup,
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(modernBackup);
    await tester.tap(modernSwitch);
    await tester.pumpAndSettle();
    expect(changes, [
      'win11:backup:true',
      'legacy:preview:true',
      'win11:backup:false',
    ]);
    expect(
      tester
          .widget<SettingsSwitchTile>(row('legacy', WindowsMenuAction.backup))
          .value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled group keeps selection and has no live row or switch', (
    tester,
  ) async {
    await showChoices(tester, modernEnabled: false);
    for (final action in ContextMenuChoices.legacyOrder) {
      expect(
        tester.widget<SettingsSwitchTile>(row('win11', action)).onChanged,
        isNull,
      );
      final ink = find.descendant(
        of: row('win11', action),
        matching: find.byType(InkWell),
      );
      expect(tester.widget<InkWell>(ink).onTap, isNull);
      expect(
        tester.widget<SettingsSwitchTile>(row('legacy', action)).onChanged,
        isNotNull,
      );
    }
    expect(
      tester
          .widget<SettingsSwitchTile>(row('win11', WindowsMenuAction.preview))
          .value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in [Lang.zhCn, Lang.en, Lang.ja]) {
    testWidgets('${language.name}: long legacy titles wrap without clipping', (
      tester,
    ) async {
      await showChoices(tester, language: language, width: 360, textScale: 2);
      for (final action in ContextMenuChoices.legacyOrder) {
        final modern = tester.widget<SettingsSwitchTile>(row('win11', action));
        final legacy = tester.widget<SettingsSwitchTile>(row('legacy', action));
        expect(modern.title, isNotEmpty);
        expect(modern.title, legacy.title);
        expect(
          tester.getSize(row('win11', action)),
          tester.getSize(row('legacy', action)),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('non-Windows action filter retains the existing five actions', (
    tester,
  ) async {
    final locale = AppLocale()..lang = Lang.zhCn;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextMenuChoices(
            group: 'legacy',
            selected: const {},
            locale: locale,
            onChanged: (_, _) {},
            actions: ContextMenuChoices.legacyOrder.where(
              (action) =>
                  action != WindowsMenuAction.preview && !action.isFileTool,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNWidgets(5));
    expect(row('legacy', WindowsMenuAction.fastDelete), findsNothing);
    expect(row('legacy', WindowsMenuAction.fileUsage), findsNothing);
    expect(row('legacy', WindowsMenuAction.preview), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
