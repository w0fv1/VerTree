import 'package:flutter/material.dart';
import 'package:vertree/view/component/tree/canvas_component.dart';

class Point extends CanvasComponent {
  Point({super.key, required super.treeCanvasManager});

  @override
  PointState createState() => PointState();
}

class PointState extends CanvasComponentState<Point> {
  @override
  Widget buildComponent() {
    return Container(
      height: 6,
      width: 6,
      decoration: BoxDecoration(
        color: Colors.amberAccent,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
