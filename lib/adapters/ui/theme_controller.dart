import 'dart:async';
import 'package:flutter/material.dart';
import '../../component/configer.dart';
import 'desktop_scope.dart' show AppThemeSetting;

class DesktopThemeController {
  DesktopThemeController(this.config) {
    _reload();
    _subscription = config.changes.listen((_) => _reload());
  }
  final Configer config;
  final mode = ValueNotifier<ThemeMode>(ThemeMode.system);
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  AppThemeSetting get setting =>
      AppThemeSetting.values.byName(config.get<String>('themeMode', 'system'));
  Brightness get effectiveBrightness => switch (mode.value) {
    ThemeMode.dark => Brightness.dark,
    ThemeMode.light => Brightness.light,
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };
  void _reload() {
    mode.value = ThemeMode.values.byName(setting.name);
  }

  void update(AppThemeSetting value) {
    config.set('themeMode', value.name);
    _reload();
  }

  void toggle() {
    if (setting == AppThemeSetting.system) return;
    update(
      setting == AppThemeSetting.dark
          ? AppThemeSetting.light
          : AppThemeSetting.dark,
    );
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    mode.dispose();
  }
}
