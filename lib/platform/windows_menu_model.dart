enum WindowsMenuAction {
  preview('RegistryVerTreePreview', 'preview', 'icon/preview.ico'),
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
  ),
  fileUsage('RegistryVerTreeFileUsage', 'unlock', 'logo/logo.ico'),
  fastDelete('RegistryVerTreeFastDelete', 'fast-delete', 'logo/logo.ico');

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
  bool get isFileTool => this == fileUsage || this == fastDelete;
  String? get explorerCommandClsid => switch (this) {
    fileUsage => '{D6F4258B-C42C-487A-ABCE-94A6BE01D6B1}',
    fastDelete => '{1C501413-5FC4-4E07-B132-790198D45724}',
    _ => null,
  };
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
}

/// Modern Explorer menu selection in settings.json. Missing values use the
/// current default; an explicit empty selection stays empty. No legacy import.
class Windows11MenuPreferences {
  static const selectionKey = 'windows11MenuActions';
  Windows11MenuPreferences(Iterable<WindowsMenuAction> actions)
    : actions = Set.unmodifiable(actions);
  final Set<WindowsMenuAction> actions;

  factory Windows11MenuPreferences.fromConfig(Map<String, dynamic> config) {
    if (!config.containsKey(selectionKey)) {
      return Windows11MenuPreferences(WindowsMenuAction.values);
    }
    final saved = config[selectionKey];
    return Windows11MenuPreferences(
      saved is List
          ? WindowsMenuAction.values.where(
              (action) => saved.contains(action.name),
            )
          : const <WindowsMenuAction>[],
    );
  }

  Windows11MenuPreferences withAction(WindowsMenuAction action, bool enabled) {
    final next = Set<WindowsMenuAction>.of(actions);
    if (enabled) {
      next.add(action);
    } else {
      next.remove(action);
    }
    return Windows11MenuPreferences(next);
  }

  List<String> toNames() => [
    for (final action in WindowsMenuAction.values)
      if (actions.contains(action)) action.name,
  ];
}
