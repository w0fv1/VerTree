import 'package:test/test.dart';
import '../../tools/check_architecture.dart';

void main() {
  test('business, foundation and HTTP cannot import UI adapters', () {
    final found = violations({
      'lib/modules/versions/application/create.dart':
          "import '../../../adapters/ui/desktop_scope.dart';",
      'lib/foundation/clock.dart':
          "import '../modules/versions/versions.dart';",
      'lib/api/routes.dart': "import '../adapters/ui/desktop_scope.dart';",
    });
    expect(
      found.any((edge) => edge.contains('module-to-legacy-or-adapter')),
      isTrue,
    );
    expect(
      found.any((edge) => edge.contains('foundation-outward-dependency')),
      isTrue,
    );
    expect(found.any((edge) => edge.contains('backend-to-ui')), isTrue);
  });
  test('checks conditional imports and exports, not only direct imports', () {
    final found = violations({
      'lib/modules/versions/domain/model.dart':
          "import 'dart:math' if (dart.library.io) 'dart:io';\nexport '../../../main.dart';",
    });
    expect(found.any((edge) => edge.contains('dart:io')), isTrue);
    expect(
      found.any((edge) => edge.contains('entry-point-dependency')),
      isTrue,
    );
  });
  test(
    'allows public contracts but rejects cross-module internals and cycles',
    () {
      final found = violations({
        'lib/modules/monitoring/application/tasks.dart':
            "import '../../snapshots/snapshots.dart';",
        'lib/modules/snapshots/application/create.dart':
            "import '../../monitoring/application/tasks.dart';",
      });
      expect(
        found.any((edge) => edge.startsWith('lib/modules/monitoring/')),
        isFalse,
      );
      expect(
        found.any((edge) => edge.contains('module-internal-import')),
        isTrue,
      );
      expect(found.any((edge) => edge.startsWith('module-cycle:')), isTrue);
    },
  );
}
