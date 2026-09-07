import 'package:flutter/material.dart';
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/component/notifier.dart';
import 'package:vertree/component/themed_assets.dart';
import 'package:vertree/adapters/ui/versions/file_version_tree.dart';
import 'package:vertree/modules/versions/versions.dart';
import 'package:vertree/foundation/result.dart';
import 'package:vertree/adapters/ui/versions/tree_builder.dart';
import 'package:vertree/adapters/ui/desktop_scope.dart';
import 'package:vertree/view/component/app_bar.dart';
import 'package:vertree/view/component/app_page_background.dart';
import 'package:vertree/view/component/loading.dart';
import 'package:vertree/view/module/file_tree.dart';
import 'package:window_manager/window_manager.dart';

class FileTreePage extends StatefulWidget {
  const FileTreePage({
    super.key,
    required this.path,
    this.viewportController,
    this.initialScale,
    this.fitToViewportOnLoad = false,
  });

  final String path;
  final FileTreeViewportController? viewportController;
  final double? initialScale;
  final bool fitToViewportOnLoad;

  @override
  State<FileTreePage> createState() => _FileTreePageState();
}

class _FileTreePageState extends State<FileTreePage> {
  late final DesktopDependencies _desktop;

  late String path = widget.path;
  late FileNode focusNode;
  FileNode? rootNode;
  bool isLoading = true;

  String _formatVersionSummary(FileVersion version) {
    return "${_desktop.appLocale.getText(LocaleKey.fileleafBranchLabel)} ${version.branchPath} · "
        "${_desktop.appLocale.getText(LocaleKey.fileleafRevisionLabel)} ${version.revisionNumber}";
  }

  int _countNodes(FileNode node) {
    var total = 1;
    if (node.child != null) {
      total += _countNodes(node.child!);
    }
    for (final branch in node.branches) {
      total += _countNodes(branch);
    }
    return total;
  }

  int _countBranchNodes(FileNode node) {
    var total = node.branches.length;
    if (node.child != null) {
      total += _countBranchNodes(node.child!);
    }
    for (final branch in node.branches) {
      total += _countBranchNodes(branch);
    }
    return total;
  }

  FileNode _findLatestNode(FileNode node) {
    FileNode latest = node;
    if (node.child != null) {
      final childLatest = _findLatestNode(node.child!);
      if (childLatest.mate.version.compareTo(latest.mate.version) > 0) {
        latest = childLatest;
      }
    }
    for (final branch in node.branches) {
      final branchLatest = _findLatestNode(branch);
      if (branchLatest.mate.version.compareTo(latest.mate.version) > 0) {
        latest = branchLatest;
      }
    }
    return latest;
  }

  Widget _buildStatChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 156, maxWidth: 228),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewContent(BuildContext context, FileNode root) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final latestNode = _findLatestNode(root);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "${root.mate.name} ${_desktop.appLocale.getText(LocaleKey.vertreeOverviewTitle)}",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            path,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildStatChip(
                context,
                icon: Icons.my_location_rounded,
                label: _desktop.appLocale.getText(
                  LocaleKey.vertreeFocusVersion,
                ),
                value: _formatVersionSummary(focusNode.mate.version),
              ),
              _buildStatChip(
                context,
                icon: Icons.update_rounded,
                label: _desktop.appLocale.getText(
                  LocaleKey.vertreeLatestVersion,
                ),
                value: _formatVersionSummary(latestNode.mate.version),
              ),
              _buildStatChip(
                context,
                icon: Icons.hub_outlined,
                label: _desktop.appLocale.getText(LocaleKey.vertreeTotalNodes),
                value: _countNodes(root).toString(),
              ),
              _buildStatChip(
                context,
                icon: Icons.call_split_rounded,
                label: _desktop.appLocale.getText(
                  LocaleKey.vertreeTotalBranches,
                ),
                value: _countBranchNodes(root).toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showOverviewDialog(BuildContext context, FileNode root) async {
    final scheme = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _buildOverviewContent(dialogContext, root),
          ),
        );
      },
    );
  }

  Widget _buildCanvasPanel(BuildContext context, FileNode root) {
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: scheme.surfaceContainerLowest,
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return FileTree(
                    rootNode: root,
                    focusNode: focusNode,
                    height: constraints.maxHeight,
                    width: constraints.maxWidth,
                    viewportController: widget.viewportController,
                    initialScale: widget.initialScale,
                    fitToViewportOnLoad: widget.fitToViewportOnLoad,
                  );
                },
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Card.filled(
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.94),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: IconButton.filledTonal(
                    tooltip: _desktop.appLocale.getText(
                      LocaleKey.vertreeOverviewTitle,
                    ),
                    icon: const Icon(Icons.info_outline_rounded),
                    onPressed: () {
                      _showOverviewDialog(context, root);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncWindowState() async {
    final fileTreeWindowsStatus = _desktop.configer.get(
      "fileTreeWindowsStatus",
      "fullscreen",
    );
    final shouldUseFullScreen =
        fileTreeWindowsStatus == "maximize" ||
        fileTreeWindowsStatus == "fullscreen";
    final isFullScreen = await windowManager.isFullScreen();

    if (shouldUseFullScreen && !isFullScreen) {
      await windowManager.setFullScreen(true);
    } else if (!shouldUseFullScreen && isFullScreen) {
      await windowManager.setFullScreen(false);
    }
  }

  @override
  void initState() {
    _desktop = DesktopScope.read(context);
    focusNode = FileNode(path);

    super.initState();
    _syncWindowState();

    Future.wait([
      buildTree(path, _desktop.catalog),
      Future.delayed(Duration(milliseconds: 200)),
    ]).then((results) {
      if (!mounted) return;
      Result<FileNode, String> buildTreeResult = results[0];
      if (buildTreeResult.isErr) {
        showToast(buildTreeResult.msg);
        setState(() => isLoading = false);
        return;
      }
      final diagnostics = buildTreeResult.unwrap().diagnostics;
      if (diagnostics.isNotEmpty) showToast(diagnostics.join("\n"));
      setState(() {
        rootNode = buildTreeResult.unwrap();
        isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: VAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            themedLogoImage(context: context, width: 18, height: 18),
            const SizedBox(width: 8),
            Text(
              _desktop.appLocale.getText(LocaleKey.vertreeFileTreeTitle).tr([
                rootNode?.mate.name ?? "",
                rootNode?.mate.extension ?? "",
              ]),
            ),
          ],
        ),
        onMinimize: () {
          _desktop.logger.info('Window minimized');
        },
        onMaximize: () {
          _desktop.configer.set("fileTreeWindowsStatus", "fullscreen");
        },
        onRestore: () {
          _desktop.configer.set("fileTreeWindowsStatus", "windowed");
        },
        onClose: () {
          _desktop.logger.info('Window closed');
        },
      ),
      body: AppPageBackground(
        child: LoadingWidget(
          isLoading: isLoading,
          child: rootNode == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildCanvasPanel(context, rootNode!),
                ),
        ),
      ),
    );
  }
}
