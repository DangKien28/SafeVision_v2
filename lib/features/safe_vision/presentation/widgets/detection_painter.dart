import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/entities/detection.dart';

class DetectionPainter extends CustomPainter {
  DetectionPainter(this.detections);

  final List<Detection> detections;

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = const Color(0xFF00FFB3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    for (final detection in detections.take(8)) {
      final rect = Rect.fromLTRB(
        detection.left * size.width,
        detection.top * size.height,
        detection.right * size.width,
        detection.bottom * size.height,
      );
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

      final bgRect = Rect.fromLTWH(
        rect.left,
        max(0, rect.top - 22),
        textPainter.width + 10,
        20,
      );
      canvas.drawRect(bgRect, Paint()..color = const Color(0xCC102219));
      textPainter.paint(canvas, Offset(bgRect.left + 5, bgRect.top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
