import 'package:flutter/material.dart';

import '../../component/i18n_lang.dart';
import '../../component/action_icons.dart';
import '../../platform/windows_menu_model.dart';
import 'settings_row.dart';

/// The same legacy-style rows for both context-menu generations. Selection and
/// persistence stay with the caller; this widget never changes the other group.
class ContextMenuChoices extends StatelessWidget {
  const ContextMenuChoices({
    super.key,
    required this.group,
    required this.selected,
    required this.locale,
    required this.onChanged,
    this.enabled = true,
    this.actions = legacyOrder,
  });

  static const legacyOrder = WindowsMenuAction.values;

  final String group;
  final Set<WindowsMenuAction> selected;
  final AppLocale locale;
  final void Function(WindowsMenuAction action, bool enabled) onChanged;
  final bool enabled;
  final Iterable<WindowsMenuAction> actions;

  String _label(WindowsMenuAction action) => switch (action) {
    WindowsMenuAction.preview => locale.getText(
      LocaleKey.settingAddPreviewMenu,
    ),
    WindowsMenuAction.backup => locale.getText(LocaleKey.settingAddBackupMenu),
    WindowsMenuAction.monitor => locale.getText(
      LocaleKey.settingAddMonitorMenu,
    ),
    WindowsMenuAction.share => locale.getText(LocaleKey.settingAddShareMenu),
    WindowsMenuAction.viewTree => locale.getText(
      LocaleKey.settingAddViewtreeMenu,
    ),
    WindowsMenuAction.fileUsage => switch (locale.lang) {
      Lang.en => 'Inspect / release file usage',
      Lang.ja => 'ファイルの使用状況を確認',
      _ => '查看／解除文件占用',
    },
    WindowsMenuAction.fastDelete => switch (locale.lang) {
      Lang.en => 'Fast delete (permanent)…',
      Lang.ja => '高速削除（完全削除）…',
      _ => '快速删除（永久）…',
    },
    WindowsMenuAction.conversion => switch (locale.lang) {
      Lang.en => 'Convert format',
      Lang.ja => '形式を変換',
      _ => '转换格式',
    },
  };

  IconData _icon(WindowsMenuAction action) => switch (action) {
    WindowsMenuAction.preview => AppActionIcon.preview.data,
    WindowsMenuAction.fileUsage => AppActionIcon.fileUsage.data,
    WindowsMenuAction.fastDelete => AppActionIcon.fastDelete.data,
    WindowsMenuAction.conversion => AppActionIcon.conversion.data,
    WindowsMenuAction.backup => AppActionIcon.backup.data,
    WindowsMenuAction.monitor => AppActionIcon.monitor.data,
    WindowsMenuAction.share => AppActionIcon.share.data,
    WindowsMenuAction.viewTree => AppActionIcon.viewTree.data,
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final action in actions)
        SettingsSwitchTile(
          key: ValueKey('$group-action-${action.name}'),
          icon: _icon(action),
          title: _label(action),
          value: selected.contains(action),
          onChanged: enabled ? (value) => onChanged(action, value) : null,
        ),
    ],
  );
}
