import 'package:flutter/material.dart';

class SizeListenerWidget extends StatefulWidget {
  final Widget child;
  final ValueChanged<Size> onSizeChange;

  const SizeListenerWidget({
    super.key,
    required this.child,
    required this.onSizeChange,
  });

  @override
  State<SizeListenerWidget> createState() => _SizeListenerWidgetState();
}

class _SizeListenerWidgetState extends State<SizeListenerWidget> {
  final GlobalKey _key = GlobalKey();
  Size? oldSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifySize());
  }

  @override
  void didUpdateWidget(covariant SizeListenerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifySize());
  }

  void _notifySize() {
    if (_key.currentContext == null) return;
    final RenderBox renderBox =
        _key.currentContext!.findRenderObject() as RenderBox;
    final newSize = renderBox.size;

    if (oldSize != newSize) {
      oldSize = newSize;
      widget.onSizeChange(newSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(key: _key, child: widget.child);
  }
}
