import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vertree/adapters/ui/desktop_scope.dart';
import 'package:vertree/view/page/brand_page.dart';
import 'package:window_manager/window_manager.dart';

class VAppBar extends StatefulWidget implements PreferredSizeWidget {
  final double height;
  final Widget title;
  final bool showMinimize;
  final bool showMaximize;
  final bool showClose;
  final bool goHome;

  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final VoidCallback? onRestore;
  final VoidCallback? onClose;

  const VAppBar({
    super.key,
    this.height = 40,
    required this.title,
    this.showMinimize = true,
    this.showMaximize = true,
    this.showClose = true,
    this.goHome = true,
    this.onMinimize,
    this.onMaximize,
    this.onRestore,
    this.onClose,
  });

  @override
  State<VAppBar> createState() => _VAppBarState();

  @override
  Size get preferredSize => Size(double.infinity, height);
}

class _VAppBarState extends State<VAppBar> with WindowListener {
  late final DesktopDependencies _desktop;

  bool isExpanded = false;

  @override
  void initState() {
    _desktop = DesktopScope.read(context);
    super.initState();
    windowManager.addListener(this);
    _syncWindowState();
  }

  Future<void> _syncWindowState() async {
    final expanded =
        await windowManager.isFullScreen() || await windowManager.isMaximized();
    if (!mounted) {
      return;
    }
    setState(() {
      isExpanded = expanded;
    });
  }

  Future<void> _toggleWindowMode() async {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
      if (widget.onRestore != null) {
        widget.onRestore!();
      }
    } else {
      if (await windowManager.isMaximized()) {
        await windowManager.restore();
      }
      await windowManager.setFullScreen(true);
      if (widget.onMaximize != null) {
        widget.onMaximize!();
      }
    }
    await _syncWindowState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => _syncWindowState();

  @override
  void onWindowUnmaximize() => _syncWindowState();

  @override
  void onWindowEnterFullScreen() => _syncWindowState();

  @override
  void onWindowLeaveFullScreen() => _syncWindowState();

  @override
  void onWindowRestore() => _syncWindowState();

  @override
  Widget build(BuildContext context) {
    final bool isMacOS = Platform.isMacOS;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(4),
        color: Colors.transparent,
        child: isMacOS ? _buildMacLayout() : _buildDefaultLayout(),
      ),
    );
  }

  Widget _buildMacLayout() {
    const double trafficLightInset = 72;
    final bool showThemeToggle =
        _desktop.currentThemeSetting != AppThemeSetting.system;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final IconData themeIcon = isDark
        ? Icons.light_mode_rounded
        : Icons.dark_mode_rounded;

    return Row(
      children: [
        const SizedBox(width: trafficLightInset),
        if (widget.goHome) ...[
          _buildAppBarButton(Icons.home_rounded, () async {
            _desktop.go(BrandPage());
          }),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: _buildDragArea(
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: widget.title,
              ),
            ),
          ),
        ),
        if (showThemeToggle)
          _buildAppBarButton(themeIcon, () {
            _desktop.toggleLightDarkTheme();
          }),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildDefaultLayout() {
    final bool showThemeToggle =
        _desktop.currentThemeSetting != AppThemeSetting.system;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final IconData themeIcon = isDark
        ? Icons.light_mode_rounded
        : Icons.dark_mode_rounded;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final windowButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showMinimize)
          _buildAppBarButton(Icons.remove, () async {
            await windowManager.minimize();
            if (widget.onMinimize != null) {
              widget.onMinimize!();
            }
          }),
        if (widget.showMinimize) const SizedBox(width: 6),
        if (widget.showMaximize)
          _buildAppBarButton(
            isExpanded
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            _toggleWindowMode,
          ),
        if (widget.showMaximize) const SizedBox(width: 6),
        if (widget.showClose)
          _buildAppBarButton(Icons.close, () async {
            await windowManager.close();
            if (widget.onClose != null) {
              widget.onClose!();
            }
          }, color: scheme.error),
      ],
    );

    return Row(
      children: [
        if (widget.goHome) ...[
          _buildAppBarButton(Icons.home_rounded, () async {
            _desktop.go(BrandPage());
          }),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: _buildDragArea(
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: widget.title,
              ),
            ),
          ),
        ),
        if (showThemeToggle)
          _buildAppBarButton(themeIcon, () {
            _desktop.toggleLightDarkTheme();
          }),
        if (showThemeToggle) const SizedBox(width: 8),
        windowButtons,
      ],
    );
  }

  Widget _buildDragArea(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: _toggleWindowMode,
      child: DragToMoveArea(child: child),
    );
  }

  Widget _buildAppBarButton(
    IconData icon,
    VoidCallback onPressed, {
    Color? color,
    double padding = 5,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color effectiveColor =
        color ?? scheme.onSurfaceVariant.withValues(alpha: 0.9);
    double size = widget.height - 8;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: IconButton(
        constraints: BoxConstraints.tightFor(width: size, height: size),
        padding: EdgeInsets.all(padding),
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: size / 3 * 2 - padding - 1,
          color: effectiveColor,
        ),
      ),
    );
  }
}
