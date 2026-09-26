import 'dart:math';

import 'configer.dart';

/// Local copy only: no network request, timer or additional settings file.
class BrandSlogans {
  static const previousIndexKey = 'lastBrandSloganIndex';
  static const zhCn = <String>[
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
  ];
  static const en = <String>[
    'Make every iteration traceable',
    'Keep a record of every edit',
    'Leave a trail for every update',
    'Make every change clearly visible',
    'Keep every adjustment on record',
    'Retrace every step of your progress',
    'Stay on top of every version change',
    'Follow the story of every file version',
    'Never lose track of a change',
    'Let every improvement show your progress',
  ];
  static const ja = <String>[
    'すべての改良に、たどれる足跡を',
    'すべての修正に、確かめられる記録を',
    'すべての更新に、見つけられる足跡を',
    'すべての変更を、はっきり見える形に',
    'すべての調整を、記録に残そう',
    'すべての進化を、振り返れるように',
    'すべてのバージョンの変化を、手の内に',
    'すべてのファイルに、たどれる歩みを',
    'どんな変更も、見失わないように',
    'すべての改善に、成長の足跡を',
  ];

  static List<String> forLanguage(String language) => switch (language) {
    'en' => en,
    'ja' => ja,
    _ => zhCn,
  };
}

/// One immutable choice per application lifetime. Rebuilding the homepage,
/// changing its theme or returning from another page cannot select again.
class BrandSloganSession {
  BrandSloganSession({Object? previousIndex, Random? random})
    : index = _pick(previousIndex, random ?? Random());

  final int index;

  String text(String language) => BrandSlogans.forLanguage(language)[index];

  static int _pick(Object? previousIndex, Random random) {
    final count = BrandSlogans.zhCn.length;
    if (previousIndex is! int || previousIndex < 0 || previousIndex >= count) {
      return random.nextInt(count);
    }
    // Uniformly choose one of the other entries, without a reroll loop.
    final choice = random.nextInt(count - 1);
    return choice >= previousIndex ? choice + 1 : choice;
  }

  /// Call only after configuration and single-instance startup are complete.
  /// Secondary shell invocations must not rewrite the running session's choice.
  static Future<BrandSloganSession> start(
    Configer config, {
    Random? random,
    void Function(Object error)? onPersistenceError,
  }) async {
    final session = BrandSloganSession(
      previousIndex: config.toJson()[BrandSlogans.previousIndexKey],
      random: random,
    );
    try {
      config.set<int>(BrandSlogans.previousIndexKey, session.index);
      await config.flush();
    } catch (error) {
      // A cosmetic preference must not prevent the application from opening.
      // This session stays stable; non-repetition across restarts needs a save.
      onPersistenceError?.call(error);
    }
    return session;
  }
}
