import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/component/notifier.dart';
import 'package:vertree/service/app_announcement_service.dart';
import 'package:vertree/component/themed_assets.dart';
import 'package:vertree/main.dart';
import 'package:vertree/platform/platform_integration.dart';
import 'package:vertree/view/component/app_bar.dart';
import 'package:vertree/view/component/app_page_background.dart';
import 'package:vertree/view/page/monit_page.dart';
import 'package:vertree/view/page/setting_page.dart';

import 'package:window_manager/window_manager.dart';

enum _AnnouncementDialogAction { close, dismissForever }

class BrandPage extends StatefulWidget {
  const BrandPage({
    super.key,
    this.forceShowInitialSetupDialog = false,
    this.initialSetupDialogDelay = const Duration(seconds: 1),
  });

  final bool forceShowInitialSetupDialog;
  final Duration initialSetupDialogDelay;

  @override
  State<BrandPage> createState() => _BrandPageState();
}

class _BrandPageState extends State<BrandPage> with WindowListener {
  static const String _expressMenuPromptedKey =
      'expressBackupContextMenuPrompted';
  Timer? _setupTimer;
  AppAnnouncement? _pendingAnnouncement;
  bool _announcementLoaded = false;
  bool _announcementDialogOpen = false;

  Future<void> _runStartupFlow() async {
    await setup();
    await _loadAnnouncementIfNeeded();
    await _tryShowAnnouncement();
  }

  Future<void> _loadAnnouncementIfNeeded() async {
    if (_announcementLoaded || suppressAnnouncementDialogs) {
      return;
    }
    _announcementLoaded = true;
    _pendingAnnouncement = await appAnnouncementService
        .fetchActiveAnnouncement();
  }

  Future<void> _tryShowAnnouncement() async {
    final announcement = _pendingAnnouncement;
    if (!mounted ||
        suppressAnnouncementDialogs ||
        announcement == null ||
        _announcementDialogOpen ||
        appAnnouncementService.hasShownInSession(announcement.uuid)) {
      return;
    }

    final isVisible = await windowManager.isVisible();
    if (!isVisible || !mounted) {
      return;
    }

    _announcementDialogOpen = true;
    appAnnouncementService.markShownInSession(announcement.uuid);
    final action = await showDialog<_AnnouncementDialogAction>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final scheme = theme.colorScheme;
        return AlertDialog(
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.campaign_rounded,
                    color: scheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appLocale.getText(LocaleKey.brandAnnouncementTitle),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        announcement.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_AnnouncementDialogAction.close),
              child: Text(appLocale.getText(LocaleKey.brandAnnouncementClose)),
            ),
            if (announcement.linkUri != null)
              FilledButton(
                onPressed: () async {
                  final opened = await _openAnnouncementLink(
                    announcement.linkUri!,
                  );
                  if (opened && dialogContext.mounted) {
                    Navigator.of(
                      dialogContext,
                    ).pop(_AnnouncementDialogAction.close);
                  }
                },
                child: Text(appLocale.getText(LocaleKey.brandAnnouncementGo)),
              ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_AnnouncementDialogAction.dismissForever),
              child: Text(
                appLocale.getText(LocaleKey.brandAnnouncementDontShowAgain),
              ),
            ),
          ],
        );
      },
    );

    if (action == _AnnouncementDialogAction.dismissForever) {
      appAnnouncementService.dismissAnnouncement(announcement.uuid);
    }

    _pendingAnnouncement = null;
    _announcementDialogOpen = false;
  }

  Future<bool> _openAnnouncementLink(Uri uri) async {
    try {
      final didLaunch = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (didLaunch) {
        return true;
      }
    } catch (e) {
      logger.error('Failed to open announcement link $uri: $e');
    }

    if (mounted) {
      showToast(appLocale.getText(LocaleKey.brandAnnouncementOpenFailed));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: VAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            themedLogoImage(context: context, width: 18, height: 18),
            const SizedBox(width: 8),
            Text(appLocale.getText(LocaleKey.brandTitle)),
          ],
        ),
        goHome: false,
      ),
      body: AppPageBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card.filled(
                color: scheme.surfaceContainerLowest,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      themedLogoImage(
                        context: context,
                        width: 240,
                        height: 180,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        appLocale.getText(LocaleKey.brandTitle),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Text(
                          appLocale.getText(LocaleKey.brandSlogan),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              go(MonitPage());
                            },
                            icon: const Icon(Icons.monitor_heart_rounded),
                            label: Text(
                              appLocale.getText(LocaleKey.brandMonitorPage),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              go(SettingPage());
                            },
                            icon: const Icon(Icons.settings_rounded),
                            label: Text(
                              appLocale.getText(LocaleKey.brandSettingPage),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await quitApplication();
                            },
                            icon: const Icon(Icons.exit_to_app_rounded),
                            label: Text(appLocale.getText(LocaleKey.brandExit)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> setup() async {
    if (!mounted) return;

    bool isSetupDone = configer.get<bool>('isSetupDone', false);
    final shouldForceInitialSetupDialog = widget.forceShowInitialSetupDialog;
    if (isSetupDone && !shouldForceInitialSetupDialog) {
      if (PlatformIntegration.isWindows) {
        final alreadyPrompted = configer.get<bool>(
          _expressMenuPromptedKey,
          false,
        );
        final expressExists =
            await PlatformIntegration.checkExpressBackupKeyExists();
        if (!alreadyPrompted && !expressExists) {
          configer.set<bool>(_expressMenuPromptedKey, true);

          Future.delayed(const Duration(milliseconds: 300), () async {
            if (!mounted) return;
            final consent = await showDialog<bool>(
              context: context,
              builder: (dialogContext) {
                return AlertDialog(
                  title: Text(
                    appLocale.getText(LocaleKey.brandExpressMenuPromptTitle),
                  ),
                  content: Text(
                    appLocale.getText(LocaleKey.brandExpressMenuPromptContent),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(
                        appLocale.getText(
                          LocaleKey.brandExpressMenuPromptLater,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(
                        appLocale.getText(
                          LocaleKey.brandExpressMenuPromptEnable,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );

            if (consent == true) {
              await PlatformIntegration.addExpressBackupContextMenu();
            }
          });
        }
      }
      return;
    }

    if (!mounted) return;
    bool? userConsent = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(appLocale.getText(LocaleKey.brandInitTitle)),
          content: Text(appLocale.getText(LocaleKey.brandInitContent)),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext, rootNavigator: true).pop(false),
              child: Text(appLocale.getText(LocaleKey.brandCancel)),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext, rootNavigator: true).pop(true),
              child: Text(appLocale.getText(LocaleKey.brandConfirm)),
            ),
          ],
        );
      },
    );

    if (userConsent == true) {
      final allSuccess = await PlatformIntegration.applyInitialSetup();
      if (allSuccess) {
        await showWindowsNotification(
          appLocale.getText(LocaleKey.brandInitDoneTitle),
          appLocale.getText(LocaleKey.brandInitDoneBody),
        );
        configer.set<bool>('isSetupDone', true);
      } else {
        logger.error("初始化未全部成功，请在设置页面重试并完成授权");
        await showWindowsNotification(
          "Vertree",
          appLocale.getText(LocaleKey.brandSetupPartialFailedBody),
        );
        configer.set<bool>('isSetupDone', false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _setupTimer = Timer(widget.initialSetupDialogDelay, () {
      unawaited(_runStartupFlow());
    });
  }

  @override
  void dispose() {
    _setupTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowFocus() {
    unawaited(_tryShowAnnouncement());
  }

  @override
  void onWindowRestore() {
    unawaited(_tryShowAnnouncement());
  }
}
