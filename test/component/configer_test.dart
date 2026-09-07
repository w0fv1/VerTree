import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/component/configer.dart';

void main() {
  test('old configuration is neither imported nor overwritten', () async {
    final directory = await Directory.systemTemp.createTemp(
      'vertree-old-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final old = File('${directory.path}/config.json');
    const content =
        '{"monitorRate": 1, "monitFiles": [{"filePath": "old.txt", "isRunning": true}]}';
    await old.writeAsString(content);
    final settings = Configer(directoryResolver: () async => directory);
    await settings.init();
    expect(settings.get<int>('monitorRate', 99), 5);
    expect(settings.get<List<dynamic>>('monitorTasks', []), isEmpty);
    settings.set('monitorRate', 4);
    await settings.dispose();
    expect(await old.readAsString(), content);
    expect(await File('${directory.path}/settings.json').exists(), isTrue);
  });
  test(
    'reading defaults is pure, snapshots cannot mutate settings, corrupted settings are preserved',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vertree-settings-',
      );
      addTearDown(() => directory.delete(recursive: true));
      Configer create() => Configer(directoryResolver: () async => directory);
      final settings = create();
      await settings.init();
      expect(settings.get<int>('monitorRate', 99), 5);
      expect(await File(settings.configFilePath).exists(), isFalse);
      settings.set('monitorRate', 2);
      await settings.flush();
      settings.toJson()['monitorRate'] = 100;
      expect(settings.get<int>('monitorRate', 5), 2);
      settings.set('monitorRate', 3);
      await settings.dispose();
      await File(settings.configFilePath).writeAsString('{broken');
      final restored = create();
      await restored.init();
      expect(restored.get<int>('monitorRate', 5), 2);
      expect(await File(settings.configFilePath).readAsString(), '{broken');
      expect(
        directory.listSync().where((file) => file.path.contains('.corrupt-')),
        hasLength(1),
      );
      await restored.dispose();
    },
  );
}
