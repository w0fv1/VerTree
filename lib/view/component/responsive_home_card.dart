import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Proportional background, independent of the current slogan's intrinsic width.
/// The preferred minimum yields to the viewport on exceptionally narrow windows.
class ResponsiveHomeCard extends StatelessWidget {
  const ResponsiveHomeCard({super.key, required this.child});
  final Widget child;
  static const widthFactor = 0.76;
  static const minimumWidth = 360.0;
  static const maximumWidth = 640.0;
  static const outerPadding = 24.0;
  static const brandActionsSpacing = 40.0;

  static double widthFor(double viewportWidth) {
    final available = math.max(0.0, viewportWidth - outerPadding * 2);
    return math.min(
      available,
      (available * widthFactor).clamp(minimumWidth, maximumWidth),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewportWidth = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : 600.0;
      return SingleChildScrollView(
        key: const ValueKey('home-card-scroll'),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(outerPadding),
              child: SizedBox(
                key: const ValueKey('home-card'),
                width: widthFor(viewportWidth),
                child: Card.filled(
                  margin: EdgeInsets.zero,
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 32,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
