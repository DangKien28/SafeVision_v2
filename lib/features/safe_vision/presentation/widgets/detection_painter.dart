import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/entities/detection.dart';

class DetectionPainter extends CustomPainter {
  DetectionPainter(this.detections);

  final List<Detection> detections;

  static const int _maxBoxes = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = const Color(0xFF00FFB3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (final detection in detections.take(_maxBoxes)) {
      final rect = Rect.fromLTRB(
        detection.left * size.width,
        detection.top * size.height,
        detection.right * size.width,
        detection.bottom * size.height,
      );
      if (rect.width < 20 || rect.height < 20) {
        continue;
      }
      canvas.drawRect(rect, boxPaint);

      final label =
          '${detection.labelVi} ${(detection.score * 100).toStringAsFixed(0)}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFFFAF7E8),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.8);

      // Guard dispose in finally so the native Paragraph is always released,
      // even if a draw call below throws an exception.
      try {
        final bgRect = Rect.fromLTWH(
          rect.left,
          max(0, rect.top - 22),
          textPainter.width + 10,
          20,
        );
        canvas.drawRect(bgRect, Paint()..color = const Color(0xCC102219));
        textPainter.paint(canvas, Offset(bgRect.left + 5, bgRect.top + 2));
      } finally {
        textPainter.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    if (oldDelegate.detections.length != detections.length) {
      return true;
    }
    for (var i = 0; i < detections.length; i++) {
      if (oldDelegate.detections[i] != detections[i]) {
        return true;
      }
    }
    return false;
  }
}