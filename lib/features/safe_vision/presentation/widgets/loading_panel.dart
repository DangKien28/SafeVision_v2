import 'package:flutter/material.dart';

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A1512), Color(0xFF193227), Color(0xFF0E4532)],
        ),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFE8D98B),
          strokeWidth: 5,
        ),
      ),
    );
  }
}
