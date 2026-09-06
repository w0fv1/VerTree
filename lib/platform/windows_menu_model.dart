enum WindowsMenuAction {
  preview('RegistryVerTreePreview', 'preview', 'logo/logo.ico'),
  backup('RegistryVerTreeBackup', 'backup', 'icon/save.ico', '备份文件 VerTree'),
  expressBackup(
    'RegistryVerTreeExpressBackup',
    'express-backup',
    'icon/express-save.ico',
    '快速备份文件 VerTree',
  ),
  monitor(
    'RegistryVerTreeMonitor',
    'monit',
    'icon/monit.ico',
    '监控文件变动 VerTree',
  ),
  share('RegistryVerTreeShare', 'share', 'icon/share.ico'),
  viewTree(
    'RegistryVerTreeViewTree',
    'viewtree',
    'logo/logo.ico',
    '查看文件版本树 VerTree',
  );

  const WindowsMenuAction(
    this.keyName,
    this.verb,
    this.icon, [
    this.legacyKeyName,
  ]);
  final String keyName;
  final String verb;
  final String icon;
  final String? legacyKeyName;
}

class WindowsMenuEntry {
  const WindowsMenuEntry(this.key, {this.action});
  final String key;
  final WindowsMenuAction? action;
  bool get isSubmenu => action == null;
}

/// A declarative plan shared by setup, item toggles, layout changes and refresh.
class WindowsMenuPlan {
  static const rootKey = 'RegistryVerTreeLegacyRoot';
  static List<String> get obsoleteKeys => WindowsMenuAction.values
      .map((action) => action.legacyKeyName)
      .nonNulls
      .toList();
  static List<String> get topLevelKeys => [
    rootKey,
    ...WindowsMenuAction.values.map((a) => a.keyName),
    ...obsoleteKeys,
  ];

  WindowsMenuPlan(Set<WindowsMenuAction> selected, {required bool collapsed}) {
    entries = [
      if (collapsed && selected.isNotEmpty) const WindowsMenuEntry(rootKey),
      for (final action in WindowsMenuAction.values)
        if (selected.contains(action))
          WindowsMenuEntry(
            collapsed ? '$rootKey\\shell\\${action.keyName}' : action.keyName,
            action: action,
          ),
    ];
    final desired = entries.map((entry) => entry.key).toSet();
    removals = [
      for (final key in topLevelKeys)
        if (!desired.contains(key)) key,
      if (collapsed && selected.isNotEmpty)
        for (final action in WindowsMenuAction.values)
          if (!selected.contains(action)) '$rootKey\\shell\\${action.keyName}',
    ];
  }

  late final List<WindowsMenuEntry> entries;
  late final List<String> removals;

  bool apply({
    required bool Function(WindowsMenuEntry) write,
    required bool Function(String) remove,
  }) {
    // Do not remove the working layout if preparing its replacement fails.
    for (final entry in entries) {
      if (!write(entry)) return false;
    }
    var success = true;
    for (final key in removals) {
      success = remove(key) && success;
    }
    return success;
  }

  static Set<WindowsMenuAction> migrateSelection(
    Iterable<WindowsMenuAction> registered,
  ) {
    final selected = registered.toSet();
    if (selected.isNotEmpty) selected.add(WindowsMenuAction.preview);
    return selected;
  }
}
