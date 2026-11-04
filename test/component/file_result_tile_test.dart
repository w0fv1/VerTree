import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/view/component/file_result_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pasteboard');
  late Directory directory;
  late File file;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('vertree-result-');
    file = File('${directory.path}/结果.webp')
      ..writeAsBytesSync(List.filled(2048, 1));
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  testWidgets(
    'output details use actual file and copy uses file clipboard format',
    (tester) async {
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (value) async {
            call = value;
            return null;
          });
      String? preview;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileResultTile(
              path: file.path,
              onPreview: (path) => preview = path,
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.text('结果.webp'), findsOneWidget);
      expect(find.textContaining('2.0 KB'), findsOneWidget);
      expect(
        find.textContaining(Platform.isWindows ? '创建' : '修改'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('预览结果'));
      expect(preview, file.path);
      await tester.tap(find.byTooltip('复制文件'));
      await tester.pumpAndSettle();
      expect(call?.method, 'writeFiles');
      expect(call?.arguments, [file.path]);
      expect(find.text('已复制文件'), findsOneWidget);
      expect(file.existsSync(), isTrue);
    },
  );

  testWidgets('clipboard failure is reported without a success message', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'busy');
        });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileResultTile(path: file.path, onPreview: (_) {}),
        ),
      ),
    );
    await tester.tap(find.byTooltip('复制文件'));
    await tester.pumpAndSettle();
    expect(find.text('已复制文件'), findsNothing);
    expect(find.textContaining('操作失败'), findsOneWidget);
  });
}
