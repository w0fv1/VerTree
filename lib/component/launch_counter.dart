import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:vertree/component/app_logger.dart';
import 'package:vertree/component/configer.dart';

class LaunchCounter {
  static const String _lastLaunchCounterAtKey = 'lastLaunchCounterAt';
  static const Duration _minInterval = Duration(hours: 20);
  static const Duration _requestTimeout = Duration(seconds: 3);
  static final Uri _counterUri = Uri.parse(
    'https://next.firco.cn/api/counter/vertree_launch?secret=1231232',
  );

  static void trackLaunchIfNeeded({
    required Configer configer,
    required AppLogger logger,
  }) {
    unawaited(_trackLaunchIfNeeded(configer: configer, logger: logger));
  }

  static Future<void> _trackLaunchIfNeeded({
    required Configer configer,
    required AppLogger logger,
  }) async {
    try {
      final now = DateTime.now();
      final lastTrackedRaw = configer.get<String>(_lastLaunchCounterAtKey, '');
      final lastTrackedAt = DateTime.tryParse(lastTrackedRaw);

      if (lastTrackedAt != null &&
          now.difference(lastTrackedAt) < _minInterval) {
        logger.info('启动计数跳过：距离上次上报未超过 ${_minInterval.inHours} 小时');
        return;
      }

      configer.set<String>(_lastLaunchCounterAtKey, now.toIso8601String());

      final response = await http.get(_counterUri).timeout(_requestTimeout);
      logger.info('启动计数请求已发送，状态码: ${response.statusCode}');
    } catch (e) {
      logger.error('启动计数请求失败，但不影响应用启动: $e');
    }
  }
}
