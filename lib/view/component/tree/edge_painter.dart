import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vertree/view/component/tree/canvas_component.dart';

class Edge {
  final GlobalKey<CanvasComponentState> startPoint;
  final GlobalKey<CanvasComponentState> endPoint;
  final String id;

  Edge(this.startPoint, this.endPoint, {required this.id});
}

class FileTreeCanvasPainter extends CustomPainter {
  final List<Edge> edges;
  final Offset baseOffset;
  final bool showDebugPoints;
  final Color color;
  final Color debugColor;
  final Listenable repaint;

  FileTreeCanvasPainter(
    this.edges,
    this.baseOffset, {
    this.showDebugPoints = false,
    required this.color,
    required this.debugColor,
    required this.repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final debugPaint = Paint()
      ..color = debugColor
      ..strokeWidth = 4.0
      ..style = PaintingStyle.fill;

    for (var edge in edges) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      var start =
          edge.startPoint.currentState?.getCenterPosition() ?? Offset.zero;
      var end = edge.endPoint.currentState?.getCenterPosition() ?? Offset.zero;
      Offset s = start + baseOffset;
      Offset e = end + baseOffset;

      double dx = e.dx - s.dx;
      double dy = e.dy - s.dy;

      double dynamicR = min(dx.abs(), dy.abs());
      double r = dynamicR > 20 ? 20 : dynamicR;

      Path path = Path();

      if (dx.abs() < r || dy.abs() < r) {
        path.moveTo(s.dx, s.dy);
        path.lineTo(e.dx, e.dy);
      } else {
        Offset p1 = dy > 0 ? Offset(s.dx, e.dy - r) : Offset(s.dx, e.dy + r);

        Offset p2 = dx > 0 ? Offset(s.dx + r, e.dy) : Offset(s.dx - r, e.dy);

        bool clockwise;
        if (dx > 0) {
          clockwise = dy > 0 ? false : true;
        } else {
          clockwise = dy < 0 ? false : true;
        }

        path.moveTo(s.dx, s.dy);
        path.lineTo(p1.dx, p1.dy);
        path.arcToPoint(p2, radius: Radius.circular(r), clockwise: clockwise);
        path.lineTo(e.dx, e.dy);

        if (showDebugPoints) {
          canvas.drawCircle(p1, 2, debugPaint);
          canvas.drawCircle(p2, 2, debugPaint);
        }
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
