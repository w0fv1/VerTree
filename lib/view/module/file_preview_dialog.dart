import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:vertree/component/file_utils.dart';
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/main.dart';
import 'package:vertree/service/file_preview_session.dart';
import 'package:vertree/service/preview_webview_environment.dart';

Future<void> showFilePreview(BuildContext context, String path) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FilePreviewDialog(path: path),
    );

class FilePreviewDialog extends StatefulWidget {
  const FilePreviewDialog({super.key, required this.path});
  final String path;

  @override
  State<FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends State<FilePreviewDialog> {
  FilePreviewSession? _session;
  WebViewEnvironment? _environment;
  String? _error;
  bool _pageLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    FilePreviewSession? session;
    WebViewEnvironment? environment;
    try {
      if (Platform.isWindows) {
        environment = await PreviewWebViewEnvironment.shared;
      }
      session = await FilePreviewSession.open(widget.path);
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() {
        _session = session;
        _environment = environment;
      });
    } catch (error) {
      await session?.close();
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    unawaited(_session?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final session = _session;
    final embedded = Platform.isWindows || Platform.isMacOS;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width * .94,
        height: size.height * .9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
              child: Row(
                children: [
                  const Icon(Icons.preview_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p.basename(widget.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () => FileUtils.openFile(widget.path),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(appLocale.getText(LocaleKey.previewOpenSystem)),
                  ),
                  IconButton(
                    tooltip: appLocale.getText(LocaleKey.fileleafPropertyClose),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 36),
                            const SizedBox(height: 16),
                            Text(appLocale.getText(LocaleKey.previewFailed)),
                            const SizedBox(height: 8),
                            SelectableText(
                              _error!,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : session == null
                  ? const Center(child: CircularProgressIndicator())
                  : !embedded
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              appLocale.getText(LocaleKey.previewBrowserHint),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () async {
                              try {
                                if (!await launchUrl(
                                  session.uri,
                                  mode: LaunchMode.externalApplication,
                                )) {
                                  throw StateError('Cannot open browser');
                                }
                              } catch (error) {
                                if (mounted) {
                                  setState(() => _error = error.toString());
                                }
                              }
                            },
                            icon: const Icon(Icons.open_in_browser),
                            label: Text(
                              appLocale.getText(LocaleKey.previewOpenBrowser),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        if (_pageLoading) const LinearProgressIndicator(),
                        Expanded(
                          child: InAppWebView(
                            webViewEnvironment: _environment,
                            initialUrlRequest: URLRequest(
                              url: WebUri(session.uri.toString()),
                            ),
                            initialSettings: InAppWebViewSettings(
                              useShouldOverrideUrlLoading: true,
                              javaScriptCanOpenWindowsAutomatically: false,
                              supportMultipleWindows: false,
                              disableContextMenu: true,
                            ),
                            shouldOverrideUrlLoading: (_, action) async {
                              final url = action.request.url;
                              return url != null &&
                                      (url.toString() ==
                                              session.uri.toString() ||
                                          (!action.isForMainFrame &&
                                              (url.scheme == 'blob' ||
                                                  url.toString() ==
                                                      session.uri
                                                          .resolve('file')
                                                          .toString())))
                                  ? NavigationActionPolicy.ALLOW
                                  : NavigationActionPolicy.CANCEL;
                            },
                            onPermissionRequest: (_, request) async =>
                                PermissionResponse(
                                  resources: request.resources,
                                  action: PermissionResponseAction.DENY,
                                ),
                            onLoadStop: (_, _) {
                              if (mounted) setState(() => _pageLoading = false);
                            },
                            onReceivedError: (_, request, error) {
                              if (request.isForMainFrame == true && mounted) {
                                setState(() => _error = error.description);
                              }
                            },
                            onReceivedHttpError: (_, request, response) {
                              if (request.isForMainFrame == true && mounted) {
                                setState(
                                  () => _error = 'HTTP ${response.statusCode}',
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
