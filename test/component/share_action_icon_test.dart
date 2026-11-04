import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/component/themed_assets.dart';
import 'package:vertree/component/action_icons.dart';

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
      await tester.pumpAndSettle();
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, AppActionIcon.share.data);
      final text = tester.widget<RichText>(
        find.descendant(of: find.byType(Icon), matching: find.byType(RichText)),
      );
      expect(text.text.style!.color, color);
      expect(
        text.text.toPlainText(),
        String.fromCharCode(AppActionIcon.share.data.codePoint),
      );
    }
  });
}
