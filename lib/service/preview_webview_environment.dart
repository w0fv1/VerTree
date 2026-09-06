import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The browser environment belongs to the Flutter engine, while individual
/// dialogs own their WebViews. Reusing it also avoids creating a browser
/// environment for every document opened by the user.
class PreviewWebViewEnvironment {
  static Future<WebViewEnvironment>? _instance;

  static Future<WebViewEnvironment> get shared => _instance ??= _create();

  static Future<WebViewEnvironment> _create() async {
    try {
      final version = await WebViewEnvironment.getAvailableVersion();
      if (version == null) {
        throw StateError('Microsoft Edge WebView2 Runtime is required.');
      }
      final support = await getApplicationSupportDirectory();
      return await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: p.join(support.path, 'office_preview_webview'),
        ),
      );
    } catch (_) {
      _instance = null;
      rethrow;
    }
  }
}
