import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/component/brand_slogans.dart';
import 'package:vertree/component/configer.dart';
import 'package:vertree/component/i18n_lang.dart';

class SlotRandom implements Random {
  SlotRandom(this.slot);
  final int slot;
  int calls = 0;
  int? upperBound;
  @override
  int nextInt(int max) {
    calls++;
    upperBound = max;
    RangeError.checkValueInInterval(slot, 0, max - 1);
    return slot;
  }

  @override
  bool nextBool() => throw UnsupportedError('Unused');
  @override
  double nextDouble() => throw UnsupportedError('Unused');
}

class ReadOnlyConfiger extends Configer {
  @override
  Map<String, dynamic> toJson() => {
    '_schemaVersion': 1,
    BrandSlogans.previousIndexKey: 2,
  };

  @override
  T set<T>(String key, T value) =>
      throw StateError('Fixture: settings read-only');
}

void main() {
  test('ten unique phrases include the exact requested primary sentence', () {
    expect(BrandSlogans.zhCn, [
      '让每一次迭代都有迹可循',
      '让每一次修改都有据可查',
      '让每一次更新都有迹可寻',
      '让每一次变更都清晰可见',
      '让每一次调整都留有记录',
      '让每一次演进都可回溯',
      '让每一次版本变化都心中有数',
      '让每一次文件迭代都有脉络可查',
      '让每一次改动都不再无迹可寻',
      '让每一次优化都留下成长轨迹',
    ]);
    for (final language in ['zhCn', 'en', 'ja']) {
      final phrases = BrandSlogans.forLanguage(language);
      expect(phrases.length, 10);
      expect(phrases.toSet().length, 10);
      expect(
        phrases.every((text) => text.trim() == text && text.isNotEmpty),
        isTrue,
      );
    }
    final locale = AppLocale();
    for (final language in [Lang.zhCn, Lang.en, Lang.ja]) {
      locale.lang = language;
      expect(
        locale.getText(LocaleKey.brandSlogan),
        BrandSlogans.forLanguage(language.name).first,
      );
    }
    expect(BrandSlogans.forLanguage('other'), BrandSlogans.zhCn);
  });

  test('a first launch can select any of the ten entries', () {
    final selected = <int>{};
    for (var slot = 0; slot < 10; slot++) {
      final random = SlotRandom(slot);
      selected.add(BrandSloganSession(random: random).index);
      expect(random.calls, 1);
      expect(random.upperBound, 10);
    }
    expect(selected, {0, 1, 2, 3, 4, 5, 6, 7, 8, 9});
  });

  test('every previous entry leaves exactly nine non-repeating choices', () {
    for (var previous = 0; previous < 10; previous++) {
      final selected = <int>{};
      for (var slot = 0; slot < 9; slot++) {
        final random = SlotRandom(slot);
        final session = BrandSloganSession(
          previousIndex: previous,
          random: random,
        );
        selected.add(session.index);
        expect(session.index, isNot(previous));
        expect(random.calls, 1, reason: 'No reroll loop');
        expect(random.upperBound, 9);
      }
      expect(selected.length, 9);
      expect(selected.contains(previous), isFalse);
    }
  });

  test(
    'invalid old state is ignored, rather than crashing or skewing the range',
    () {
      for (final previous in [null, -1, 10, 999, '3', 3.0, false, [], {}]) {
        final random = SlotRandom(9);
        final session = BrandSloganSession(
          previousIndex: previous,
          random: random,
        );
        expect(session.index, 9);
        expect(random.upperBound, 10);
      }
    },
  );

  test(
    'reading or changing the display language never draws another index',
    () {
      final random = SlotRandom(4);
      final session = BrandSloganSession(random: random);
      for (var round = 0; round < 30; round++) {
        for (final language in ['zhCn', 'en', 'ja', 'other']) {
          expect(session.text(language), BrandSlogans.forLanguage(language)[4]);
        }
      }
      expect(random.calls, 1);
      expect(session.index, 4);
    },
  );

  test(
    'restarts persist only one index in settings.json and preserve other data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'VerTree-Slogan-Test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      const existing = {
        '_schemaVersion': 1,
        'themeMode': 'dark',
        'windows11MenuActions': ['preview'],
        'monitorTasks': [
          {
            'id': 'fixture',
            'filePath': r'C:\fixture\file.txt',
            'enabled': true,
          },
        ],
      };
      final file = File('${directory.path}/settings.json');
      await file.writeAsString(jsonEncode(existing));
      int? previous;
      for (var launch = 0; launch < 4; launch++) {
        final config = Configer(directoryResolver: () async => directory);
        await config.init();
        final session = await BrandSloganSession.start(
          config,
          random: SlotRandom(0),
        );
        expect(session.index, isNot(previous));
        previous = session.index;
        final persisted =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        expect(persisted.remove(BrandSlogans.previousIndexKey), session.index);
        expect(persisted, existing);
        final current = session.text('zhCn');
        config.set('themeMode', 'light');
        expect(session.text('zhCn'), current);
        config.set('themeMode', 'dark');
        await config.dispose();
        expect(
          directory.listSync().map((entity) => entity.uri.pathSegments.last),
          ['settings.json'],
        );
      }
    },
  );

  test('an unwritable preference does not prevent a stable homepage', () async {
    final config = ReadOnlyConfiger();
    addTearDown(config.dispose);
    final errors = <Object>[];
    final random = SlotRandom(2);
    final session = await BrandSloganSession.start(
      config,
      random: random,
      onPersistenceError: errors.add,
    );
    expect(session.index, 3);
    expect(session.text('zhCn'), BrandSlogans.zhCn[3]);
    expect(errors, hasLength(1));
    expect(random.calls, 1);
  });
}
