import 'package:flutter/material.dart';

import 'action_icons.dart';

const String kLogoDefault = 'assets/img/logo/logo.png';

const List<double> _invertColorMatrix = <double>[
  -1,
  0,
  0,
  0,
  255,
  0,
  -1,
  0,
  0,
  255,
  0,
  0,
  -1,
  0,
  255,
  0,
  0,
  0,
  1,
  0,
];

Widget themedLogoImage({
  required BuildContext context,
  double width = 20,
  double height = 20,
  BoxFit fit = BoxFit.contain,
}) {
  final brightness = Theme.of(context).brightness;
  final image = Image.asset(
    kLogoDefault,
    width: width,
    height: height,
    fit: fit,
  );

  if (brightness == Brightness.dark) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(_invertColorMatrix),
      child: image,
    );
  }
  return image;
}

Widget shareActionImage({double size = 18}) {
  return Icon(AppActionIcon.share.data, size: size);
}
