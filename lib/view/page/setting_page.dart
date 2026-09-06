import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vertree/api/local_http_api_server.dart';
import 'package:vertree/component/app_version_info.dart';
import 'package:vertree/component/file_utils.dart';
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/component/notifier.dart';
import 'package:vertree/component/themed_assets.dart';
import 'package:vertree/component/tray_manager.dart';
import 'package:vertree/core/result.dart';
import 'package:vertree/main.dart';
import 'package:vertree/platform/linux_gnome_integration.dart';
import 'package:vertree/platform/platform_integration.dart';
import 'package:vertree/view/component/app_bar.dart';
import 'package:vertree/view/component/app_page_background.dart';
import 'package:vertree/view/component/app_version_button.dart';
import 'package:vertree/view/component/loading.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  late final TextEditingController _monitorRateController;
  late final TextEditingController _monitorMaxSizeController;
  late final ScrollController _settingsScrollController;

  bool previewFile = false;
  bool backupFile = false;
  bool expressBackupFile = false;
  bool monitorFile = false;
  bool shareFile = false;
  bool viewTreeFile = false;
  bool autoStart = false;
  bool launchToTray = PlatformIntegration.defaultLaunchToTray;
  bool legacyMenuEnabled = false;
  bool legacyMenuCollapsed = false;
  bool win11MenuEnabled = false;
  bool localHttpApiEnabled = false;
  bool _showLegacyMenuDetails = false;
  bool isLoading = false;
  String _themeModeSetting = 'system';
  GnomeSupportInfo? _gnomeFilesSupportInfo;
  GnomeSupportInfo? _gnomeTraySupportInfo;

  bool get _launchToTrayAvailable =>
      PlatformIntegration.supportsTrayOnlyBackgroundMode;
  bool get _shouldShowGnomeTraySupportCard =>
      PlatformIntegration.isLinuxGnome &&
      (_gnomeTraySupportInfo?.isAvailable == false);
  bool get _shouldShowWindowsWin11IdentityCard => false;
  bool get _shouldShowEnvironmentInfoSection =>
      _shouldShowGnomeTraySupportCard || _shouldShowWindowsWin11IdentityCard;
  String get _launchBehaviorTitle => PlatformIntegration.isLinuxGnome
      ? appLocale.getText(LocaleKey.settingLaunchMinimized)
      : appLocale.getText(LocaleKey.settingLaunchToTray);
  String get _linuxContextMenuToggleTitle =>
      _gnomeFilesSupportInfo?.isAvailable == false
      ? appLocale.getText(LocaleKey.settingLinuxContextMenuToggleInstallHint)
      : appLocale.getText(LocaleKey.settingLinuxContextMenuToggle);
  GnomeSupportInfo get _windowsWin11IdentityInfo => GnomeSupportInfo(
    status: GnomeSupportStatus.missingDependency,
    message: appLocale.getText(LocaleKey.settingWin11IdentityRequired),
    installCommand:
        r'powershell -ExecutionPolicy Bypass -File windows\packaging\install_sparse_package.ps1 -Force',
    installCommandLabel: appLocale.getText(
      LocaleKey.settingCopyRegisterCommand,
    ),
    restartCommand:
        r'powershell -ExecutionPolicy Bypass -File windows\packaging\refresh_win11_menu.ps1',
    restartCommandLabel: appLocale.getText(LocaleKey.settingCopyRefreshCommand),
  );

  Future<void> _showLinuxMenuToggleResult(bool success) async {
    if (!PlatformIntegration.isLinux) return;
    showToast(
      success
          ? appLocale.getText(LocaleKey.settingGnomeMenuUpdated)
          : appLocale.getText(LocaleKey.settingGnomeMenuUnavailable),
    );
  }

  Future<void> _applyContextMenuToggle({
    required bool? value,
    required Future<bool> Function() enableAction,
    required Future<bool> Function() disableAction,
    required String enableNotification,
    required String disableNotification,
    required void Function(bool nextValue) updateState,
  }) async {
    if (value == null) return;
    setState(() => isLoading = true);

    final success = value ? await enableAction() : await disableAction();
    if (success) {
      await showWindowsNotification(
        "Vertree",
        value ? enableNotification : disableNotification,
      );
    } else {
      showToast(appLocale.getText(LocaleKey.settingMenuUpdateFailed));
    }

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() {
      if (success) {
        updateState(value);
      }
      isLoading = false;
      legacyMenuEnabled =
          previewFile ||
          backupFile ||
          expressBackupFile ||
          monitorFile ||
          shareFile ||
          viewTreeFile;
    });
    await _showLinuxMenuToggleResult(success);
  }

  @override
  void initState() {
    super.initState();
    _monitorRateController = TextEditingController(
      text: configer.get("monitorRate", 5).toString(),
    );
    _monitorMaxSizeController = TextEditingController(
      text: configer.get("monitorMaxSize", 50).toString(),
    );
    _settingsScrollController = ScrollController();
    _loadPlatformState();
  }

  @override
  void dispose() {
    _monitorRateController.dispose();
    _monitorMaxSizeController.dispose();
    _settingsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPlatformState() async {
    await PlatformIntegration.refreshLinuxCapabilityCache();
    if (PlatformIntegration.isWindows) {
      await PlatformIntegration.migrateLegacyMenuLayoutConfig();
    }
    if (PlatformIntegration.isLinuxGnome) {
      _gnomeFilesSupportInfo =
          await LinuxGnomeIntegration.getFilesMenuSupportInfo();
      _gnomeTraySupportInfo = await LinuxGnomeIntegration.getTraySupportInfo();
    } else {
      _gnomeFilesSupportInfo = null;
      _gnomeTraySupportInfo = null;
    }
    if (PlatformIntegration.supportsContextMenus) {
      previewFile =
          PlatformIntegration.isWindows &&
          await PlatformIntegration.checkPreviewKeyExists();
      backupFile = await PlatformIntegration.checkBackupKeyExists();
      expressBackupFile =
          await PlatformIntegration.checkExpressBackupKeyExists();
      monitorFile = await PlatformIntegration.checkMonitorKeyExists();
      shareFile = await PlatformIntegration.checkShareKeyExists();
      viewTreeFile = await PlatformIntegration.checkViewTreeKeyExists();
      legacyMenuCollapsed = configer.get<bool>('legacyMenuCollapsed', false);
      legacyMenuEnabled =
          previewFile ||
          backupFile ||
          expressBackupFile ||
          monitorFile ||
          shareFile ||
          viewTreeFile;
      if (PlatformIntegration.isWindows) {
        final configuredWin11MenuEnabled = configer.get(
          "win11MenuEnabled",
          true,
        );
        final registeredWin11Menu =
            await PlatformIntegration.checkWin11ContextMenuHandler();
        win11MenuEnabled = configuredWin11MenuEnabled && registeredWin11Menu;
      }
    }
    if (PlatformIntegration.supportsAutoStart) {
      autoStart = await PlatformIntegration.isAutoStartEnabled();
    }
    launchToTray = configer.get<bool>(
      'launch2Tray',
      PlatformIntegration.defaultLaunchToTray,
    );
    if (!_launchToTrayAvailable && launchToTray) {
      launchToTray = false;
      configer.set<bool>('launch2Tray', false);
    }
    localHttpApiEnabled = configer.get<bool>('localHttpApiEnabled', false);
    _themeModeSetting = configer.get<String>('themeMode', 'system');
    _syncMonitorControllers();
    if (!mounted) return;
    setState(() {});
  }

  void _syncMonitorControllers() {
    _setControllerText(
      _monitorRateController,
      configer.get("monitorRate", 5).toString(),
    );
    _setControllerText(
      _monitorMaxSizeController,
      configer.get("monitorMaxSize", 50).toString(),
    );
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _refreshLegacyMenuState() async {
    await _loadPlatformState();
  }

  Future<void> _toggleLegacyMenus(bool? value) async {
    if (value == null) return;
    setState(() => isLoading = true);

    final success = await PlatformIntegration.applyLegacyMenus(
      value,
      collapsed: PlatformIntegration.isWindows ? legacyMenuCollapsed : false,
    );

    if (!success && PlatformIntegration.isWindows) {
      showToast(appLocale.getText(LocaleKey.settingMenuUpdateFailed));
    }
    await _refreshLegacyMenuState();
    if (PlatformIntegration.isLinux) {
      showToast(
        success
            ? appLocale.getText(LocaleKey.settingGnomeMenuRestartHint)
            : appLocale.getText(LocaleKey.settingGnomeMenuUnavailable),
      );
    }
    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _toggleLegacyMenuCollapsed(bool? value) async {
    if (value == null || !PlatformIntegration.isWindows || !legacyMenuEnabled) {
      return;
    }
    setState(() => isLoading = true);
    final success = await PlatformIntegration.setLegacyMenuLayout(value);
    if (!success) {
      showToast(appLocale.getText(LocaleKey.settingMenuUpdateFailed));
    }
    await Future.delayed(const Duration(milliseconds: 200));
    await _refreshLegacyMenuState();
    if (!mounted) return;
    setState(() => isLoading = false);
  }

  Future<void> _toggleWin11Menu(bool? value) async {
    if (value == null) return;
    setState(() => isLoading = true);
    logger.info('Win11 menu toggle start: target=$value');
    try {
      final success = value
          ? await PlatformIntegration.addWin11ContextMenuHandler()
          : await PlatformIntegration.removeWin11ContextMenuHandler();
      if (!success) {
        showToast(appLocale.getText(LocaleKey.settingWin11MenuNeedsIdentity));
        return;
      }

      logger.info('Win11 menu display updated: enabled=$value');
    } catch (e) {
      logger.error('Win11 menu toggle failed: $e');
      showToast(appLocale.getText(LocaleKey.settingWin11MenuNeedsIdentity));
    } finally {
      await Future.delayed(const Duration(milliseconds: 200));
      await _refreshLegacyMenuState();
      if (mounted) {
        setState(() => isLoading = false);
      }
      logger.info('Win11 menu toggle end');
    }
  }

  Future<void> _togglePreviewFile(bool? value) async {
    if (value == null) return;
    setState(() => isLoading = true);
    try {
      final success = value
          ? await PlatformIntegration.addPreviewContextMenu()
          : await PlatformIntegration.removePreviewContextMenu();
      if (!success) {
        showToast(appLocale.getText(LocaleKey.settingMenuUpdateFailed));
      }
      await _refreshLegacyMenuState();
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _toggleBackupFile(bool? value) async {
    await _applyContextMenuToggle(
      value: value,
      enableAction: PlatformIntegration.addBackupContextMenu,
      disableAction: PlatformIntegration.removeBackupContextMenu,
      enableNotification: appLocale.getText(LocaleKey.settingNotifyAddBackup),
      disableNotification: appLocale.getText(
        LocaleKey.settingNotifyRemoveBackup,
      ),
      updateState: (nextValue) => backupFile = nextValue,
    );
  }

  Future<void> _toggleMonitorFile(bool? value) async {
    await _applyContextMenuToggle(
      value: value,
      enableAction: PlatformIntegration.addMonitorContextMenu,
      disableAction: PlatformIntegration.removeMonitorContextMenu,
      enableNotification: appLocale.getText(LocaleKey.settingNotifyAddMonitor),
      disableNotification: appLocale.getText(
        LocaleKey.settingNotifyRemoveMonitor,
      ),
      updateState: (nextValue) => monitorFile = nextValue,
    );
  }

  Future<void> _toggleViewTreeFile(bool? value) async {
    await _applyContextMenuToggle(
      value: value,
      enableAction: PlatformIntegration.addViewTreeContextMenu,
      disableAction: PlatformIntegration.removeViewTreeContextMenu,
      enableNotification: appLocale.getText(LocaleKey.settingNotifyAddView),
      disableNotification: appLocale.getText(LocaleKey.settingNotifyRemoveView),
      updateState: (nextValue) => viewTreeFile = nextValue,
    );
  }

  Future<void> _toggleShareFile(bool? value) async {
    await _applyContextMenuToggle(
      value: value,
      enableAction: PlatformIntegration.addShareContextMenu,
      disableAction: PlatformIntegration.removeShareContextMenu,
      enableNotification: appLocale.getText(LocaleKey.settingNotifyAddShare),
      disableNotification: appLocale.getText(
        LocaleKey.settingNotifyRemoveShare,
      ),
      updateState: (nextValue) => shareFile = nextValue,
    );
  }

  Future<void> _toggleAutoStart(bool? value) async {
    if (value == null) return;
    setState(() => isLoading = true);

    late final bool success;
    if (value) {
      success = await PlatformIntegration.enableAutoStart();
      await showWindowsNotification(
        "Vertree",
        appLocale.getText(LocaleKey.settingNotifyEnableAutostart),
      );
    } else {
      success = await PlatformIntegration.disableAutoStart();
      await showWindowsNotification(
        "Vertree",
        appLocale.getText(LocaleKey.settingNotifyDisableAutostart),
      );
    }

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() {
      if (success) {
        autoStart = value;
      }
      isLoading = false;
    });
  }

  Future<void> _toggleLaunchToTray(bool? value) async {
    if (value == null) return;
    if (value && !_launchToTrayAvailable) {
      final suggestion = _gnomeTraySupportInfo?.installCommand;
      showToast(
        suggestion == null
            ? appLocale.getText(LocaleKey.settingLaunchToTrayUnsupported)
            : appLocale.getText(LocaleKey.settingLaunchToTraySetupHint),
      );
      setState(() {
        launchToTray = false;
      });
      configer.set<bool>('launch2Tray', false);
      return;
    }
    setState(() {
      launchToTray = value;
    });
    configer.set<bool>('launch2Tray', value);
  }

  Future<void> _copyCommand(String command, String successMessage) async {
    await Clipboard.setData(ClipboardData(text: command));
    showToast(successMessage);
  }

  String _statusLabel(GnomeSupportInfo? info) {
    switch (info?.status) {
      case GnomeSupportStatus.available:
        return appLocale.getText(LocaleKey.settingSupportStatusAvailable);
      case GnomeSupportStatus.missingDependency:
        return appLocale.getText(
          LocaleKey.settingSupportStatusMissingDependency,
        );
      case GnomeSupportStatus.installedButDisabled:
        return appLocale.getText(
          LocaleKey.settingSupportStatusInstalledButDisabled,
        );
      case GnomeSupportStatus.unavailable:
        return appLocale.getText(LocaleKey.settingSupportStatusUnavailable);
      case GnomeSupportStatus.unknown:
        return appLocale.getText(LocaleKey.settingSupportStatusUnknown);
      case null:
        return appLocale.getText(LocaleKey.settingSupportStatusChecking);
    }
  }

  Color _statusColor(GnomeSupportInfo? info) {
    final scheme = Theme.of(context).colorScheme;
    switch (info?.status) {
      case GnomeSupportStatus.available:
        return scheme.primary;
      case GnomeSupportStatus.missingDependency:
      case GnomeSupportStatus.installedButDisabled:
        return scheme.tertiary;
      case GnomeSupportStatus.unavailable:
      case GnomeSupportStatus.unknown:
      case null:
        return scheme.outline;
    }
  }

  Future<void> _toggleLocalHttpApi(bool? value) async {
    if (value == null) return;
    setState(() => isLoading = true);

    configer.set<bool>('localHttpApiEnabled', value);
    try {
      await localHttpApiServer.syncWithConfig();
    } catch (e) {
      logger.error('Local HTTP API toggle failed: $e');
      showToast(
        appLocale.getText(LocaleKey.settingLocalHttpApiToggleFailed).tr([
          e.toString(),
        ]),
      );
      configer.set<bool>('localHttpApiEnabled', !value);
    }

    await _loadPlatformState();
    if (!mounted) return;
    setState(() => isLoading = false);
  }

  Future<void> _toggleExpressBackupFile(bool? value) async {
    await _applyContextMenuToggle(
      value: value,
      enableAction: PlatformIntegration.addExpressBackupContextMenu,
      disableAction: PlatformIntegration.removeExpressBackupContextMenu,
      enableNotification: appLocale.getText(LocaleKey.settingNotifyAddExpress),
      disableNotification: appLocale.getText(
        LocaleKey.settingNotifyRemoveExpress,
      ),
      updateState: (nextValue) => expressBackupFile = nextValue,
    );
  }

  void _updateLanguage(Lang lang) {
    setState(() {
      appLocale.changeLang(lang);
    });
    unawaited(TrayManager().refreshTray(forceRebuild: true));
  }

  void _updateThemeMode(String value) {
    setState(() {
      _themeModeSetting = value;
    });
    switch (value) {
      case 'system':
        updateThemeSetting(AppThemeSetting.system);
        break;
      case 'light':
        updateThemeSetting(AppThemeSetting.light);
        break;
      case 'dark':
        updateThemeSetting(AppThemeSetting.dark);
        break;
    }
  }

  void _handleIntegerSettingChanged(String key, String value) {
    final parsed = int.tryParse(value);
    if (parsed != null && parsed > 0) {
      configer.set(key, parsed);
    }
  }

  void _finalizeIntegerSetting(
    String key,
    TextEditingController controller,
    int fallback,
  ) {
    final parsed = int.tryParse(controller.text);
    if (parsed != null && parsed > 0) {
      configer.set(key, parsed);
    }
    final current = configer.get(key, fallback).toString();
    _setControllerText(controller, current);
  }

  void _openUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw appLocale.getText(LocaleKey.settingOpenUrlFailed).tr([url]);
    }
  }

  List<Widget> _withDividers(List<Widget> children) {
    final result = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i != children.length - 1) {
        result.add(const SizedBox(height: 14));
      }
    }
    return result;
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: Card.outlined(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ..._withDividers(children),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedPreference<T>({
    required IconData icon,
    required String title,
    required Set<T> selected,
    required List<ButtonSegment<T>> segments,
    required ValueChanged<T> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: SegmentedButton<T>(
                segments: segments,
                selected: selected,
                showSelectedIcon: false,
                expandedInsets: EdgeInsets.zero,
                onSelectionChanged: (values) {
                  if (values.isEmpty) return;
                  onSelected(values.first);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    IconData? icon,
    Widget? leading,
    required String title,
    required bool value,
    required ValueChanged<bool?>? onChanged,
  }) {
    return _buildSettingRow(
      icon: icon,
      leading: leading,
      title: Text(title),
      trailing: Switch(value: value, onChanged: onChanged),
      onTap: onChanged == null ? null : () => onChanged(!value),
    );
  }

  Widget _buildSettingRow({
    IconData? icon,
    Widget? leading,
    required Widget title,
    Widget? supportingText,
    Widget? trailing,
    VoidCallback? onTap,
    bool topAlignLeading = false,
  }) {
    assert(icon != null || leading != null);
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

  Widget _buildSubsectionCard({
    required IconData icon,
    required String title,
    Widget? trailing,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: Card.filled(
        color: scheme.surfaceContainerLowest,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[trailing],
                ],
              ),
              const SizedBox(height: 12),
              ..._withDividers(children),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommandButton({
    required IconData icon,
    required String label,
    required String command,
  }) {
    return FilledButton.tonalIcon(
      onPressed: () => _copyCommand(
        command,
        appLocale.getText(LocaleKey.settingCommandCopied),
      ),
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Widget _buildGnomeSupportCard({
    required IconData icon,
    required String title,
    required GnomeSupportInfo? info,
    required List<Widget> commands,
  }) {
    final color = _statusColor(info);
    return _buildSubsectionCard(
      icon: icon,
      title: title,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: color),
              const SizedBox(width: 10),
              Text(
                _statusLabel(info),
                style: TextStyle(fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            (info?.message.isNotEmpty ?? false)
                ? info!.message
                : appLocale.getText(
                    LocaleKey.settingDetectingPlatformIntegration,
                  ),
          ),
        ),
        if (commands.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 12, runSpacing: 12, children: commands),
          ),
      ],
    );
  }

  Widget _buildIntegerSettingTile({
    required IconData icon,
    required String title,
    required TextEditingController controller,
    required String configKey,
    required int fallback,
  }) {
    return _buildSettingRow(
      icon: icon,
      title: Text(title),
      topAlignLeading: true,
      trailing: SizedBox(
        width: 120,
        child: TextFormField(
          controller: controller,
          mouseCursor: SystemMouseCursors.text,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.end,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: (value) => _handleIntegerSettingChanged(configKey, value),
          onEditingComplete: () {
            _finalizeIntegerSetting(configKey, controller, fallback);
            FocusScope.of(context).unfocus();
          },
          onFieldSubmitted: (_) {
            _finalizeIntegerSetting(configKey, controller, fallback);
          },
          onTapOutside: (_) {
            _finalizeIntegerSetting(configKey, controller, fallback);
            FocusScope.of(context).unfocus();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contextMenuGroupTitle = PlatformIntegration.isLinux
        ? appLocale.getText(LocaleKey.settingLinuxContextMenuGroup)
        : appLocale.getText(LocaleKey.settingContextMenuGroup);
    final gnomeTrayCommands = <Widget>[
      if (_gnomeTraySupportInfo?.installCommand case final installCommand?)
        _buildCommandButton(
          icon: Icons.content_copy_rounded,
          label:
              (_gnomeTraySupportInfo?.installCommandLabel?.isNotEmpty ?? false)
              ? _gnomeTraySupportInfo!.installCommandLabel!
              : appLocale.getText(LocaleKey.settingCopyConfigCommand),
          command: installCommand,
        ),
      if (_gnomeTraySupportInfo?.restartCommand case final restartCommand?)
        _buildCommandButton(
          icon: Icons.restart_alt_rounded,
          label:
              (_gnomeTraySupportInfo?.restartCommandLabel?.isNotEmpty ?? false)
              ? _gnomeTraySupportInfo!.restartCommandLabel!
              : appLocale.getText(LocaleKey.settingCopyAssistCommand),
          command: restartCommand,
        ),
    ];
    final windowsWin11IdentityCommands = <Widget>[
      if (_windowsWin11IdentityInfo.installCommand case final installCommand?)
        _buildCommandButton(
          icon: Icons.content_copy_rounded,
          label:
              (_windowsWin11IdentityInfo.installCommandLabel?.isNotEmpty ??
                  false)
              ? _windowsWin11IdentityInfo.installCommandLabel!
              : appLocale.getText(LocaleKey.settingCopyRegisterCommand),
          command: installCommand,
        ),
      if (_windowsWin11IdentityInfo.restartCommand case final restartCommand?)
        _buildCommandButton(
          icon: Icons.restart_alt_rounded,
          label:
              (_windowsWin11IdentityInfo.restartCommandLabel?.isNotEmpty ??
                  false)
              ? _windowsWin11IdentityInfo.restartCommandLabel!
              : appLocale.getText(LocaleKey.settingCopyRefreshCommand),
          command: restartCommand,
        ),
    ];
    return LoadingWidget(
      isLoading: isLoading,
      child: Scaffold(
        appBar: VAppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.settings_rounded, size: 18),
              const SizedBox(width: 8),
              Text(appLocale.getText(LocaleKey.settingTitleBar)),
            ],
          ),
        ),
        body: AppPageBackground(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Scrollbar(
                  controller: _settingsScrollController,
                  child: ListView(
                    controller: _settingsScrollController,
                    children: [
                      if (_shouldShowEnvironmentInfoSection) ...[
                        _buildSection(
                          icon: Icons.info_outline_rounded,
                          title: appLocale.getText(
                            LocaleKey.settingEnvironmentGroup,
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                appLocale.getText(
                                  LocaleKey.settingEnvironmentDescription,
                                ),
                              ),
                            ),
                            if (_shouldShowGnomeTraySupportCard)
                              _buildGnomeSupportCard(
                                icon: Icons.notifications_active_outlined,
                                title: appLocale.getText(
                                  LocaleKey.settingTraySupportTitle,
                                ),
                                info: _gnomeTraySupportInfo,
                                commands: gnomeTrayCommands,
                              ),
                            if (_shouldShowWindowsWin11IdentityCard)
                              _buildGnomeSupportCard(
                                icon: Icons.apps_outlined,
                                title: appLocale.getText(
                                  LocaleKey.settingWin11MenuEnvironmentTitle,
                                ),
                                info: _windowsWin11IdentityInfo,
                                commands: windowsWin11IdentityCommands,
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildSection(
                        icon: Icons.palette_outlined,
                        title: appLocale.getText(
                          LocaleKey.settingAppearanceGroup,
                        ),
                        children: [
                          _buildSegmentedPreference<Lang>(
                            icon: Icons.language_rounded,
                            title: appLocale.getText(LocaleKey.settingLanguage),
                            selected: {appLocale.lang},
                            segments: appLocale.supportedLangs
                                .map(
                                  (lang) => ButtonSegment<Lang>(
                                    value: lang,
                                    label: Text(lang.label),
                                  ),
                                )
                                .toList(),
                            onSelected: _updateLanguage,
                          ),
                          _buildSegmentedPreference<String>(
                            icon: Icons.dark_mode_rounded,
                            title: appLocale.getText(
                              LocaleKey.settingThemeModeLabel,
                            ),
                            selected: {_themeModeSetting},
                            segments: [
                              ButtonSegment<String>(
                                value: 'system',
                                icon: const Icon(Icons.brightness_auto_rounded),
                                label: Text(
                                  appLocale.getText(
                                    LocaleKey.settingThemeModeSystem,
                                  ),
                                ),
                              ),
                              ButtonSegment<String>(
                                value: 'light',
                                icon: const Icon(Icons.light_mode_rounded),
                                label: Text(
                                  appLocale.getText(
                                    LocaleKey.settingThemeModeLight,
                                  ),
                                ),
                              ),
                              ButtonSegment<String>(
                                value: 'dark',
                                icon: const Icon(Icons.dark_mode_rounded),
                                label: Text(
                                  appLocale.getText(
                                    LocaleKey.settingThemeModeDark,
                                  ),
                                ),
                              ),
                            ],
                            onSelected: _updateThemeMode,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (PlatformIntegration.supportsContextMenus ||
                          PlatformIntegration.supportsAutoStart) ...[
                        _buildSection(
                          icon: Icons.extension_outlined,
                          title: appLocale.getText(
                            LocaleKey.settingIntegrationsGroup,
                          ),
                          children: [
                            if (PlatformIntegration.isWindows)
                              _buildSwitchTile(
                                icon: Icons.apps_rounded,
                                title: contextMenuGroupTitle,
                                value: win11MenuEnabled,
                                onChanged: _toggleWin11Menu,
                              ),
                            if (PlatformIntegration.supportsContextMenus)
                              _buildSubsectionCard(
                                icon: Icons.history_toggle_off_rounded,
                                title: PlatformIntegration.isLinux
                                    ? contextMenuGroupTitle
                                    : "$contextMenuGroupTitle${appLocale.getText(LocaleKey.settingContextMenuLegacySuffix)}",
                                trailing: IconButton.filledTonal(
                                  onPressed: () {
                                    setState(() {
                                      _showLegacyMenuDetails =
                                          !_showLegacyMenuDetails;
                                    });
                                  },
                                  icon: Icon(
                                    _showLegacyMenuDetails
                                        ? Icons.expand_less_rounded
                                        : Icons.expand_more_rounded,
                                  ),
                                ),
                                children: [
                                  _buildSwitchTile(
                                    icon: Icons.toggle_on_rounded,
                                    title: PlatformIntegration.isLinux
                                        ? _linuxContextMenuToggleTitle
                                        : appLocale.getText(
                                            LocaleKey.settingContextMenuToggle,
                                          ),
                                    value: legacyMenuEnabled,
                                    onChanged: _toggleLegacyMenus,
                                  ),
                                  if (PlatformIntegration.isWindows)
                                    _buildSwitchTile(
                                      icon: Icons
                                          .subdirectory_arrow_right_rounded,
                                      title: appLocale.getText(
                                        LocaleKey
                                            .settingLegacyMenuCollapseToggle,
                                      ),
                                      value: legacyMenuCollapsed,
                                      onChanged: legacyMenuEnabled
                                          ? _toggleLegacyMenuCollapsed
                                          : null,
                                    ),
                                  AnimatedCrossFade(
                                    duration: const Duration(milliseconds: 180),
                                    crossFadeState: _showLegacyMenuDetails
                                        ? CrossFadeState.showSecond
                                        : CrossFadeState.showFirst,
                                    firstChild: const SizedBox.shrink(),
                                    secondChild: Column(
                                      children: [
                                        if (PlatformIntegration.isWindows)
                                          _buildSwitchTile(
                                            icon: Icons.preview_outlined,
                                            title: appLocale.getText(
                                              LocaleKey.settingAddPreviewMenu,
                                            ),
                                            value: previewFile,
                                            onChanged: _togglePreviewFile,
                                          ),
                                        _buildSwitchTile(
                                          icon: Icons.save_outlined,
                                          title: appLocale.getText(
                                            LocaleKey.settingAddBackupMenu,
                                          ),
                                          value: backupFile,
                                          onChanged: _toggleBackupFile,
                                        ),
                                        _buildSwitchTile(
                                          icon: Icons.flash_on_outlined,
                                          title: appLocale.getText(
                                            LocaleKey
                                                .settingAddExpressBackupMenu,
                                          ),
                                          value: expressBackupFile,
                                          onChanged: _toggleExpressBackupFile,
                                        ),
                                        _buildSwitchTile(
                                          icon: Icons.monitor_heart_outlined,
                                          title: appLocale.getText(
                                            LocaleKey.settingAddMonitorMenu,
                                          ),
                                          value: monitorFile,
                                          onChanged: _toggleMonitorFile,
                                        ),
                                        _buildSwitchTile(
                                          leading: shareActionImage(size: 20),
                                          title: appLocale.getText(
                                            LocaleKey.settingAddShareMenu,
                                          ),
                                          value: shareFile,
                                          onChanged: _toggleShareFile,
                                        ),
                                        _buildSwitchTile(
                                          icon: Icons.account_tree_outlined,
                                          title: appLocale.getText(
                                            LocaleKey.settingAddViewtreeMenu,
                                          ),
                                          value: viewTreeFile,
                                          onChanged: _toggleViewTreeFile,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            if (PlatformIntegration.supportsAutoStart)
                              _buildSwitchTile(
                                icon: Icons.move_to_inbox_outlined,
                                title: _launchToTrayAvailable
                                    ? _launchBehaviorTitle
                                    : appLocale.getText(
                                        LocaleKey
                                            .settingLaunchToTrayUnsupported,
                                      ),
                                value: launchToTray,
                                onChanged: _launchToTrayAvailable
                                    ? _toggleLaunchToTray
                                    : null,
                              ),
                            if (PlatformIntegration.supportsAutoStart)
                              _buildSwitchTile(
                                icon: Icons.power_settings_new_rounded,
                                title: appLocale.getText(
                                  LocaleKey.settingEnableAutostart,
                                ),
                                value: autoStart,
                                onChanged: _toggleAutoStart,
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildSection(
                        icon: Icons.monitor_heart_outlined,
                        title: appLocale.getText(LocaleKey.settingMonitGroup),
                        children: [
                          _buildIntegerSettingTile(
                            icon: Icons.schedule_rounded,
                            title: appLocale.getText(
                              LocaleKey.settingMonitRate,
                            ),
                            controller: _monitorRateController,
                            configKey: "monitorRate",
                            fallback: 5,
                          ),
                          _buildIntegerSettingTile(
                            icon: Icons.inventory_2_outlined,
                            title: appLocale.getText(
                              LocaleKey.settingMonitMaxSize,
                            ),
                            controller: _monitorMaxSizeController,
                            configKey: "monitorMaxSize",
                            fallback: 50,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildSection(
                        icon: Icons.hub_outlined,
                        title: appLocale.getText(LocaleKey.settingHttpApiGroup),
                        children: [
                          _buildSwitchTile(
                            icon: Icons.lan_rounded,
                            title: appLocale.getText(
                              LocaleKey.settingEnableLocalHttpApi,
                            ),
                            value: localHttpApiEnabled,
                            onChanged: _toggleLocalHttpApi,
                          ),
                          _buildSettingRow(
                            icon: Icons.info_outline_rounded,
                            topAlignLeading: true,
                            title: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    appLocale
                                        .getText(LocaleKey.settingHttpApiStatus)
                                        .tr([
                                          localHttpApiServer.isRunning
                                              ? appLocale.getText(
                                                  LocaleKey
                                                      .settingHttpApiRunning,
                                                )
                                              : appLocale.getText(
                                                  LocaleKey
                                                      .settingHttpApiStopped,
                                                ),
                                        ]),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  localHttpApiServer.isRunning
                                      ? Icons.check_circle_rounded
                                      : Icons.pause_circle_outline_rounded,
                                  size: 18,
                                  color: localHttpApiServer.isRunning
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                            supportingText: localHttpApiServer.isRunning
                                ? InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () => _openUrl(
                                      localHttpApiServer.baseUrl ??
                                          'http://127.0.0.1:${localHttpApiServer.port ?? LocalHttpApiServer.defaultPort}/api/v1',
                                    ),
                                    child: Text(
                                      localHttpApiServer.baseUrl ??
                                          'http://127.0.0.1:${localHttpApiServer.port ?? LocalHttpApiServer.defaultPort}/api/v1',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: localHttpApiServer.docsUrl == null
                                      ? null
                                      : () => _openUrl(
                                          localHttpApiServer.docsUrl!,
                                        ),
                                  icon: const Icon(
                                    Icons.open_in_browser_rounded,
                                  ),
                                  label: Text(
                                    appLocale.getText(
                                      LocaleKey.settingHttpApiDocs,
                                    ),
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: localHttpApiServer.isRunning
                                      ? () async {
                                          await Clipboard.setData(
                                            ClipboardData(
                                              text: localHttpApiServer
                                                  .accessToken,
                                            ),
                                          );
                                          showToast(
                                            appLocale.getText(
                                              LocaleKey
                                                  .settingHttpApiTokenCopied,
                                            ),
                                          );
                                        }
                                      : null,
                                  icon: const Icon(Icons.key_rounded),
                                  label: Text(
                                    appLocale.getText(
                                      LocaleKey.settingHttpApiCopyToken,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildSection(
                        icon: Icons.folder_outlined,
                        title: appLocale.getText(
                          LocaleKey.settingResourcesGroup,
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Tooltip(
                                  message: appLocale.getText(
                                    LocaleKey.settingVersionInfo,
                                  ),
                                  child: AppVersionDisplay(
                                    appVersion: appVersionInfo.currentVersion,
                                    defaultLink:
                                        "https://github.com/w0fv1/vertree/releases",
                                    checkNewVersion: () async {
                                      final Result<UpdateInfo, String>
                                      checkUpdateResult = await appVersionInfo
                                          .checkUpdate();

                                      if (checkUpdateResult.isErr) {
                                        logger.error(checkUpdateResult.msg);
                                        return false;
                                      }

                                      final hasNewVersion = checkUpdateResult
                                          .unwrap()
                                          .hasUpdate;
                                      final newVersionTag = checkUpdateResult
                                          .unwrap()
                                          .latestVersionTag;

                                      if (hasNewVersion &&
                                          newVersionTag != null &&
                                          newVersionTag.isNotEmpty) {
                                        showToast(
                                          appLocale
                                              .getText(
                                                LocaleKey.settingHasNewVertion,
                                              )
                                              .tr([newVersionTag]),
                                        );
                                      }
                                      return hasNewVersion;
                                    },
                                    getNewVersionDownloadUrl: () async {
                                      final Result<String?, String>
                                      checkUpdateResult = await appVersionInfo
                                          .getPreferredDownloadUrl();
                                      if (checkUpdateResult.isErr) {
                                        logger.info(checkUpdateResult.msg);
                                        return "https://github.com/w0fv1/vertree/releases";
                                      }
                                      return checkUpdateResult.unwrap();
                                    },
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: () => FileUtils.openFile(
                                        configer.configFilePath,
                                      ),
                                      icon: const Icon(
                                        Icons.description_outlined,
                                      ),
                                      label: Text(
                                        appLocale.getText(
                                          LocaleKey.settingOpenConfig,
                                        ),
                                      ),
                                    ),
                                    FilledButton.tonalIcon(
                                      onPressed: () => FileUtils.openFolder(
                                        logger.logDirPath,
                                      ),
                                      icon: const Icon(
                                        Icons.receipt_long_outlined,
                                      ),
                                      label: Text(
                                        appLocale.getText(
                                          LocaleKey.settingOpenLogs,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: () => _openUrl(
                                        "https://vertree.w0fv1.dev/",
                                      ),
                                      icon: const Icon(Icons.language_rounded),
                                      label: Text(
                                        appLocale.getText(
                                          LocaleKey.settingVisitWebsite,
                                        ),
                                      ),
                                    ),
                                    FilledButton.tonalIcon(
                                      onPressed: () => _openUrl(
                                        "https://github.com/w0fv1/vertree",
                                      ),
                                      icon: const Icon(
                                        MaterialCommunityIcons.github,
                                      ),
                                      label: Text(
                                        appLocale.getText(
                                          LocaleKey.settingOpenGithub,
                                        ),
                                      ),
                                    ),
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        textStyle: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      onPressed: () => _openUrl(
                                        "https://next.firco.cn/w0fv1?focusProduct=product-8283788fa5724d25ae65958d1b61b288",
                                      ),
                                      icon: const Icon(
                                        Icons.volunteer_activism_rounded,
                                      ),
                                      label: Text(
                                        appLocale.getText(
                                          LocaleKey.settingDonate,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
}
