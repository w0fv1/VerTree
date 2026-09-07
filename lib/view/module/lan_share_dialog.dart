import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/component/themed_assets.dart';
import 'package:vertree/component/notifier.dart';
import 'package:vertree/adapters/ui/desktop_scope.dart';

class LanShareDialog extends StatelessWidget {
  const LanShareDialog({super.key, required this.shareData});

  final Map<String, dynamic> shareData;

  String? get _sharePageUrl => shareData['sharePageUrl'] as String?;
  List<dynamic> get _directDownloads =>
      (shareData['directDownloads'] as List?) ?? const <dynamic>[];

  @override
  Widget build(BuildContext context) {
    final desktop = DesktopScope.read(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final compactLayout = screenWidth < 760;
    final dialogWidth =
        (compactLayout
                ? (screenWidth - 24).clamp(280.0, 520.0)
                : (screenWidth * 0.82).clamp(640.0, 980.0))
            .toDouble();
    final qrSize = compactLayout ? 180.0 : 220.0;
    final sharePageUrl = _sharePageUrl;
    final fileName = (shareData['fileName'] as String?) ?? '';
    final fileSize = (shareData['fileSize'] as num?)?.toInt() ?? 0;
    final expiresAt = _formatDateTime(shareData['expiresAt'] as String?);

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compactLayout ? 12 : 24,
        vertical: 18,
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actionsOverflowButtonSpacing: 10,
      title: Text(
        desktop.appLocale.getText(LocaleKey.fileleafShareDialogTitle).tr([
          fileName,
        ]),
      ),
      content: SizedBox(
        width: dialogWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.78),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desktop.appLocale.getText(LocaleKey.fileleafShareDialogHint),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatCard(
                      icon: Icons.insert_drive_file_outlined,
                      label: desktop.appLocale.getText(
                        LocaleKey.fileleafPropertyName,
                      ),
                      value: fileName,
                    ),
                    _StatCard(
                      icon: Icons.data_object_rounded,
                      label: desktop.appLocale.getText(
                        LocaleKey.fileleafPropertySize,
                      ),
                      value: _formatBytes(fileSize),
                    ),
                    _StatCard(
                      icon: Icons.timer_outlined,
                      label: desktop.appLocale.getText(
                        LocaleKey.fileleafShareExpiresAt,
                      ),
                      value: expiresAt,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (sharePageUrl != null) ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked =
                          compactLayout || constraints.maxWidth < 720;
                      final qrWidget = Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: QrImageView(
                              data: sharePageUrl,
                              version: QrVersions.auto,
                              size: qrSize,
                            ),
                          ),
                        ),
                      );

                      final linkWidget = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            desktop.appLocale.getText(
                              LocaleKey.fileleafShareLandingLink,
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _SelectableUrlCard(text: sharePageUrl),
                        ],
                      );

                      if (stacked) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            qrWidget,
                            const SizedBox(height: 14),
                            linkWidget,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: qrSize + 36, child: qrWidget),
                          const SizedBox(width: 20),
                          Expanded(child: linkWidget),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                ],
                Text(
                  desktop.appLocale.getText(LocaleKey.fileleafShareCandidates),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  desktop.appLocale.getText(LocaleKey.fileleafShareBrowserHint),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                ..._directDownloads.map((item) {
                  final directDownload = item as Map;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _DirectDownloadCard(
                      ip: directDownload['ip']?.toString() ?? '',
                      url: directDownload['downloadUrl']?.toString() ?? '',
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            desktop.appLocale.getText(LocaleKey.fileleafPropertyClose),
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: sharePageUrl == null
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: sharePageUrl));
                  showToast(
                    desktop.appLocale.getText(
                      LocaleKey.fileleafShareCopiedLink,
                    ),
                  );
                },
          icon: const Icon(Icons.copy_all_rounded),
          label: Text(
            desktop.appLocale.getText(LocaleKey.fileleafShareCopyLink),
          ),
        ),
        FilledButton.icon(
          onPressed: sharePageUrl == null
              ? null
              : () async {
                  final uri = Uri.parse(sharePageUrl);
                  if (!await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  )) {
                    showToast(
                      desktop.appLocale.getText(
                        LocaleKey.fileleafShareOpenFailed,
                      ),
                    );
                  }
                },
          icon: const Icon(Icons.open_in_browser_rounded),
          label: Text(
            desktop.appLocale.getText(LocaleKey.fileleafShareOpenLanding),
          ),
        ),
      ],
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String _formatDateTime(String? isoText) {
    if (isoText == null || isoText.isEmpty) {
      return '-';
    }

    final parsed = DateTime.tryParse(isoText);
    if (parsed == null) {
      return isoText;
    }
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 228),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.64),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectableUrlCard extends StatelessWidget {
  const _SelectableUrlCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SelectableText(text),
      ),
    );
  }
}

class _DirectDownloadCard extends StatelessWidget {
  const _DirectDownloadCard({required this.ip, required this.url});

  final String ip;
  final String url;

  @override
  Widget build(BuildContext context) {
    final desktop = DesktopScope.read(context);
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 460;
        final header = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      shareActionImage(size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ip,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        showToast(
                          desktop.appLocale.getText(
                            LocaleKey.fileleafShareCopiedLink,
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(
                        desktop.appLocale.getText(
                          LocaleKey.fileleafShareCopyLink,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  shareActionImage(size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ip,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      showToast(
                        desktop.appLocale.getText(
                          LocaleKey.fileleafShareCopiedLink,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(
                      desktop.appLocale.getText(
                        LocaleKey.fileleafShareCopyLink,
                      ),
                    ),
                  ),
                ],
              );

        return Card.outlined(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 8),
                SelectableText(url),
              ],
            ),
          ),
        );
      },
    );
  }
}
