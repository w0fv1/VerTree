import 'package:flutter/material.dart';

import 'canvas_component.dart';

class TreeRepaintNotifier extends ChangeNotifier {
  void repaint() {
    notifyListeners();
  }
}

class TreeCanvasManager {
  final TreeRepaintNotifier repaintNotifier = TreeRepaintNotifier();

  late String Function(
    CanvasComponent Function(
      GlobalKey<CanvasComponentState> key,
      TreeCanvasManager treeCanvasManager,
    )
    builder,
  )
  put;
  late void Function(String id, Offset offset) move;

  late void Function(String id, Offset position) jump;

  late void Function(String) raiseOneLayer;
  late void Function(String) lowerOneLayer;

  late void Function(String startId, String endId) connectPoints;
  late void Function(double scale) setScale;
  late void Function() fitScene;
  late double Function() getScale;

  void requestRepaint() {
    repaintNotifier.repaint();
  }
}
