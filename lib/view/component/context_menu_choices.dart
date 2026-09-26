import 'package:flutter/material.dart';
import '../../component/i18n_lang.dart';
import '../../component/themed_assets.dart';
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

  static const legacyOrder = [
    WindowsMenuAction.preview,
    WindowsMenuAction.fileUsage,
    WindowsMenuAction.fastDelete,
    WindowsMenuAction.backup,
    WindowsMenuAction.expressBackup,
    WindowsMenuAction.monitor,
    WindowsMenuAction.share,
    WindowsMenuAction.viewTree,
  ];

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
    WindowsMenuAction.expressBackup => locale.getText(
      LocaleKey.settingAddExpressBackupMenu,
    ),
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
  };

  IconData _icon(WindowsMenuAction action) => switch (action) {
    WindowsMenuAction.preview => Icons.visibility_outlined,
    WindowsMenuAction.fileUsage => Icons.manage_search,
    WindowsMenuAction.fastDelete => Icons.delete_forever_outlined,
    WindowsMenuAction.backup => Icons.save_outlined,
    WindowsMenuAction.expressBackup => Icons.flash_on_outlined,
    WindowsMenuAction.monitor => Icons.monitor_heart_outlined,
    WindowsMenuAction.share => Icons.share_outlined,
    WindowsMenuAction.viewTree => Icons.account_tree_outlined,
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final action in actions)
        SettingsSwitchTile(
          key: ValueKey('$group-action-${action.name}'),
          icon: _icon(action),
          leading: action == WindowsMenuAction.share
              ? shareActionImage(size: 20)
              : null,
          title: _label(action),
          value: selected.contains(action),
          onChanged: enabled ? (value) => onChanged(action, value) : null,
        ),
    ],
  );
}
