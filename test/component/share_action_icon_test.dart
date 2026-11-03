import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/component/themed_assets.dart';

void main() {
  testWidgets('share asset follows icon theme across brightness changes', (
    tester,
  ) async {
    for (final color in [Colors.white, Colors.black, Colors.grey]) {
      await tester.pumpWidget(
        MaterialApp(
          home: IconTheme(
            data: IconThemeData(color: color),
            child: Center(child: shareActionImage(size: 20)),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage(kShareActionPng),
          tester.element(find.byType(Center)),
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<RawImage>(find.byType(RawImage));
      expect(image.image, isNotNull);
      expect(image.color, color);
    }
  });
}
