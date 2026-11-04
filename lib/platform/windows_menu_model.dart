enum WindowsMenuAction {
  preview('RegistryVerTreePreview', 'preview'),
  viewTree('RegistryVerTreeViewTree', 'viewtree', '查看文件版本树 VerTree'),
  backup('RegistryVerTreeBackup', 'express-backup', '备份文件 VerTree'),
  monitor('RegistryVerTreeMonitor', 'monit', '监控文件变动 VerTree'),
  share('RegistryVerTreeShare', 'share'),
  conversion('RegistryVerTreeConversion', 'conversion'),
  fileUsage('RegistryVerTreeFileUsage', 'unlock'),
  fastDelete('RegistryVerTreeFastDelete', 'fast-delete');

  const WindowsMenuAction(this.keyName, this.verb, [this.legacyKeyName]);
  final String keyName;
  final String verb;
  String get icon => 'icon/action-$name.ico';
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
  static List<String> get obsoleteKeys => [
    'RegistryVerTreeExpressBackup',
    '快速备份文件 VerTree',
    ...WindowsMenuAction.values.map((action) => action.legacyKeyName).nonNulls,
  ];
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
      for (final key in obsoleteKeys) '$rootKey\\shell\\$key',
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
