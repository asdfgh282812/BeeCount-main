import 'dart:math';
import 'package:flutter/material.dart';

/// Hand-drawn, colored-pencil-textured underline mark used to carry a
/// category's own [color] when the "cute" icon theme is active. The icon
/// artwork itself (a bundled original SVG, see cute_category_icon_keys.dart)
/// always keeps its own fixed colors — this underline is the one place
/// `category.color` actually shows up in cute mode.
///
/// The demo this was approved from used an SVG feTurbulence/feDisplacementMap
/// filter for the grain; Flutter's Canvas has no equivalent filter, so the
/// "hand drawn" feel here comes from two overlapping semi-transparent strokes
/// of different width plus a fixed-seed scatter of small dots along the path.
class PencilUnderlinePainter extends CustomPainter {
  final Color color;
  const PencilUnderlinePainter({required this.color});

  static Path _wavePath(double w, double h) {
    return Path()
      ..moveTo(w * 0.06, h * 0.6)
      ..quadraticBezierTo(w * 0.3, h * 0.25, w * 0.5, h * 0.55)
      ..quadraticBezierTo(w * 0.7, h * 0.85, w * 0.94, h * 0.5);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _wavePath(size.width, size.height);

    final soft = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.42
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, soft);

    final core = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.24
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, core);

    // Graphite grain: fixed seed so repeated builds/tests/screenshots are
    // stable (not a new random scribble every frame).
    final rnd = Random(7);
    for (final metric in path.computeMetrics()) {
      final length = metric.length;
      final dotCount = (length / 3).floor();
      for (var i = 0; i < dotCount; i++) {
        final t = rnd.nextDouble() * length;
        final tangent = metric.getTangentForOffset(t);
        if (tangent == null) continue;
        final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
        final jitter = (rnd.nextDouble() - 0.5) * size.height * 0.5;
        final point = tangent.position + normal * jitter;
        final dot = Paint()
          ..color = color.withValues(alpha: 0.2 + rnd.nextDouble() * 0.35)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          point,
          size.height * 0.05 + rnd.nextDouble() * size.height * 0.05,
          dot,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant PencilUnderlinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Sizes and hosts a [PencilUnderlinePainter] so call sites don't need to
/// build a [CustomPaint] manually.
class CategoryColorUnderline extends StatelessWidget {
  final Color color;
  final double width;
  final double height;

  const CategoryColorUnderline({
    super.key,
    required this.color,
    this.width = 28,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: PencilUnderlinePainter(color: color)),
    );
  }
}
