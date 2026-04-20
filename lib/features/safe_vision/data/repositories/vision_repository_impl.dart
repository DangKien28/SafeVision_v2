import 'package:camera/camera.dart';

import '../../domain/entities/detection.dart';
import '../../domain/repositories/vision_repository.dart';
import '../datasources/camera_data_source.dart';
import '../datasources/tflite_detector_data_source.dart';

class VisionRepositoryImpl implements VisionRepository {
  VisionRepositoryImpl({
    required CameraDataSource cameraDataSource,
    required TfliteDetectorDataSource detectorDataSource,
  })  : _cameraDataSource = cameraDataSource,
        _detectorDataSource = detectorDataSource;

  final CameraDataSource _cameraDataSource;
  final TfliteDetectorDataSource _detectorDataSource;

  @override
  CameraLensDirection get currentLensDirection =>
      _cameraDataSource.currentLensDirection;

  @override
  Future<CameraController> initializeCamera() async {
    final controller = await _cameraDataSource.initializeCamera();
    await _detectorDataSource.load();
    return controller;
  }

  @override
  Future<CameraController> switchCamera() {
    return _cameraDataSource.switchCamera();
  }

  @override
  Future<void> startImageStream(void Function(CameraImage image) onImage) {
    return _cameraDataSource.startImageStream(onImage);
  }

  @override
  Future<List<Detection>> detect(CameraImage image) {
    return _detectorDataSource.detect(image);
  }

  @override
  Future<void> dispose() async {
    await _cameraDataSource.dispose();
    _detectorDataSource.dispose();
  }
}
