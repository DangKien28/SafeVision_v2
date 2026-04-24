import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/safe_vision_bloc.dart';
import '../bloc/safe_vision_event.dart';
import '../bloc/safe_vision_state.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CÀI ĐẶT',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildSectionHeader('ÂM THANH'),
          const SizedBox(height: 16),
          BlocBuilder<SafeVisionBloc, SafeVisionState>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Âm lượng thông báo', style: TextStyle(fontSize: 16)),
                      Text('${(state.volume * 100).toInt()}%', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: state.volume,
                    activeColor: primaryColor,
                    onChanged: (v) {
                      context.read<SafeVisionBloc>().add(SafeVisionVolumeChanged(v));
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          _buildSectionHeader('CAMERA'),
          const SizedBox(height: 16),
          BlocBuilder<SafeVisionBloc, SafeVisionState>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Độ phóng đại (Zoom)', style: TextStyle(fontSize: 16)),
                      Text('${state.zoomLevel.toStringAsFixed(1)}x', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: state.zoomLevel,
                    min: 1.0,
                    max: 5.0,
                    activeColor: primaryColor,
                    onChanged: (v) {
                      context.read<SafeVisionBloc>().add(SafeVisionZoomChanged(v));
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          _buildSectionHeader('HƯỚNG DẪN SỬ DỤNG'),
          const SizedBox(height: 16),
          _buildInstructionItem(
            icon: Icons.swipe,
            title: 'Chuyển chế độ',
            description: 'Vuốt sang trái hoặc phải trên màn hình để chuyển giữa chế độ Ngoài trời và Trong nhà.',
          ),
          _buildInstructionItem(
            icon: Icons.mic,
            title: 'Ra lệnh giọng nói',
            description: 'Nhấn nút Micro ở giữa thanh công cụ và nói "Ngoài trời" hoặc "Trong nhà" để chuyển chế tap.',
          ),
          _buildInstructionItem(
            icon: Icons.touch_app,
            title: 'Đổi camera',
            description: 'Nhấn đúp 2 lần vào màn hình để chuyển đổi giữa camera trước và sau.',
          ),
          _buildInstructionItem(
            icon: Icons.warning_amber_rounded,
            title: 'Cảnh báo nguy hiểm',
            description: 'Khi phát hiện vật nguy hiểm (lửa, hố) hoặc bối cảnh nguy hiểm (xe lao tới), ứng dụng sẽ phát âm thanh Beep và lời nhắc.',
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.white54,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildInstructionItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blueAccent, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
