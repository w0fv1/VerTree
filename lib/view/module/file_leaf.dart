import 'package:flutter/material.dart';

import 'package:vertree/component/file_utils.dart';
import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/component/notifier.dart';
import 'package:vertree/component/themed_assets.dart';
import 'package:vertree/core/file_version_tree.dart';
import 'package:vertree/main.dart';
import 'package:vertree/view/component/tree/canvas_component.dart';

class FileLeaf extends CanvasComponent {
  static const double minCardWidth = 240;
  static const double maxCardWidth = 320;
  static const double cardHorizontalPadding = 26;
  static const double titleTrailingWidth = 46;
  static const double defaultTagHeight = 30;
  static const double cardRadius = 22;
  static const double edgeActionInset = 24;
  static const double edgeActionButtonSize = 30;
  static const double edgeActionHitSize = 44;

  FileLeaf(
    this.fileNode, {
    required this.sprout,
    required this.backupNode,
    required this.branchNode,
    super.key,
    super.componentId,
    required super.position,
    required super.treeCanvasManager,
    required this.preferredWidth,
    this.isFocused = false,
    this.animateEntry = false,
  });

  final FileNode fileNode;
  final double preferredWidth;
  final bool isFocused;
  final bool animateEntry;

  final void Function(
    FileNode parentNode,
    Offset parentPosition,
    GlobalKey<CanvasComponentState> parentKey,
  )
  sprout;
  final void Function(
    FileNode parentNode,
    Offset parentPosition,
    GlobalKey<CanvasComponentState> parentKey,
  )
  backupNode;
  final void Function(
    FileNode parentNode,
    Offset parentPosition,
    GlobalKey<CanvasComponentState> parentKey,
  )
  branchNode;

  static String _displayLabel(FileNode fileNode) {
    final label = fileNode.mate.label?.trim();
    if (label == null || label.isEmpty) {
      return appLocale.getText(LocaleKey.fileleafNoLabel);
    }
    return label;
  }

  static double estimateWidth(BuildContext context, FileNode fileNode) {
    final theme = Theme.of(context);
    final direction = Directionality.of(context);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final bodyStyle = theme.textTheme.bodyMedium;
    final chipStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    double measure(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        maxLines: 1,
      )..layout();
      return painter.width;
    }

    final branchText =
        "${appLocale.getText(LocaleKey.fileleafBranchLabel)} ${fileNode.version.branchPath}";
    final revisionText =
        "${appLocale.getText(LocaleKey.fileleafRevisionLabel)} ${fileNode.version.revisionNumber}";

    final titleWidth =
        measure(fileNode.mate.fullName, titleStyle) +
        titleTrailingWidth +
        cardHorizontalPadding;
    final labelWidth =
        measure(_displayLabel(fileNode), bodyStyle) * 0.64 +
        cardHorizontalPadding;
    final tagsWidth =
        measure(branchText, chipStyle) + measure(revisionText, chipStyle) + 84;

    final resolvedWidth = [
      minCardWidth,
      titleWidth,
      labelWidth,
      tagsWidth,
    ].reduce((value, element) => value > element ? value : element);
    return resolvedWidth.clamp(minCardWidth, maxCardWidth);
  }

  static Size estimateSize(BuildContext context, FileNode fileNode) {
    final theme = Theme.of(context);
    final direction = Directionality.of(context);
    final width = estimateWidth(context, fileNode);
    final labelText = _displayLabel(fileNode);

    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.3);
    final chipStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    double measureHeight(
      String text,
      TextStyle? style,
      double maxWidth,
      int maxLines,
    ) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        maxLines: maxLines,
        ellipsis: '...',
      )..layout(maxWidth: maxWidth);
      return painter.height;
    }

    final titleMaxWidth = width - cardHorizontalPadding - titleTrailingWidth;
    final titleHeight = measureHeight(
      fileNode.mate.fullName,
      titleStyle,
      titleMaxWidth,
      1,
    );
    final labelHeight = measureHeight(
      labelText,
      bodyStyle,
      width - cardHorizontalPadding,
      3,
    );

    double measureChipWidth(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: chipStyle),
        textDirection: direction,
        maxLines: 1,
      )..layout();
      return painter.width + 36;
    }

    final branchText =
        "${appLocale.getText(LocaleKey.fileleafBranchLabel)} ${fileNode.version.branchPath}";
    final revisionText =
        "${appLocale.getText(LocaleKey.fileleafRevisionLabel)} ${fileNode.version.revisionNumber}";
    final branchChipWidth = measureChipWidth(branchText);
    final revisionChipWidth = measureChipWidth(revisionText);
    final availableTagWidth = width - cardHorizontalPadding;
    final tagRows = branchChipWidth + revisionChipWidth + 8 <= availableTagWidth
        ? 1
        : 2;
    final tagHeight = (defaultTagHeight * tagRows) + (tagRows > 1 ? 8 : 0);

    final totalHeight = 26 + titleHeight + 10 + tagHeight + 10 + labelHeight;
    return Size(
      width + (edgeActionInset * 2),
      totalHeight + (edgeActionInset * 2),
    );
  }

  @override
  State<FileLeaf> createState() => _FileNodeState();
}

