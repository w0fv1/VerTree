import 'package:vertree/platform/bootstrap/platform_bootstrap.dart';
import 'package:vertree/component/isolated_profile.dart';
import 'package:vertree/platform/windows_registry_bridge.dart';
import 'package:vertree/platform/windows_single_instance_bridge.dart';

class WindowsBootstrap extends PlatformBootstrap {
  const WindowsBootstrap();

  @override
  String get name => 'windows';

  @override
  Future<bool> handlePreBootstrapArgs(List<String> args) {
    return WindowsRegistryBridge.tryHandleElevatedTask(args);
  }

  @override
  Future<void> configureSingleInstance({
    required List<String> args,
    required SecondInstanceArgsHandler onSecondInstanceArgs,
  }) {
    return WindowsSingleInstanceBridge.ensureSingleInstance(
      args,
      "dev.w0fv1.vertree$isolatedInstanceSuffix",
      onSecondWindow: onSecondInstanceArgs,
      bringWindowToFront: false,
    );
  }
}
