import 'dart:async';
import '../component/configer.dart';

/// Prompt acknowledgement is independent of optional platform setup success.
class InitialSetupService {
  InitialSetupService(this.config);

  final Configer config;
  Completer<void>? _running;
  static const promptedKey = 'initialSetupPrompted';

  Future<void> run({
    required Future<bool?> Function() requestConsent,
    required Future<bool> Function() applySetup,
    required Future<void> Function(bool success) notifyResult,
    required void Function(Object error) onError,
    bool force = false,
  }) async {
    if (_running != null) {
      // A new home page must wait before continuing to announcements.
      await _running!.future;
      return;
    }
    if (!force &&
        (config.get<bool>(promptedKey, false) ||
            config.get<bool>('isSetupDone', false))) {
      return;
    }
    _running = Completer<void>();
    try {
      // Reserve synchronously before opening a dialog. Recreated pages must
      // not prompt again while consent or platform integration is pending.
      config.set(promptedKey, true);
      await config.flush();
      final consent = await requestConsent();
      if (consent != true) return;
      var success = false;
      try {
        success = await applySetup();
      } catch (error) {
        onError(error);
      }
      config.set('isSetupDone', success);
      await config.flush();
      // Notification failure must never undo successfully saved setup state.
      await notifyResult(success);
    } finally {
      _running!.complete();
      _running = null;
    }
  }
}