class _FileNodeState extends CanvasComponentState<FileLeaf> {
  FileNode get fileNode => widget.fileNode;
  bool _showTopAction = false;
  bool _showBottomAction = false;
  bool _showRightAction = false;
  late final AnimationController _entryController;
  late final Animation<double> _entryOpacity;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.animateEntry ? 0 : 1,
    );
    _entryOpacity = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );

    if (widget.animateEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _entryController.forward(from: 0);
        }
      });
    }
  }

  @override
  void onInitState() {
    super.dragable = false;
  }

  @override
  void didUpdateWidget(covariant FileLeaf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateEntry && !oldWidget.animateEntry) {
      _entryController.forward(from: 0);
    }
  }

  @override
  Widget buildComponent() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isFocused = widget.isFocused;
    final surfaceColor = isFocused
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;
    final foregroundColor = isFocused
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    final secondaryForeground = isFocused
        ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    final outlineColor = isFocused
        ? scheme.primary.withValues(alpha: 0.45)
        : scheme.outlineVariant.withValues(alpha: 0.85);
    final shadowColor = isFocused
        ? scheme.primary.withValues(alpha: 0.16)
        : Colors.black.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.18 : 0.06,
          );
    final labelText = fileNode.mate.label?.trim().isNotEmpty == true
        ? fileNode.mate.label!.trim()
        : appLocale.getText(LocaleKey.fileleafNoLabel);
    final outerWidth = widget.preferredWidth + (FileLeaf.edgeActionInset * 2);

    final content = Material(
      color: Colors.transparent,
      child: Container(
        width: widget.preferredWidth,
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(FileLeaf.cardRadius),
          border: Border.all(color: outlineColor, width: isFocused ? 1.4 : 1),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: isFocused ? 22 : 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fileNode.mate.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: () {
                    widget.sprout(
                      fileNode,
                      position,
                      widget.canvasComponentKey,
                    );
                  },
                  icon: const Icon(Icons.file_copy_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTag(
                  context,
                  icon: Icons.account_tree_outlined,
                  text:
                      "${appLocale.getText(LocaleKey.fileleafBranchLabel)} ${fileNode.version.branchPath}",
                  backgroundColor: isFocused
                      ? scheme.primary.withValues(alpha: 0.12)
                      : scheme.secondaryContainer.withValues(alpha: 0.55),
                  foregroundColor: foregroundColor,
                ),
                _buildTag(
                  context,
                  icon: Icons.tag_rounded,
                  text:
                      "${appLocale.getText(LocaleKey.fileleafRevisionLabel)} ${fileNode.version.revisionNumber}",
                  backgroundColor: scheme.tertiaryContainer.withValues(
                    alpha: isFocused ? 0.42 : 0.72,
                  ),
                  foregroundColor: isFocused
                      ? scheme.onPrimaryContainer
                      : scheme.onTertiaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              labelText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondaryForeground,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );

    return FadeTransition(
      opacity: _entryOpacity,
      child: SizedBox(
        width: outerWidth,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(FileLeaf.edgeActionInset),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _showOpenFileDialog,
                  onSecondaryTapDown: (details) {
                    _showContextMenu(details.globalPosition);
                  },
                  child: content,
                ),
              ),
            ),
            _buildHoverAction(
              visible: _showTopAction,
              alignment: Alignment.topCenter,
              offset: const Offset(0, 0),
              onPressed: () {
                widget.branchNode(
                  fileNode,
                  position,
                  widget.canvasComponentKey,
                );
              },
              onHoverChanged: (value) {
                setState(() {
                  _showTopAction = value;
                });
              },
              icon: Icons.call_split_rounded,
            ),
            _buildHoverAction(
              visible: _showBottomAction,
              alignment: Alignment.bottomCenter,
              offset: const Offset(0, 0),
              onPressed: () {
                widget.branchNode(
                  fileNode,
                  position,
                  widget.canvasComponentKey,
                );
              },
              onHoverChanged: (value) {
                setState(() {
                  _showBottomAction = value;
                });
              },
              icon: Icons.call_split_rounded,
            ),
            if (fileNode.child == null)
              _buildHoverAction(
                visible: _showRightAction,
                alignment: Alignment.centerRight,
                offset: const Offset(0, 0),
                onPressed: () {
                  widget.backupNode(
                    fileNode,
                    position,
                    widget.canvasComponentKey,
                  );
                },
                onHoverChanged: (value) {
                  setState(() {
                    _showRightAction = value;
                  });
                },
                icon: Icons.file_copy_outlined,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(
    BuildContext context, {
    required IconData icon,
    required String text,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuEntry(
    BuildContext context, {
    required Widget icon,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 12),
        Flexible(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }

  Widget _buildHoverAction({
    required bool visible,
    required Alignment alignment,
    required Offset offset,
    required VoidCallback onPressed,
    required ValueChanged<bool> onHoverChanged,
    required IconData icon,
  }) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Transform.translate(
          offset: offset,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => onHoverChanged(true),
            onExit: (_) => onHoverChanged(false),
            child: SizedBox(
              width: FileLeaf.edgeActionHitSize,
              height: FileLeaf.edgeActionHitSize,
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: visible ? 1 : 0,
                  child: SizedBox(
                    width: FileLeaf.edgeActionButtonSize,
                    height: FileLeaf.edgeActionButtonSize,
                    child: IconButton.filled(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: visible ? onPressed : null,
                      icon: Icon(icon),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showOpenFileDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            appLocale.getText(LocaleKey.fileleafOpenTitle).tr([
              fileNode.mate.name,
              fileNode.mate.extension,
            ]),
          ),
          content: Text(
            appLocale.getText(LocaleKey.fileleafOpenContent).tr([
              fileNode.mate.name,
              fileNode.mate.extension,
              fileNode.mate.version.toString(),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(appLocale.getText(LocaleKey.fileleafCancel)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                FileUtils.openFile(fileNode.mate.fullPath);
              },
              child: Text(appLocale.getText(LocaleKey.fileleafConfirm)),
            ),
          ],
        );
      },
    );
  }

  void _showContextMenu(Offset globalPosition) async {
    final result = await showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'backup',
          enabled: fileNode.child == null,
          child: _buildMenuEntry(
            context,
            icon: Icon(
              Icons.file_copy_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            label: appLocale.getText(LocaleKey.fileleafMenuBackup),
          ),
        ),
        PopupMenuItem(
          value: 'branch',
          child: _buildMenuEntry(
            context,
            icon: Icon(
              Icons.call_split_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            label: appLocale.getText(LocaleKey.fileleafMenuBranch),
          ),
        ),
        PopupMenuItem(
          value: 'monit',
          child: _buildMenuEntry(
            context,
            icon: Icon(
              Icons.visibility_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            label: appLocale.getText(LocaleKey.fileleafMenuMonit),
          ),
        ),
        PopupMenuItem(
          value: 'property',
          child: _buildMenuEntry(
            context,
            icon: Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            label: appLocale.getText(LocaleKey.fileleafMenuProperty),
          ),
        ),
        PopupMenuItem(
          value: 'share',
          child: _buildMenuEntry(
            context,
            icon: shareActionImage(size: 18),
            label: appLocale.getText(LocaleKey.fileleafMenuShare),
          ),
        ),
      ],
    );

    if (!mounted) {
      return;
    }

    if (result == 'backup') {
      widget.backupNode(fileNode, position, widget.canvasComponentKey);
    } else if (result == 'branch') {
      widget.branchNode(fileNode, position, widget.canvasComponentKey);
    } else if (result == 'monit') {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(appLocale.getText(LocaleKey.fileleafMonitTitle)),
            content: Text(
              appLocale.getText(LocaleKey.fileleafMonitContent).tr([
                fileNode.mate.name,
                fileNode.mate.extension,
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(appLocale.getText(LocaleKey.fileleafCancel)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  monitService.addFileMonitTask(fileNode.mate.fullPath).then((
                    result,
                  ) {
                    if (result.isErr) {
                      showWindowsNotification(
                        appLocale.getText(LocaleKey.fileleafNotifyFailed),
                        result.msg,
                      );
                      return;
                    }
                    final task = result.unwrap();
                    if (task.backupDirPath != null) {
                      showWindowsNotificationWithFolder(
                        appLocale.getText(LocaleKey.fileleafNotifySuccess),
                        appLocale.getText(LocaleKey.fileleafNotifyHint),
                        task.backupDirPath!,
                      );
                    }
                  });
                },
                child: Text(appLocale.getText(LocaleKey.fileleafConfirm)),
              ),
            ],
          );
        },
      );
    } else if (result == 'property') {
      showDialog(
        context: context,
        builder: (context) => FilePropertiesDialog(meta: fileNode.mate),
      );
    } else if (result == 'share') {
      _openLanShareDialog();
    }
  }

  Future<void> _openLanShareDialog() async {
    await openLanShareDialogForPath(fileNode.mate.fullPath);
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }
}

class FilePropertiesDialog extends StatefulWidget {
  final FileMeta meta;

  const FilePropertiesDialog({super.key, required this.meta});

  @override
  State<FilePropertiesDialog> createState() => _FilePropertiesDialogState();
}

class _FilePropertiesDialogState extends State<FilePropertiesDialog> {
  bool isEditingLabel = false;
  late TextEditingController _labelController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.meta.label ?? "");
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(appLocale.getText(LocaleKey.fileleafPropertyTitle)),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
            },
            children: [
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      appLocale.getText(LocaleKey.fileleafPropertyFullname),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(widget.meta.fullName),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      appLocale.getText(LocaleKey.fileleafPropertyName),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(widget.meta.name),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      appLocale.getText(LocaleKey.fileleafPropertyLabel),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: isEditingLabel
                        ? Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _labelController,
                                  decoration: InputDecoration(
                                    hintText: appLocale.getText(
                                      LocaleKey.fileleafPropertyInputLabel,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.check_rounded, size: 18),
                                onPressed: () async {
                                  await widget.meta.renameFile(
                                    _labelController.text,
                                  );
                                  setState(() => isEditingLabel = false);
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.cancel_outlined,
                                  size: 18,
                                ),
                                onPressed: () {
                                  setState(() {
                                    isEditingLabel = false;
                                    _labelController.text =
                                        widget.meta.label ?? "";
                                  });
                                },
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: Text(widget.meta.label ?? "")),
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 18),
                                onPressed: () =>
                                    setState(() => isEditingLabel = true),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      appLocale.getText(LocaleKey.fileleafPropertyVersion),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(widget.meta.version.toString()),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      appLocale.getText(LocaleKey.fileleafPropertyExt),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(widget.meta.extension),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      appLocale.getText(LocaleKey.fileleafPropertyPath),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(widget.meta.fullPath),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      appLocale.getText(LocaleKey.fileleafPropertySize),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text("${widget.meta.fileSize} bytes"),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      appLocale.getText(LocaleKey.fileleafPropertyCreated),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(widget.meta.creationTime.toString()),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      appLocale.getText(LocaleKey.fileleafPropertyModified),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(widget.meta.lastModifiedTime.toString()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appLocale.getText(LocaleKey.fileleafPropertyClose)),
        ),
      ],
    );
  }
}
