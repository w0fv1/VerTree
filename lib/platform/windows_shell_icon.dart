import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WindowsShellIcon extends ValueNotifier<String> {
  WindowsShellIcon() : super('assets/img/logo/logo.ico');

  static const _channel = MethodChannel('vertree/shell-icons');

  Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'iconChanged') value = call.arguments as String;
    });
    value = (await _channel.invokeMethod<String>('currentIcon'))!;
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
