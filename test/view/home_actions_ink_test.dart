import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/adapters/ui/desktop_theme.dart';
import 'package:vertree/view/component/home_actions.dart';

// Geometry-only tests use Ahem and cannot detect the real font's empty space.
// Load the installed Windows font locally; never copy it into project assets.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
  final regular = File('$windows/Fonts/msyh.ttc');
  final bold = File('$windows/Fonts/msyhbd.ttc');
  final available =
      Platform.isWindows && regular.existsSync() && bold.existsSync();
  group(
    'real Microsoft YaHei visible-ink alignment',
    () {
      setUpAll(() async {
        final fonts = FontLoader('Microsoft YaHei');
        for (final font in [regular, bold]) {
          fonts.addFont(font.readAsBytes().then(ByteData.sublistView));
        }
        await fonts.load();
        final config = File('.dart_tool/package_config.json').absolute;
        final packages =
            (jsonDecode(await config.readAsString()) as Map)['packages']
                as List;
        final flutter = packages.cast<Map>().firstWhere(
          (p) => p['name'] == 'flutter',
        );
        final sdk = Directory.fromUri(
          config.uri.resolve(flutter['rootUri'] as String),
        ).parent.parent;
        final icons = FontLoader('MaterialIcons');
        icons.addFont(
          File(
            '${sdk.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        );
        await icons.load();
      });

      for (final labels in [
        ['监控', '设置'],
        ['モニター', '設定'],
      ]) {
        for (final scale in [1.0, 1.5]) {
          for (final dpi in [1.0, 1.25, 1.5, 2.0]) {
            testWidgets(
              '${labels.first}, text $scale, DPI $dpi: paint is centered',
              (tester) async {
                tester.view.devicePixelRatio = dpi;
                tester.view.physicalSize = Size(600 * dpi, 200 * dpi);
                addTearDown(tester.view.resetPhysicalSize);
                addTearDown(tester.view.resetDevicePixelRatio);
                final key = GlobalKey();
                await tester.pumpWidget(
                  MaterialApp(
                    theme: buildLightTheme(),
                    home: Scaffold(
                      body: RepaintBoundary(
                        key: key,
                        child: MediaQuery(
                          data: MediaQueryData(
                            textScaler: TextScaler.linear(scale),
                          ),
                          child: Center(
                            child: HomeActions(
                              monitorLabel: labels[0],
                              settingsLabel: labels[1],
                              exitLabel: 'Exit',
                              onMonitor: () {},
                              onSettings: () {},
                              onExit: () {},
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                final boundary =
                    key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final origin = boundary.localToGlobal(Offset.zero);
                await tester.runAsync(() async {
                  final image = await boundary.toImage(pixelRatio: dpi);
                  try {
                    final rgba = (await image.toByteData(
                      format: ui.ImageByteFormat.rawRgba,
                    ))!.buffer.asUint8List();
                    for (final name in ['monitor', 'settings']) {
                      final button = tester
                          .getRect(find.byKey(ValueKey('home-$name')))
                          .shift(-origin);
                      if (scale == 1) {
                        expect(
                          button.height,
                          32,
                          reason: 'Optical correction must not enlarge buttons',
                        );
                      }
                      final centres = <double>[];
                      for (final part in ['icon', 'label']) {
                        final bounds = tester
                            .getRect(find.byKey(ValueKey('home-$name-$part')))
                            .shift(-origin);
                        final ink = _visibleInk(
                          rgba,
                          image.width,
                          image.height,
                          bounds,
                          dpi,
                        );
                        expect(
                          ink,
                          isNotNull,
                          reason:
                              '$name $part must be rendered with a real font',
                        );
                        final centre = ink!.center.dy;
                        centres.add(centre);
                        expect(
                          (centre - button.center.dy * dpi).abs(),
                          lessThanOrEqualTo(1.25),
                          reason:
                              '$name $part ink, not its line box, must be vertically centered',
                        );
                      }
                      expect(
                        (centres[0] - centres[1]).abs(),
                        lessThanOrEqualTo(1.5),
                        reason:
                            '$name: visible icon/text must align within pixel rasterization tolerance',
                      );
                    }
                  } finally {
                    image.dispose();
                  }
                });
                expect(tester.takeException(), isNull);
              },
            );
          }
        }
      }
    },
    skip: available
        ? false
        : 'Requires locally installed Microsoft YaHei on Windows',
  );
}

Rect? _visibleInk(
  Uint8List rgba,
  int width,
  int height,
  Rect bounds,
  double dpi,
) {
  // Restrict horizontally to the icon/label; extend vertically to include ink
  // outside a tightly set line box. Light button/card pixels are not glyphs.
  final left = (bounds.left * dpi).floor().clamp(0, width);
  final right = (bounds.right * dpi).ceil().clamp(0, width);
  final top = ((bounds.top - 4) * dpi).floor().clamp(0, height);
  final bottom = ((bounds.bottom + 4) * dpi).ceil().clamp(0, height);
  int? first, last;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final i = (y * width + x) * 4;
      if (rgba[i + 3] > 200 &&
          rgba[i] < 140 &&
          rgba[i + 1] < 140 &&
          rgba[i + 2] < 140) {
        first ??= y;
        last = y;
      }
    }
  }
  return first == null
      ? null
      : Rect.fromLTRB(
          left.toDouble(),
          first.toDouble(),
          right.toDouble(),
          (last! + 1).toDouble(),
        );
}
