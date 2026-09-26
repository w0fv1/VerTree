import 'package:flutter/material.dart';

/// Shared settings row; keeps the original legacy-menu layout and interaction.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.supportingText,
    this.trailing,
    this.onTap,
    this.topAlignLeading = false,
  }) : assert(icon != null || leading != null);

  final IconData? icon;
  final Widget? leading;
  final Widget title;
  final Widget? supportingText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool topAlignLeading;

  @override
  Widget build(BuildContext context) {
    final supportingText = this.supportingText;
    final trailing = this.trailing;
    final scheme = Theme.of(context).colorScheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyLarge!,
          child: title,
        ),
        if (supportingText != null) ...[
          const SizedBox(height: 4),
          DefaultTextStyle(
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
            child: supportingText,
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                crossAxisAlignment: topAlignLeading || supportingText != null
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      top: topAlignLeading || supportingText != null ? 2 : 0,
                    ),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Center(child: leading ?? Icon(icon, size: 20)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: topAlignLeading || supportingText != null ? 0 : 1,
                      ),
                      child: content,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    Padding(
                      padding: EdgeInsets.only(
                        top: topAlignLeading || supportingText != null ? 0 : 0,
                      ),
                      child: trailing,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    required this.value,
    required this.onChanged,
  }) : assert(icon != null || leading != null);

  final IconData? icon;
  final Widget? leading;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SettingsRow(
    icon: icon,
    leading: leading,
    title: Text(title),
    trailing: Switch(value: value, onChanged: onChanged),
    onTap: onChanged == null ? null : () => onChanged!(!value),
  );
}
