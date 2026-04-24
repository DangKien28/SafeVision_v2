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
        color: const Color(0xCC1A2621),
        borderRadius: BorderRadius.circular(16),
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
                          ? const Color(0xFFE8D98B)
                          : const Color(0xFF2C3D35),
                      foregroundColor:
                          m == mode ? const Color(0xFF102019) : Colors.white,
                    ),
                      child: Text(
                        switch (m) {
                          SafeVisionMode.outdoor => 'Ngoai troi',
                          SafeVisionMode.indoor => 'Trong nha',
                        },
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
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
