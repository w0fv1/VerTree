import 'package:flutter/material.dart';

/// Homepage actions only; navigation and shutdown remain owned by the app.
class HomeActions extends StatelessWidget {
  const HomeActions({
    super.key,
    required this.monitorLabel,
    required this.settingsLabel,
    required this.exitLabel,
    required this.onMonitor,
    required this.onSettings,
    required this.onExit,
  });

  final String monitorLabel;
  final String settingsLabel;
  final String exitLabel;
  final VoidCallback onMonitor;
  final VoidCallback onSettings;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 12,
    children: [
      _navigationButton(
        context,
        name: 'monitor',
        label: monitorLabel,
        icon: Icons.monitor_heart_rounded,
        onPressed: onMonitor,
      ),
      _navigationButton(
        context,
        name: 'settings',
        label: settingsLabel,
        icon: Icons.settings_rounded,
        onPressed: onSettings,
      ),
      IconButton(
        key: const ValueKey('home-exit'),
        onPressed: onExit,
        tooltip: exitLabel,
        icon: const Icon(Icons.exit_to_app_rounded, size: 20),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(32),
          padding: const EdgeInsets.all(6),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.center,
          side: BorderSide.none,
          backgroundColor: Colors.transparent,
        ),
      ),
    ],
  );

  Widget _navigationButton(
    BuildContext context, {
    required String name,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) => FilledButton.tonal(
    key: ValueKey('home-$name'),
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      // Equal insets center the icon AND label as a single group. The .icon
      // constructor's default directional padding intentionally differs.
      // Keep the default height compact and let width follow content, not the
      // window. A minimum (not fixed) height still accommodates larger text.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minimumSize: const Size(0, 32),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      alignment: Alignment.center,
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        height: 1,
        leadingDistribution: TextLeadingDistribution.even,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, key: ValueKey('home-$name-icon'), size: 18),
        const SizedBox(width: 6),
        Flexible(
          // A centered line box is not necessarily centered visible ink.
          // Microsoft YaHei CJK labels sit about 1-1.5 logical pixels below
          // their line-box centre. Correct painting only: keep the 32px
          // button and its horizontal insets unchanged. Other font families
          // and Latin labels retain their native baseline.
          child: Transform.translate(
            offset: Offset(0, _labelInkOffset(context, label)),
            child: Text(
              label,
              key: ValueKey('home-$name-label'),
              textAlign: TextAlign.center,
              textHeightBehavior: const TextHeightBehavior(
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
        ),
      ],
    ),
  );
  static double _labelInkOffset(BuildContext context, String label) {
    final style = Theme.of(context).textTheme.labelLarge;
    final isYaHei = style?.fontFamily == 'Microsoft YaHei';
    final isCjk = RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(label);
    return isYaHei && isCjk ? -1.25 : 0;
  }
}
