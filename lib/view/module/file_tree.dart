import 'package:flutter/material.dart';

import 'package:vertree/component/i18n_lang.dart';
import 'package:vertree/component/notifier.dart';
import 'package:vertree/adapters/ui/versions/file_version_tree.dart';
import 'package:vertree/foundation/result.dart';
import 'package:vertree/modules/versions/versions.dart';
import 'package:vertree/adapters/ui/desktop_scope.dart';
import 'package:vertree/view/component/tree/canvas.dart';
import 'package:vertree/view/component/tree/canvas_component.dart';
import 'package:vertree/view/component/tree/canvas_manager.dart';
import 'package:vertree/view/component/tree/edge_painter.dart';
import 'package:vertree/view/module/file_leaf.dart';

class FileTreeViewportController {
  void Function(double scale)? _setScale;
  void Function()? _fitScene;
  double Function()? _getScale;

  void attach({
    required void Function(double scale) setScale,
    required void Function() fitScene,
    required double Function() getScale,
  }) {
    _setScale = setScale;
    _fitScene = fitScene;
    _getScale = getScale;
  }

  void detach() {
    _setScale = null;
    _fitScene = null;
    _getScale = null;
  }

  bool get isAttached => _setScale != null && _fitScene != null;

  void setScale(double scale) {
    _setScale?.call(scale);
  }

  void fitScene() {
    _fitScene?.call();
  }

  double? get currentScale => _getScale?.call();
}

class FileTree extends StatefulWidget {
  const FileTree({
    super.key,
    required this.rootNode,
    required this.height,
    required this.width,
    this.focusNode,
    this.viewportController,
    this.initialScale,
    this.fitToViewportOnLoad = false,
  });

  final double height;
  final double width;
  final FileNode rootNode;
  final FileNode? focusNode;
  final FileTreeViewportController? viewportController;
  final double? initialScale;
  final bool fitToViewportOnLoad;

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
  late final DesktopDependencies _desktop;
  @override
  void initState() {
    super.initState();
    _desktop = DesktopScope.read(context);
  }

  static const double _baseHorizontalGap = 54;
  static const double _baseVerticalGap = 42;
  static const double _rootLeftPadding = 48;
  static const double _scenePadding = 120;

  late FileNode rootNode = widget.rootNode;
  final TreeCanvasManager treeCanvasManager = TreeCanvasManager();
  final Map<FileNode, Size> _nodeSizes = {};
  final Map<FileNode, _SubtreeSpan> _subtreeSpans = {};
  final Map<String, GlobalKey<CanvasComponentState>> _nodeKeys = {};

  List<CanvasComponentContainer> canvasComponentContainers = [];
  List<Edge> edges = [];
  late GlobalKey<CanvasComponentState> rootKey;
  late Offset initPosition;
  Rect? _contentBounds;
  Size _sceneSize = Size.zero;

