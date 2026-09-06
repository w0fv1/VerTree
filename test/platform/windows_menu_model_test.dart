import 'package:test/test.dart';
import 'package:vertree/platform/windows_menu_model.dart';

class FakeRegistry {
  final keys = <String, WindowsMenuAction?>{'AnotherApp': null};
  String? failWrite;
  String? failRemove;

  bool apply(Set<WindowsMenuAction> selected, {required bool collapsed}) =>
      WindowsMenuPlan(selected, collapsed: collapsed).apply(
        write: (entry) {
          if (entry.key == failWrite) return false;
          keys[entry.key] = entry.action;
          return true;
        },
        remove: (key) {
          if (key == failRemove) return false;
          keys.removeWhere(
            (candidate, _) =>
                candidate == key || candidate.startsWith('$key\\'),
          );
          return true;
        },
      );

  Iterable<WindowsMenuAction> get actions => keys.values.nonNulls;
}

void main() {
  test('upgrade adds preview while preserving disabled actions', () {
    expect(WindowsMenuPlan.migrateSelection({WindowsMenuAction.backup}), {
      WindowsMenuAction.backup,
      WindowsMenuAction.preview,
    });
    expect(WindowsMenuPlan.migrateSelection({}), isEmpty);
  });

  test(
    'switching layouts preserves a partial selection without duplicates',
    () {
      final registry = FakeRegistry();
      final selected = {WindowsMenuAction.preview, WindowsMenuAction.monitor};
      for (final collapsed in [false, true, true, false, false]) {
        expect(registry.apply(selected, collapsed: collapsed), isTrue);
        expect(registry.actions, unorderedEquals(selected));
        expect(registry.keys.containsKey(WindowsMenuPlan.rootKey), collapsed);
        expect(registry.keys.containsKey('AnotherApp'), isTrue);
      }
    },
  );

  test(
    'individual switches work inside a submenu and remove the last root',
    () {
      final registry = FakeRegistry();
      registry.apply(WindowsMenuAction.values.toSet(), collapsed: true);
      registry.apply({WindowsMenuAction.preview}, collapsed: true);
      expect(registry.actions, [WindowsMenuAction.preview]);
      registry.apply({}, collapsed: true);
      expect(registry.keys.keys, ['AnotherApp']);
    },
  );

  test('disabling cleans both layouts and historical keys', () {
    final registry = FakeRegistry();
    registry.apply(WindowsMenuAction.values.toSet(), collapsed: true);
    for (final action in WindowsMenuAction.values) {
      registry.keys[action.keyName] = action;
    }
    for (final key in WindowsMenuPlan.obsoleteKeys) {
      registry.keys[key] = null;
    }
    expect(registry.apply({}, collapsed: false), isTrue);
    expect(registry.keys.keys, ['AnotherApp']);
  });

  test('a failed replacement does not remove the working layout', () {
    final registry = FakeRegistry();
    final selected = {WindowsMenuAction.preview, WindowsMenuAction.backup};
    registry.apply(selected, collapsed: false);
    registry.failWrite =
        '${WindowsMenuPlan.rootKey}\\shell\\${WindowsMenuAction.backup.keyName}';
    expect(registry.apply(selected, collapsed: true), isFalse);
    for (final action in selected) {
      expect(registry.keys[action.keyName], action);
    }
    registry.failWrite = null;
    expect(registry.apply(selected, collapsed: true), isTrue);
    expect(registry.actions, unorderedEquals(selected));
  });

  test('cleanup failure is reported and can be retried', () {
    final registry = FakeRegistry();
    registry.apply({WindowsMenuAction.preview}, collapsed: false);
    registry.failRemove = WindowsMenuAction.preview.keyName;
    expect(registry.apply({}, collapsed: false), isFalse);
    registry.failRemove = null;
    expect(registry.apply({}, collapsed: false), isTrue);
    expect(registry.keys.keys, ['AnotherApp']);
  });
}
