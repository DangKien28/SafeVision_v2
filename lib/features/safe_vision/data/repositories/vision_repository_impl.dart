import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../../domain/entities/detection.dart';
import '../../domain/repositories/vision_repository.dart';
import '../datasources/camera_data_source.dart';
import '../datasources/tflite_detector_data_source.dart';

class VisionRepositoryImpl implements VisionRepository {
  VisionRepositoryImpl({
    required CameraDataSource cameraDataSource,
    required TfliteDetectorDataSource detectorDataSource,
  }) : _cameraDataSource = cameraDataSource,
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
    return _detectorDataSource.detect(
      image,
      rotationDegrees: _resolveYoloRotationDegrees(),
    );
  }

  int _resolveYoloRotationDegrees() {
    const orientationToDegrees = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    final orientation =
        orientationToDegrees[_cameraDataSource.deviceOrientation] ?? 0;
    final sensorOrientation = _cameraDataSource.sensorOrientation;

    if (_cameraDataSource.currentLensDirection == CameraLensDirection.front) {
      return (sensorOrientation + orientation) % 360;
    }
    return (sensorOrientation - orientation + 360) % 360;
  }

  @override
  Future<void> dispose() async {
    await _cameraDataSource.dispose();
    _detectorDataSource.dispose();
  }
}