  bool _hasResolvedDependencies = false;
  int _canvasRevision = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hasResolvedDependencies = true;
    _attachViewportController();
    _refreshTree();
  }

  @override
  void didUpdateWidget(covariant FileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewportController != widget.viewportController) {
      oldWidget.viewportController?.detach();
      _attachViewportController();
    }
    if (oldWidget.height != widget.height ||
        oldWidget.width != widget.width ||
        oldWidget.rootNode != widget.rootNode ||
        oldWidget.focusNode != widget.focusNode) {
      rootNode = widget.rootNode;
      _refreshTree();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TreeCanvas(
      height: widget.height,
      width: widget.width,
      manager: treeCanvasManager,
      children: canvasComponentContainers,
      edges: edges,
      sceneSize: _sceneSize,
      revision: _canvasRevision,
      refresh: _refreshTreeAnimated,
    );
  }

  String _nodeId(FileNode node) {
    return node.mate.fullPath;
  }

  String _edgeId(String parentNodeId, String childNodeId) {
    return '$parentNodeId->$childNodeId';
  }

  void _attachViewportController() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.viewportController == null) {
        return;
      }
      widget.viewportController!.attach(
        setScale: treeCanvasManager.setScale,
        fitScene: treeCanvasManager.fitScene,
        getScale: treeCanvasManager.getScale,
      );
    });
  }

  Future<void> _refreshTreeAnimated() async {
    if (!mounted || !_hasResolvedDependencies) {
      return;
    }
    _refreshTreeLayout();
  }

  void _refreshTree() {
    _refreshTreeLayout();
  }

  void _refreshTreeLayout() {
    if (!mounted || !_hasResolvedDependencies) {
      return;
    }

    _nodeSizes.clear();
    _subtreeSpans.clear();
    canvasComponentContainers.clear();
    edges.clear();
    _contentBounds = null;

    _measureTree(rootNode);
    _updateInitPosition();

    rootKey = addChild(rootNode, initPosition);
    _layoutTree(rootNode, initPosition, rootKey);
    _updateSceneSize();
    _canvasRevision += 1;

    setState(() {});
    treeCanvasManager.requestRepaint();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.fitToViewportOnLoad) {
        treeCanvasManager.fitScene();
        return;
      }
      if (widget.initialScale != null) {
        treeCanvasManager.setScale(widget.initialScale!);
      }
    });
  }

  void _updateInitPosition() {
    final rootSize =
        _nodeSizes[rootNode] ?? FileLeaf.estimateSize(context, rootNode);
    final rootSpan = _subtreeSpans[rootNode] ?? _computeSubtreeSpan(rootNode);
    final centeredRootY =
        (widget.height / 2) + ((rootSpan.top - rootSpan.bottom) / 2);
    initPosition = Offset(
      _rootLeftPadding,
      centeredRootY - (rootSize.height / 2),
    );
  }

  Future<String?> _askForLabel() async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        String label = "";
        return AlertDialog(
          title: Text(
            _desktop.appLocale.getText(LocaleKey.filetreeInputLabelTitle),
          ),
          content: TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: _desktop.appLocale.getText(
                LocaleKey.filetreeInputLabelHint,
              ),
            ),
            onChanged: (value) {
              label = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(
                _desktop.appLocale.getText(LocaleKey.filetreeInputCancel),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(label),
              child: Text(
                _desktop.appLocale.getText(LocaleKey.filetreeInputConfirm),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runNodeMutation(
    Future<Result<FileNode, String>> Function(String? label) action,
  ) async {
    final label = await _askForLabel();

    if (label == null || !mounted) return;
    final result = await action(label);
    if (!mounted) return;
    if (result.isErr) {
      showToast(result.msg);
      return;
    }

    await _refreshTreeAnimated();
  }

  Future<Result<FileNode, String>> _createVersion(
    FileNode parent,
    String? label,
    VersionCreationMode mode,
  ) async {
    final result = await _desktop.versionActions.create(
      parent.mate.fullPath,
      label: label,
      mode: mode,
    );
    if (result.isOk) {
      if (mode == VersionCreationMode.branch) {
        parent.addBranch(result.unwrap());
      } else {
        parent.addChild(result.unwrap());
      }
    }
    return result;
  }

  void sprout(
    FileNode parentNode,
    Offset parentPosition,
    GlobalKey<CanvasComponentState> parentKey,
  ) async {
    _runNodeMutation(
      (label) => parentNode.child == null
          ? _createVersion(parentNode, label, VersionCreationMode.next)
          : _createVersion(parentNode, label, VersionCreationMode.branch),
    );
  }

  void backupNode(
    FileNode parentNode,
    Offset parentPosition,
    GlobalKey<CanvasComponentState> parentKey,
  ) {
    if (parentNode.child != null) {
      showToast(
        _desktop.appLocale.getText(LocaleKey.filetreeBackupBlockedHasChild),
      );
      return;
    }
    _runNodeMutation(
      (label) => _createVersion(parentNode, label, VersionCreationMode.next),
    );
  }

  void branchNode(
    FileNode parentNode,
    Offset parentPosition,
    GlobalKey<CanvasComponentState> parentKey,
  ) {
    _runNodeMutation(
      (label) => _createVersion(parentNode, label, VersionCreationMode.branch),
    );
  }

  GlobalKey<CanvasComponentState> addChild(
    FileNode child,
    Offset childPosition, {
    GlobalKey<CanvasComponentState>? parentKey,
    String? parentNodeId,
  }) {
    final nodeId = _nodeId(child);
    final isFreshNode = !_nodeKeys.containsKey(nodeId);
    final childKey = _nodeKeys.putIfAbsent(
      nodeId,
      () => GlobalKey<CanvasComponentState>(),
    );
    final isFocused =
        widget.focusNode != null &&
        widget.focusNode!.version.compareTo(child.version) == 0;
    _desktop.logger.info(
      "isFocused: $isFocused, widget.focusNode version: ${widget.focusNode?.version}, child version: ${child.version}",
    );

    canvasComponentContainers.add(
      CanvasComponentContainer.component(
        FileLeaf(
          child,
          sprout: sprout,
          backupNode: backupNode,
          branchNode: branchNode,
          key: childKey,
          componentId: nodeId,
          treeCanvasManager: treeCanvasManager,
          position: childPosition,
          preferredWidth:
              (_nodeSizes[child] ?? FileLeaf.estimateSize(context, child))
                  .width,
          isFocused: isFocused,
          animateEntry: isFreshNode,
        ),
      ),
    );
    _includeNodeBounds(child, childPosition);

    if (parentKey != null && parentNodeId != null) {
      final edgeId = _edgeId(parentNodeId, nodeId);
      edges.add(Edge(parentKey, childKey, id: edgeId));
    }

    return childKey;
  }

  void _includeNodeBounds(FileNode node, Offset position) {
    final nodeSize = _nodeSizes[node] ?? FileLeaf.estimateSize(context, node);
    final rect = Rect.fromLTWH(
      position.dx,
      position.dy,
      nodeSize.width,
      nodeSize.height,
    );
    _contentBounds = _contentBounds == null
        ? rect
        : _contentBounds!.expandToInclude(rect);
  }

  void _updateSceneSize() {
    final bounds = _contentBounds;
    if (bounds == null) {
      _sceneSize = Size(widget.width, widget.height);
      return;
    }

    _sceneSize = Size(
      bounds.right + _scenePadding > widget.width
          ? bounds.right + _scenePadding
          : widget.width,
      bounds.bottom + _scenePadding > widget.height
          ? bounds.bottom + _scenePadding
          : widget.height,
    );
  }

  void _measureTree(FileNode node) {
    _nodeSizes[node] = FileLeaf.estimateSize(context, node);
    if (node.child != null) {
      _measureTree(node.child!);
    }
    for (final branch in node.branches) {
      _measureTree(branch);
    }
    _computeSubtreeSpan(node);
  }

  _SubtreeSpan _computeSubtreeSpan(FileNode node) {
    final cached = _subtreeSpans[node];
    if (cached != null) {
      return cached;
    }

    final nodeSize = _nodeSizes[node] ?? FileLeaf.estimateSize(context, node);
    double topExtent = nodeSize.height / 2;
    double bottomExtent = nodeSize.height / 2;

    _SubtreeSpan? childSpan;
    if (node.child != null) {
      childSpan = _computeSubtreeSpan(node.child!);
      if (childSpan.top > topExtent) {
        topExtent = childSpan.top;
      }
      if (childSpan.bottom > bottomExtent) {
        bottomExtent = childSpan.bottom;
      }
    }

    double topCursor = topExtent;
    for (final branch in node.topBranches) {
      final span = _computeSubtreeSpan(branch);
      final branchGap = _verticalGapFor(node, branch);
      final branchCenterDistance = topCursor + branchGap + span.bottom;
      final branchTopExtent = branchCenterDistance + span.top;
      if (branchTopExtent > topExtent) {
        topExtent = branchTopExtent;
      }
      topCursor = branchTopExtent;
    }

    double bottomCursor = bottomExtent;
    for (final branch in node.bottomBranches) {
      final span = _computeSubtreeSpan(branch);
      final branchGap = _verticalGapFor(node, branch);
      final branchCenterDistance = bottomCursor + branchGap + span.top;
      final branchBottomExtent = branchCenterDistance + span.bottom;
      if (branchBottomExtent > bottomExtent) {
        bottomExtent = branchBottomExtent;
      }
      bottomCursor = branchBottomExtent;
    }

    final result = _SubtreeSpan(top: topExtent, bottom: bottomExtent);
    _subtreeSpans[node] = result;
    return result;
  }

  double _horizontalGapFor(FileNode node) {
    final nodeSize = _nodeSizes[node] ?? FileLeaf.estimateSize(context, node);
    return _baseHorizontalGap +
        ((nodeSize.width - FileLeaf.minCardWidth) * 0.18);
  }

  double _verticalGapFor(FileNode from, FileNode to) {
    final fromSize = _nodeSizes[from] ?? FileLeaf.estimateSize(context, from);
    final toSize = _nodeSizes[to] ?? FileLeaf.estimateSize(context, to);
    return _baseVerticalGap + ((fromSize.height + toSize.height) * 0.12);
  }

  void _layoutTree(
    FileNode fileNode,
    Offset parentPosition,
    GlobalKey<CanvasComponentState> parentKey,
  ) {
    final nodeSize =
        _nodeSizes[fileNode] ?? FileLeaf.estimateSize(context, fileNode);
    final centerY = parentPosition.dy + (nodeSize.height / 2);
    final childX =
        parentPosition.dx + nodeSize.width + _horizontalGapFor(fileNode);
    final fileNodeId = _nodeId(fileNode);

    if (fileNode.child != null) {
      final childSize =
          _nodeSizes[fileNode.child!] ??
          FileLeaf.estimateSize(context, fileNode.child!);
      final childPosition = Offset(childX, centerY - (childSize.height / 2));
      final childKey = addChild(
        fileNode.child!,
        childPosition,
        parentKey: parentKey,
        parentNodeId: fileNodeId,
      );
      _layoutTree(fileNode.child!, childPosition, childKey);
    }

    final childSpan = fileNode.child != null
        ? _subtreeSpans[fileNode.child!]
        : null;

    double topCursor = nodeSize.height / 2;
    if ((childSpan?.top ?? 0) > topCursor) {
      topCursor = childSpan!.top;
    }
    for (final branch in fileNode.topBranches) {
      final branchSize =
          _nodeSizes[branch] ?? FileLeaf.estimateSize(context, branch);
      final branchSpan = _subtreeSpans[branch] ?? _computeSubtreeSpan(branch);
      final branchGap = _verticalGapFor(fileNode, branch);
      final branchCenterY =
          centerY - (topCursor + branchGap + branchSpan.bottom);
      final branchPosition = Offset(
        childX,
        branchCenterY - (branchSize.height / 2),
      );
      final childKey = addChild(
        branch,
        branchPosition,
        parentKey: parentKey,
        parentNodeId: fileNodeId,
      );
      _layoutTree(branch, branchPosition, childKey);
      topCursor += branchGap + branchSpan.bottom + branchSpan.top;
    }

    double bottomCursor = nodeSize.height / 2;
    if ((childSpan?.bottom ?? 0) > bottomCursor) {
      bottomCursor = childSpan!.bottom;
    }
    for (final branch in fileNode.bottomBranches) {
      final branchSize =
          _nodeSizes[branch] ?? FileLeaf.estimateSize(context, branch);
      final branchSpan = _subtreeSpans[branch] ?? _computeSubtreeSpan(branch);
      final branchGap = _verticalGapFor(fileNode, branch);
      final branchCenterY =
          centerY + (bottomCursor + branchGap + branchSpan.top);
      final branchPosition = Offset(
        childX,
        branchCenterY - (branchSize.height / 2),
      );
      final childKey = addChild(
        branch,
        branchPosition,
        parentKey: parentKey,
        parentNodeId: fileNodeId,
      );
      _layoutTree(branch, branchPosition, childKey);
      bottomCursor += branchGap + branchSpan.top + branchSpan.bottom;
    }
  }

  @override
  void dispose() {
    widget.viewportController?.detach();
    super.dispose();
  }
}

class _SubtreeSpan {
  const _SubtreeSpan({required this.top, required this.bottom});

  final double top;
  final double bottom;
}
