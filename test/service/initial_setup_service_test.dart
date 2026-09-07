import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/component/configer.dart';
import 'package:vertree/service/initial_setup_service.dart';

void main() {
  late Directory directory;
  late Configer config;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vertree-setup-');
    config = Configer(directoryResolver: () async => directory);
    await config.init();
  });
  tearDown(() async {
    await config.dispose();
    await directory.delete(recursive: true);
  });

  for (final consent in <bool?>[false, null, true]) {
    test(
      'consent $consent does not prompt again after restart, even on partial failure',
      () async {
        await InitialSetupService(config).run(
          requestConsent: () async => consent,
          applySetup: () async => false,
          notifyResult: (_) async {},
          onError: (_) {},
        );
        final reloaded = Configer(directoryResolver: () async => directory);
        await reloaded.init();
        await InitialSetupService(reloaded).run(
          requestConsent: () async => fail('Repeated initialization prompt'),
          applySetup: () async => fail('Unexpected setup'),
          notifyResult: (_) async {},
          onError: (_) {},
        );
        expect(reloaded.get<bool>('isSetupDone', false), isFalse);
        await reloaded.dispose();
      },
    );
  }

  test('setup success is durable before a failing notification', () async {
    await expectLater(
      InitialSetupService(config).run(
        requestConsent: () async => true,
        applySetup: () async => true,
        notifyResult: (_) async => throw StateError('Notification unavailable'),
        onError: (_) {},
      ),
      throwsStateError,
    );
    final reloaded = Configer(directoryResolver: () async => directory);
    await reloaded.init();
    expect(reloaded.get<bool>('isSetupDone', false), isTrue);
    await reloaded.dispose();
  });

  test(
    'concurrent forced requests do not stack and an explicit later retry works',
    () async {
      final service = InitialSetupService(config);
      final consent = Completer<bool>();
      final opened = Completer<void>();
      var prompts = 0;
      Future<void> run() => service.run(
        force: true,
        requestConsent: () {
          prompts++;
          if (!opened.isCompleted) opened.complete();
          return consent.future;
        },
        applySetup: () async => true,
        notifyResult: (_) async {},
        onError: (_) {},
      );
      final first = run();
      await opened.future;
      var secondFinished = false;
      final second = run().then((_) {
        secondFinished = true;
      });
      expect(prompts, 1);
      expect(secondFinished, isFalse);
      consent.complete(false);
      await first;
      await second;
      await run();
      expect(prompts, 2);
    },
  );

  test(
    'platform exceptions persist acknowledgement and report failure',
    () async {
      Object? reported;
      bool? notified;
      await InitialSetupService(config).run(
        requestConsent: () async => true,
        applySetup: () async => throw StateError('Integration failed'),
        notifyResult: (success) async {
          notified = success;
        },
        onError: (error) {
          reported = error;
        },
      );
      expect(reported, isStateError);
      expect(notified, isFalse);
      expect(config.get<bool>(InitialSetupService.promptedKey, false), isTrue);
    },
  );
}
