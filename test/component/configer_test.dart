import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/component/configer.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'vertree-single-settings-',
    );
  });
  tearDown(() => directory.delete(recursive: true));
  Configer create() => Configer(directoryResolver: () async => directory);
  List<String> names() =>
      directory
          .listSync()
          .map((file) => file.path.split(Platform.pathSeparator).last)
          .toList()
        ..sort();

  test(
    'obsolete files are discarded, never imported into the sole configuration',
    () async {
      await File('${directory.path}/config.json').writeAsString(
        '{"monitorRate":1,"monitFiles":[{"filePath":"old.txt"}]}',
      );
      await File(
        '${directory.path}/settings.json.previous',
      ).writeAsString('{"_schemaVersion":1,"monitorRate":2}');
      final settings = create();
      await settings.init();
      expect(settings.get<int>('monitorRate', 99), 5);
      expect(settings.get<List<dynamic>>('monitorTasks', []), isEmpty);
      expect(names(), isEmpty);
      settings.set('monitorRate', 4);
      await settings.dispose();
      expect(names(), ['settings.json']);
    },
  );

  test('valid current settings survive removal of obsolete files', () async {
    const task = {
      'id': 'fixture-task',
      'filePath': r'C:\fixture.txt',
      'enabled': true,
    };
    await File('${directory.path}/settings.json').writeAsString(
      jsonEncode({
        '_schemaVersion': 1,
        'monitorRate': 7,
        'monitorTasks': [task],
      }),
    );
    await File(
      '${directory.path}/config.json',
    ).writeAsString('{"monitorRate":1}');
    final settings = create();
    await settings.init();
    expect(settings.get<int>('monitorRate', 5), 7);
    expect(settings.get<List<dynamic>>('monitorTasks', []), [task]);
    await settings.dispose();
    expect(names(), ['settings.json']);
  });

  test(
    'reading defaults is pure and returned snapshots cannot mutate settings',
    () async {
      final settings = create();
      await settings.init();
      expect(settings.get<int>('monitorRate', 99), 5);
      expect(names(), isEmpty);
      settings.set('monitorTasks', <dynamic>[
        {'id': 'test', 'enabled': true},
      ]);
      settings.toJson()['monitorRate'] = 100;
      settings.get<List<dynamic>>('monitorTasks', []).clear();
      expect(settings.get<int>('monitorRate', 99), 5);
      expect(settings.get<List<dynamic>>('monitorTasks', []), hasLength(1));
      await settings.dispose();
      expect(names(), ['settings.json']);
    },
  );

  test(
    'corruption does not restore an older configuration or create backup copies',
    () async {
      await File('${directory.path}/settings.json').writeAsString('{broken');
      await File(
        '${directory.path}/settings.json.previous',
      ).writeAsString('{"_schemaVersion":1,"monitorRate":2}');
      final errors = <String>[];
      final settings = Configer(
        directoryResolver: () async => directory,
        onLogError: errors.add,
      );
      await settings.init();
      expect(settings.get<int>('monitorRate', 99), 5);
      expect(errors, hasLength(1));
      expect(names(), ['settings.json']);
      settings.set('monitorRate', 6);
      await settings.dispose();
      final data =
          jsonDecode(await File(settings.configFilePath).readAsString()) as Map;
      expect(data, {'_schemaVersion': 1, 'monitorRate': 6});
      expect(names(), ['settings.json']);
    },
  );

  test('unsupported schemas are not migrated', () async {
    await File('${directory.path}/settings.json').writeAsString(
      '{"_schemaVersion":0,"monitorRate":1,"monitFiles":["old"]}',
    );
    final settings = create();
    await settings.init();
    expect(settings.get<int>('monitorRate', 99), 5);
    settings.set('themeMode', 'dark');
    await settings.dispose();
    final data =
        jsonDecode(await File(settings.configFilePath).readAsString()) as Map;
    expect(data, {'_schemaVersion': 1, 'themeMode': 'dark'});
  });

  test(
    'queued commits leave one complete JSON file and no persistent recovery file',
    () async {
      final settings = create();
      await settings.init();
      for (var rate = 0; rate < 20; rate++) {
        settings.set('monitorRate', rate);
      }
      await settings.dispose();
      expect(names(), ['settings.json']);
      final fresh = create();
      await fresh.init();
      expect(fresh.get<int>('monitorRate', 99), 19);
      await fresh.dispose();
    },
  );

  test(
    'obsolete cleanup leaves unrelated files untouched',
    () async {
      final other = File('${directory.path}/notes.txt');
      await other.writeAsString('not application settings');
      final settings = create();
      await settings.init();
      settings.set('monitorRate', 4);
      await settings.dispose();
      expect(await other.readAsString(), 'not application settings');
      expect(names(), ['notes.txt', 'settings.json']);
    },
  );
}
