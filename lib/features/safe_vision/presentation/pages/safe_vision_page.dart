import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/detection.dart';
import '../../domain/entities/safe_vision_mode.dart';
import '../bloc/safe_vision_bloc.dart';
import '../bloc/safe_vision_event.dart';
import '../bloc/safe_vision_state.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/detection_painter.dart';
import '../widgets/loading_panel.dart';
import '../widgets/top_status_bar.dart';

class SafeVisionPage extends StatefulWidget {
  const SafeVisionPage({super.key});

  @override
  State<SafeVisionPage> createState() => _SafeVisionPageState();
}

class _SafeVisionPageState extends State<SafeVisionPage> {
  static const double _swipeThreshold = 32;

  @override
  void initState() {
    super.initState();
    context.read<SafeVisionBloc>().add(const SafeVisionStarted());
  }

  void _showSettings(BuildContext context) {
    final bloc = context.read<SafeVisionBloc>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF102019),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return BlocProvider.value(
          value: bloc,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CÀI ĐẶT',
                  style: TextStyle(
                    color: Color(0xFF00FFB3),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Âm lượng hướng dẫn',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                BlocBuilder<SafeVisionBloc, SafeVisionState>(
                  builder: (context, state) {
                    return Slider(
                      value: state.volume,
                      activeColor: const Color(0xFF00FFB3),
                      onChanged: (v) {
                        context.read<SafeVisionBloc>().add(
                          SafeVisionVolumeChanged(v),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Độ phóng đại (Zoom)',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                BlocBuilder<SafeVisionBloc, SafeVisionState>(
                  builder: (context, state) {
                    return Slider(
                      value: state.zoomLevel,
                      min: 1.0,
                      max: 5.0,
                      activeColor: const Color(0xFF00FFB3),
                      onChanged: (v) {
                        context.read<SafeVisionBloc>().add(
                          SafeVisionZoomChanged(v),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() < _swipeThreshold) {
            return;
          }
          context.read<SafeVisionBloc>().add(
            SafeVisionModeSwiped(toNext: velocity < 0),
          );
        },
        child: Stack(
          children: [
            const Positioned.fill(child: _CameraStage()),
            Positioned(
              top: 120,
              left: 12,
              right: 12,
              child: const _StatusLayer(),
            ),
            // Top Controls
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RoundButton(
                    icon: Icons.cameraswitch,
                    label: 'ĐỔI CAMERA',
                    onPressed: () {
                      context.read<SafeVisionBloc>().add(
                        const CameraLensToggled(),
                      );
                    },
                  ),
                  _RoundButton(
                    icon: Icons.settings,
                    label: 'CÀI ĐẶT',
                    onPressed: () => _showSettings(context),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BlocBuilder<SafeVisionBloc, SafeVisionState>(
                buildWhen: (previous, current) => previous.mode != current.mode,
                builder: (context, state) {
                  return BottomActionBar(
                    mode: state.mode,
                    onModeChanged: (mode) {
                      context.read<SafeVisionBloc>().add(
                        SafeVisionModeChanged(mode),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: IconButton.filled(
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF00FFB3),
              foregroundColor: Colors.black,
            ),
            icon: Icon(icon, size: 28),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _CameraStage extends StatelessWidget {
  const _CameraStage();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      SafeVisionBloc,
      SafeVisionState,
      (bool, CameraController?)
    >(
      selector: (state) => (state.isInitializing, state.cameraController),
      builder: (context, cameraState) {
        final isInitializing = cameraState.$1;
        final controller = cameraState.$2;

        if (isInitializing ||
            controller == null ||
            !controller.value.isInitialized) {
          return const LoadingPanel();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            // FIX: Use FittedBox with BoxFit.cover to maintain aspect ratio without stretching
            // This behavior is similar to native camera app.
            return Stack(
              children: [
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: controller.value.previewSize?.height ?? 1,
                      height: controller.value.previewSize?.width ?? 1,
                      child: CameraPreview(controller),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(child: _DetectionOverlay()),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DetectionOverlay extends StatelessWidget {
  const _DetectionOverlay();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<SafeVisionBloc, SafeVisionState, List<Detection>>(
      selector: (state) => state.detections,
      builder: (context, detections) {
        return CustomPaint(painter: DetectionPainter(detections));
      },
    );
  }
}

class _StatusLayer extends StatelessWidget {
  const _StatusLayer();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      SafeVisionBloc,
      SafeVisionState,
      (SafeVisionMode, String)
    >(
      selector: (state) => (state.mode, state.statusText),
      builder: (context, status) {
        return TopStatusBar(mode: status.$1, statusText: status.$2);
      },
    );
  }
}
