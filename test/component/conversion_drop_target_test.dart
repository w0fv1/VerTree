import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/view/component/conversion_drop_target.dart';

void main() {
  testWidgets(
    'external Ctrl survives exit-before-done and resets for the next drag',
    (tester) async {
      var control = true;
      final dropped = <List<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ConversionDropTarget(
            readControlPressed: () => control,
            onConvert: dropped.add,
            child: const SizedBox.expand(),
          ),
        ),
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Future<void> send(String method, Object? args) =>
          messenger.handlePlatformMessage(
            'desktop_drop',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, args),
            ),
            (_) {},
          );
      await send('entered', [20.0, 20.0]);
      control = false;
      await send('performOperation', [r'C:\sample.png']);
      expect(dropped, [
        [r'C:\sample.png'],
      ]);
      await send('entered', [20.0, 20.0]);
      await send('performOperation', [r'C:\plain.png']);
      expect(dropped, hasLength(1));
      control = true;
      await send('entered', [20.0, 20.0]);
      control = false;
      await send('updated', [25.0, 25.0]);
      await send('performOperation', [r'C:\released.png']);
      expect(dropped, hasLength(1));
    },
  );
}
