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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
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
                top: 12,
                left: 12,
                right: 110,
                child: const _StatusLayer(),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: BlocBuilder<SafeVisionBloc, SafeVisionState>(
                  buildWhen: (previous, current) =>
                      previous.isInitializing != current.isInitializing ||
                      previous.isFrontCamera != current.isFrontCamera,
                  builder: (context, state) {
                    return Semantics(
                      label: 'Doi camera truoc hoac sau',
                      button: true,
                      child: SizedBox(
                        width: 86,
                        height: 86,
                        child: FilledButton(
                          onPressed: state.isInitializing
                              ? null
                              : () {
                                  context.read<SafeVisionBloc>().add(
                                    const CameraLensToggled(),
                                  );
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFFE400),
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: const Color(0xFFA39A3B),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: const BorderSide(
                                color: Colors.black,
                                width: 3,
                              ),
                            ),
                            elevation: 10,
                            shadowColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cameraswitch, size: 34),
                              Text(
                                state.isFrontCamera ? 'TRUOC' : 'SAU',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: BlocBuilder<SafeVisionBloc, SafeVisionState>(
                  buildWhen: (previous, current) =>
                      previous.mode != current.mode,
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
      ),
    );
  }

}

class _CameraStage extends StatelessWidget {
  const _CameraStage();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<SafeVisionBloc, SafeVisionState, (bool, CameraController?)>(
      selector: (state) => (state.isInitializing, state.cameraController),
      builder: (context, cameraState) {
        final isInitializing = cameraState.$1;
        final controller = cameraState.$2;

        if (isInitializing || controller == null || !controller.value.isInitialized) {
          return const LoadingPanel();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final previewAspectRatio = 1 / controller.value.aspectRatio;
            final viewportWidth = constraints.maxWidth;
            final viewportHeight = viewportWidth / previewAspectRatio;

            return Center(
              child: SizedBox(
                width: viewportWidth,
                height: viewportHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CameraPreview(controller),
                      ),
                    ),
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: _DetectionOverlay(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
        return CustomPaint(
          painter: DetectionPainter(detections),
        );
      },
    );
  }
}

class _StatusLayer extends StatelessWidget {
  const _StatusLayer();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<SafeVisionBloc, SafeVisionState, (SafeVisionMode, String)>(
      selector: (state) => (state.mode, state.statusText),
      builder: (context, status) {
        return TopStatusBar(
          mode: status.$1,
          statusText: status.$2,
        );
      },
    );
  }
}
