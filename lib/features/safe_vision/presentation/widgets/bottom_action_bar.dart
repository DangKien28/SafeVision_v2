import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/safe_vision_mode.dart';
import '../bloc/safe_vision_bloc.dart';
import '../bloc/safe_vision_event.dart';

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
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xDD0D1B2A),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ModeButton(
            label: 'NGOÀI TRỜI',
            isSelected: mode == SafeVisionMode.outdoor,
            onPressed: () => onModeChanged(SafeVisionMode.outdoor),
            primaryColor: primaryColor,
          ),
          const SizedBox(width: 8),
          // Voice Button in the middle
          _VoiceButton(primaryColor: primaryColor),
          const SizedBox(width: 8),
          _ModeButton(
            label: 'TRONG NHÀ',
            isSelected: mode == SafeVisionMode.indoor,
            onPressed: () => onModeChanged(SafeVisionMode.indoor),
            primaryColor: primaryColor,
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.isSelected,
    required this.onPressed,
    required this.primaryColor,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onPressed;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: isSelected ? primaryColor : const Color(0xFF1B263B),
          foregroundColor: isSelected ? Colors.white : Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: isSelected ? 4 : 0,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _VoiceButton extends StatelessWidget {
  const _VoiceButton({required this.primaryColor});

  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: primaryColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.4),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.mic, color: Colors.white, size: 32),
        onPressed: () {
          context.read<SafeVisionBloc>().add(const VoiceCommandStarted());
        },
      ),
    );
  }
}
