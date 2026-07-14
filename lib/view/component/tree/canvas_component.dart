import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:vertree/view/component/size_listener_widget.dart';
import 'package:vertree/view/component/tree/canvas_manager.dart';

abstract class CanvasComponent extends StatefulWidget {
  final GlobalKey<CanvasComponentState> canvasComponentKey;
  final String id;
  final TreeCanvasManager treeCanvasManager;
  final Offset position;

  CanvasComponent({
    required super.key,
    required this.treeCanvasManager,
    this.position = Offset.zero,
    String? componentId,
  }) : canvasComponentKey = key as GlobalKey<CanvasComponentState>,
       id = componentId ?? const Uuid().v4();
}

abstract class CanvasComponentState<T extends CanvasComponent> extends State<T>
    with TickerProviderStateMixin {
  late Offset position = widget.position;
  late AnimationController _animationController;
  late Animation<Offset> _animation;
  SystemMouseCursor _cursor = SystemMouseCursors.click;

  @override
  void initState() {
    onInitState();

    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = Tween<Offset>(begin: widget.position, end: widget.position)
        .animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );
    _animation.addListener(() {
      if (!mounted) {
        return;
      }
      setState(() {
        position = _animation.value;
      });
      widget.treeCanvasManager.requestRepaint();
    });
  }

  void onInitState() {
    return;
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position && !isDragging) {
      _animateTo(widget.position);
    }
  }

  String getId() {
    return widget.id;
  }

  Offset getCenterPosition() {
    return position + Offset(size.width / 2, size.height / 2);
  }

  bool isDragging = false;

  bool dragable = false;

  double scale = 1.0;
  bool isHovered = false;

  void setPosition(Offset position) {
    setState(() {
      this.position = position;
    });
    widget.treeCanvasManager.requestRepaint();
  }

  Size size = Size.zero;

  @override
  Widget build(BuildContext context) {
    return SizeListenerWidget(
      onSizeChange: (Size size) {
        setState(() {
          this.size = size;
        });
        widget.treeCanvasManager.requestRepaint();
      },
      child: Positioned(
        left: position.dx,
        top: position.dy,
        child: MouseRegion(
          cursor: _cursor,
          onEnter: (_) {
            if (!isDragging) {
              setState(() {
                scale = 1.02;
              });
              isHovered = true;
            }
          },
          onExit: (_) {
            if (!isDragging) {
              setState(() {
                scale = 1.0;
              });
              isHovered = false;
            }
          },
          child: GestureDetector(
            onPanStart: (_) {
              setState(() {
                isDragging = true;
                scale = 1.1;
                _cursor = SystemMouseCursors.allScroll;
              });
            },
            onPanUpdate: (details) {
              if (!dragable) {
                return;
              }
              setState(() {
                position += details.delta;
                _cursor = SystemMouseCursors.allScroll;
              });
              widget.treeCanvasManager.requestRepaint();
            },
            onPanEnd: (_) {
              setState(() {
                isDragging = false;
                if (isHovered) {
                  scale = 1.02;
                } else {
                  scale = 1.0;
                }
                _cursor = SystemMouseCursors.grab;
              });
            },
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: buildComponent(),
            ),
          ),
        ),
      ),
    );
  }

  String put(
    CanvasComponent Function(
      GlobalKey<CanvasComponentState> key,
      TreeCanvasManager treeCanvasManager,
    )
    builder,
    Offset position,
  ) {
    return widget.treeCanvasManager.put(builder);
  }

  void animateMove(Offset targetOffset) {
    _animation = Tween<Offset>(begin: position, end: position + targetOffset)
        .animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );

    _animationController.forward(from: 0.0);
  }

  void _animateTo(Offset targetPosition) {
    _animation = Tween<Offset>(begin: position, end: targetPosition).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward(from: 0.0);
  }

  void move(Offset offset) {
    setPosition(position += offset);
  }

  void raiseLayer() {
    setState(() {
      widget.treeCanvasManager.raiseOneLayer(widget.id);
    });
  }

  void lowerLayer() {
    setState(() {
      widget.treeCanvasManager.lowerOneLayer(widget.id);
    });
  }

  Widget buildComponent();

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
