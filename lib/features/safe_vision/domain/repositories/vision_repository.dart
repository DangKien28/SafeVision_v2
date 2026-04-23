import 'package:camera/camera.dart';

import '../entities/detection.dart';

abstract class VisionRepository {
  CameraLensDirection get currentLensDirection;
  Future<CameraController> initializeCamera();
  Future<CameraController> switchCamera();
  Future<void> startImageStream(void Function(CameraImage image) onImage);
  Future<List<Detection>> detect(CameraImage image, {double confidenceThreshold = 0.40});
  Future<void> dispose();
}
