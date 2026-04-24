import 'package:flutter/material.dart';

import '../../domain/entities/safe_vision_mode.dart';

class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.mode,
    required this.onModeChanged,
  });

  final SafeVisionMode mode;
  final ValueChanged<SafeVisionMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xCC0A120E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: SafeVisionMode.values
            .map(
              (m) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilledButton(
                    onPressed: () => onModeChanged(m),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: m == mode
                          ? const Color(0xFF00FFB3)
                          : const Color(0xFF1A2621),
                      foregroundColor: m == mode
                          ? Colors.black
                          : Colors.white70,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      switch (m) {
                        SafeVisionMode.outdoor => 'Ngoài trời',
                        SafeVisionMode.indoor => 'Trong nhà',
                        SafeVisionMode.tutorial => 'Hướng dẫn',
                      },
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}
