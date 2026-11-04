import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/api/local_http_api_server.dart';
import 'package:vertree/component/configer.dart';
import 'package:vertree/service/local_http_api_service.dart';

void main() {
  test(
    'startup API override can be disabled and stays disabled after restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vertree-api-toggle-',
      );
      final config = Configer(directoryResolver: () async => directory);
      await config.init();
      final server = LocalHttpApiServer(
        apiService: SettingsService(config),
        startEnabled: true,
      );
      try {
        await server.syncWithConfig();
        expect(server.isRunning, isTrue);
        final port = server.port!;
        await server.setEnabled(false);
        expect(server.isRunning, isFalse);
        final socket = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        await socket.close();
        await server.syncWithConfig();
        expect(server.isRunning, isFalse);
        await server.setEnabled(true);
        expect(server.isRunning, isTrue);
        expect(config.get<bool>('localHttpApiEnabled', false), isTrue);
        await server.setEnabled(false);
        await config.flush();
        final reopened = Configer(directoryResolver: () async => directory);
        await reopened.init();
        expect(reopened.get<bool>('localHttpApiEnabled', true), isFalse);
      } finally {
        await server.stop();
        await directory.delete(recursive: true);
      }
    },
  );
}

class SettingsService implements LocalHttpApiService {
  SettingsService(this.configer);
  @override
  final Configer configer;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
