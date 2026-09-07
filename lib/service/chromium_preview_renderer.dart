import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ChromiumPreviewRenderer {
  static Future<String?> executable() async {
    for (final candidate in [
      'chromium',
      'chromium-browser',
      'google-chrome',
      'google-chrome-stable',
    ]) {
      final result = await Process.run('which', [candidate]);
      if (result.exitCode == 0) return (result.stdout as String).trim();
    }
    return null;
  }

  static Future<Map<dynamic, dynamic>> execute(
    Uri uri,
    String expression, {
    String? browserPath,
  }) async {
    final browser = browserPath ?? await executable();
    if (browser == null) {
      throw UnsupportedError(
        'Install Chromium or Google Chrome for background preview images on Linux',
      );
    }
    final directory = await Directory.systemTemp.createTemp(
      'vertree-render-browser-',
    );
    Process? process;
    _DevTools? tools;
    StreamSubscription<String>? errors;
    StreamSubscription<List<int>>? output;
    try {
      process = await Process.start(browser, [
        '--headless=new',
        '--remote-debugging-port=0',
        '--no-first-run',
        '--no-default-browser-check',
        '--user-data-dir=${directory.path}',
        'about:blank',
      ]);
      output = process.stdout.listen((_) {});
      final endpoint = Completer<String>();
      errors = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final match = RegExp(
              r'DevTools listening on (ws://\S+)',
            ).firstMatch(line);
            if (match != null && !endpoint.isCompleted) {
              endpoint.complete(match[1]);
            }
          });
      unawaited(
        process.exitCode.then((code) {
          if (!endpoint.isCompleted) {
            endpoint.completeError(
              StateError('Chromium exited with code $code'),
            );
          }
        }),
      );
      tools = _DevTools(
        await WebSocket.connect(
          await endpoint.future.timeout(const Duration(seconds: 15)),
        ),
      );
      final target = await tools.call('Target.createTarget', {
        'url': 'about:blank',
      });
      final attached = await tools.call('Target.attachToTarget', {
        'targetId': target['targetId'],
        'flatten': true,
      });
      tools.sessionId = attached['sessionId'] as String;
      await tools.call('Page.navigate', {'url': uri.toString()});
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (true) {
        final ready = await tools.call('Runtime.evaluate', {
          'expression': '!!window.officePreviewImages',
          'returnByValue': true,
        });
        if ((ready['result'] as Map?)?['value'] == true) break;
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Preview renderer did not load');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final result = await tools.call('Runtime.evaluate', {
        'expression': expression,
        'awaitPromise': true,
        'returnByValue': true,
      });
      if (result['exceptionDetails'] != null) {
        throw StateError(result['exceptionDetails'].toString());
      }
      return Map<dynamic, dynamic>.from(
        (result['result'] as Map)['value'] as Map,
      );
    } finally {
      await tools?.close();
      if (process != null) {
        process.kill();
        await process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            process!.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      }
      await errors?.cancel();
      await output?.cancel();
      await directory.delete(recursive: true);
    }
  }
}

class _DevTools {
  _DevTools(this.socket) {
    subscription = socket.listen(
      (message) {
        final data = jsonDecode(message as String) as Map<String, dynamic>;
        final pending = requests.remove(data['id']);
        if (pending == null) return;
        if (data['error'] != null) {
          pending.completeError(StateError(data['error'].toString()));
        } else {
          pending.complete(Map<String, dynamic>.from(data['result'] as Map));
        }
      },
      onDone: () {
        for (final pending in requests.values) {
          pending.completeError(StateError('Renderer disconnected'));
        }
        requests.clear();
      },
    );
  }
  final WebSocket socket;
  late final StreamSubscription<dynamic> subscription;
  final requests = <int, Completer<Map<String, dynamic>>>{};
  int sequence = 0;
  String? sessionId;
  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params,
  ) {
    final id = ++sequence;
    final complete = Completer<Map<String, dynamic>>();
    requests[id] = complete;
    socket.add(
      jsonEncode({
        'id': id,
        'method': method,
        'params': params,
        if (sessionId != null) 'sessionId': sessionId,
      }),
    );
    return complete.future
        .timeout(const Duration(seconds: 40))
        .whenComplete(() => requests.remove(id));
  }

  Future<void> close() async {
    await subscription.cancel();
    await socket.close();
  }
}
