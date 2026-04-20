import 'package:flutter/material.dart';

import '../../domain/entities/safe_vision_mode.dart';

class TopStatusBar extends StatelessWidget {
  const TopStatusBar({
    super.key,
    required this.mode,
    required this.statusText,
  });

  final SafeVisionMode mode;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xAA10130F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8D98B), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'SAFEVISION - ${mode.name.toUpperCase()}',
            style: const TextStyle(
              color: Color(0xFFE8D98B),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            statusText,
            style: const TextStyle(
              color: Color(0xFFF3F7F3),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
