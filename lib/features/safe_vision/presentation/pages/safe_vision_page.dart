import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
              Positioned.fill(
                child: BlocBuilder<SafeVisionBloc, SafeVisionState>(
                  buildWhen: (previous, current) =>
                      previous.isInitializing != current.isInitializing ||
                      previous.cameraController != current.cameraController,
                  builder: (context, state) {
                    final controller = state.cameraController;

                    if (state.isInitializing || !_isPreviewReady(controller)) {
                      return const LoadingPanel();
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final previewAspectRatio =
                            1 / controller!.value.aspectRatio;
                        final viewportWidth = constraints.maxWidth;
                        final viewportHeight =
                            viewportWidth / previewAspectRatio;

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
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: BlocBuilder<SafeVisionBloc,
                                        SafeVisionState>(
                                      buildWhen: (previous, current) =>
                                          previous.detections !=
                                          current.detections,
                                      builder: (context, state) {
                                        return RepaintBoundary(
                                          child: CustomPaint(
                                            painter: DetectionPainter(
                                              state.detections,
                                            ),
                                          ),
                                        );
                                      },
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
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 110,
                child: BlocBuilder<SafeVisionBloc, SafeVisionState>(
                  buildWhen: (previous, current) =>
                      previous.statusText != current.statusText ||
                      previous.mode != current.mode,
                  builder: (context, state) {
                    return TopStatusBar(
                      mode: state.mode,
                      statusText: state.statusText,
                    );
                  },
                ),
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

  bool _isPreviewReady(CameraController? controller) {
    if (controller == null) {
      return false;
    }
    return controller.value.isInitialized;
  }
}
