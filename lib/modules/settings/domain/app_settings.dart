import '../../../foundation/operation_failure.dart';

class AppSettings {
  static const defaults = <String, Object>{
    'monitorRate': 5,
    'monitorMaxSize': 50,
    'themeMode': 'system',
    'localHttpApiEnabled': false,
  };
  static void validate(String key, Object? value) {
    final valid = switch (key) {
      'monitorRate' => value is int && value >= 0,
      'monitorMaxSize' => value is int && value >= 1,
      'themeMode' => ['system', 'light', 'dark'].contains(value),
      'launch2Tray' || 'localHttpApiEnabled' => value is bool,
      _ => true,
    };
    if (!valid) {
      throw OperationFailure('INVALID_SETTING', 'Invalid value for $key');
    }
  }
}
