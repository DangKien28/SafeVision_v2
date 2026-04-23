import 'package:camera/camera.dart';

import '../../domain/entities/detection.dart';
import '../../domain/entities/safe_vision_mode.dart';

class SafeVisionState {
  const SafeVisionState({
    required this.isInitializing,
    required this.statusText,
    required this.isFrontCamera,
    required this.mode,
    required this.rawDetections,
    required this.detections,
    required this.cameraController,
    required this.errorMessage,
  });

  factory SafeVisionState.initial() {
    return const SafeVisionState(
      isInitializing: true,
      statusText: 'Đang khởi tạo camera...',
      isFrontCamera: false,
      mode: SafeVisionMode.outdoor,
      rawDetections: <Detection>[],
      detections: <Detection>[],
      cameraController: null,
      errorMessage: null,
    );
  }

  final bool isInitializing;
  final String statusText;
  final bool isFrontCamera;
  final SafeVisionMode mode;
  final List<Detection> rawDetections;
  final List<Detection> detections;
  final CameraController? cameraController;
  final String? errorMessage;

  SafeVisionState copyWith({
    bool? isInitializing,
    String? statusText,
    bool? isFrontCamera,
    SafeVisionMode? mode,
    List<Detection>? rawDetections,
    List<Detection>? detections,
    CameraController? cameraController,
    String? errorMessage,
  }) {
    return SafeVisionState(
      isInitializing: isInitializing ?? this.isInitializing,
      statusText: statusText ?? this.statusText,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      mode: mode ?? this.mode,
      rawDetections: rawDetections ?? this.rawDetections,
      detections: detections ?? this.detections,
      cameraController: cameraController ?? this.cameraController,
      errorMessage: errorMessage,
    );
  }
}
