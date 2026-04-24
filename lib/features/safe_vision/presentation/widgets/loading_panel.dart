import 'package:flutter/material.dart';

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A120E),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF00FFB3),
          strokeWidth: 5,
        ),
      ),
    );
  }
}
