import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/platform/windows_shell_icon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vertree/shell-icons');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('notification identity comes from the native shell owner', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'appIdentity');
      return 'test.native.identity';
    });
    expect(await WindowsShellIcon.appIdentity(), 'test.native.identity');
  });

  test(
    'uses the native shell selection and updates only when it changes',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'currentIcon');
        return 'assets/img/logo/logo-dark.ico';
      });
      final icon = WindowsShellIcon();
      var notifications = 0;
      icon.addListener(() => notifications++);
      await icon.initialize();
      expect(icon.value, 'assets/img/logo/logo-dark.ico');
      expect(notifications, 1);
      for (final asset in ['logo-dark.ico', 'logo-light.ico']) {
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('iconChanged', 'assets/img/logo/$asset'),
          ),
          (_) {},
        );
      }
      expect(icon.value, 'assets/img/logo/logo-light.ico');
      expect(notifications, 2);
      icon.dispose();
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('iconChanged', 'assets/img/logo/logo-dark.ico'),
        ),
        (_) {},
      );
      expect(notifications, 2);
    },
  );
}
