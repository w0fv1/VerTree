import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';
import 'package:vertree/platform/drop_modifiers.dart';

class ConversionDropTarget extends StatefulWidget {
  const ConversionDropTarget({
    super.key,
    required this.child,
    required this.onConvert,
    this.readControlPressed = isExternalControlPressed,
  });
  final Widget child;
  final ValueChanged<List<String>> onConvert;
  final bool Function() readControlPressed;

  @override
  State<ConversionDropTarget> createState() => _ConversionDropTargetState();
}

class _ConversionDropTargetState extends State<ConversionDropTarget> {
  bool _control = false;

  @override
  Widget build(BuildContext context) => DropTarget(
    onDragEntered: (_) => _control = widget.readControlPressed(),
    onDragUpdated: (_) => _control = widget.readControlPressed(),
    onDragDone: (details) {
      final convert = _control || widget.readControlPressed();
      _control = false;
      if (!convert) return;
      final paths = details.files
          .map((file) => file.path)
          .where((path) => path.isNotEmpty)
          .toSet()
          .toList();
      if (paths.isNotEmpty) widget.onConvert(paths);
    },
    child: widget.child,
  );
}
