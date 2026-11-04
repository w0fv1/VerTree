import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/modules/conversion/conversion.dart';
import 'package:vertree/view/component/conversion_panel.dart';

class Runtime implements ConversionRuntime {
  final jobs = <ConversionJob>[];
  @override
  Future<List<ConversionFormat>> formats() async => const [];
  @override
  Future<List<ConversionFormat>> targetsFor(String source) async => [
    const ConversionFormat(id: 'webp', name: 'WEBP', extensions: ['webp']),
    if (source.endsWith('.png'))
      const ConversionFormat(id: 'jpg', name: 'JPG', extensions: ['jpg']),
  ];
  @override
  Future<ConversionResult> convert(
    ConversionJob job, {
    void Function(double)? onProgress,
  }) async {
    jobs.add(job);
    return const ConversionResult(outputs: ['result.webp']);
  }
}

void main() {
  testWidgets(
    'selecting a format waits for conversion and shows output filename',
    (tester) async {
      final runtime = Runtime();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversionPanel(
              createQueue: () => ConversionQueue(runtime),
              initialFiles: const ['sample.png'],
              onPreview: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('选择目标格式'), findsOneWidget);
      expect(runtime.jobs, isEmpty);
      await tester.tap(find.text('WEBP'));
      await tester.pumpAndSettle();
      expect(runtime.jobs, isEmpty);
      expect(find.byTooltip('选择文件'), findsOneWidget);
      await tester.tap(find.byTooltip('转换'));
      await tester.pumpAndSettle();
      expect(runtime.jobs.single.target, 'webp');
      expect(runtime.jobs.single.sources, ['sample.png']);
      expect(find.text('result.webp'), findsOneWidget);
      expect(find.byTooltip('复制文件'), findsOneWidget);
      expect(find.byTooltip('在文件资源管理器中打开'), findsOneWidget);
      expect(find.text('开始转换'), findsNothing);
    },
  );

  testWidgets('clear removes source and selected format without conversion', (
    tester,
  ) async {
    final runtime = Runtime();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversionPanel(
            createQueue: () => ConversionQueue(runtime),
            initialFiles: const ['sample.png'],
            onPreview: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEBP'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清空选择'));
    await tester.pumpAndSettle();
    expect(find.text('sample.png'), findsNothing);
    expect(find.text('WEBP'), findsNothing);
    expect(runtime.jobs, isEmpty);
  });

  testWidgets(
    'mixed sources only offer their common targets and cancel does not convert',
    (tester) async {
      final runtime = Runtime();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversionPanel(
              createQueue: () => ConversionQueue(runtime),
              initialFiles: const ['sample.png', 'sample.jpg'],
              onPreview: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('WEBP'), findsOneWidget);
      expect(find.text('JPG'), findsNothing);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(runtime.jobs, isEmpty);
    },
  );
}
