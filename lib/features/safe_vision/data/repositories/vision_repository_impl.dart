import 'package:camera/camera.dart';
import 'dart:math';
import 'dart:ui';

import '../../domain/entities/detection.dart';
import '../../domain/repositories/vision_repository.dart';
import '../datasources/camera_data_source.dart';
import '../datasources/mlkit_tracker_data_source.dart';
import '../datasources/tflite_detector_data_source.dart';

class VisionRepositoryImpl implements VisionRepository {
  VisionRepositoryImpl({
    required CameraDataSource cameraDataSource,
    required MlKitTrackerDataSource trackerDataSource,
    required TfliteDetectorDataSource detectorDataSource,
    int yoloIntervalFrames = 6,
    int roiRefreshFrames = 10,
  })  : _cameraDataSource = cameraDataSource,
        _trackerDataSource = trackerDataSource,
        _detectorDataSource = detectorDataSource,
        _yoloIntervalFrames = yoloIntervalFrames,
        _roiRefreshFrames = roiRefreshFrames;

  final CameraDataSource _cameraDataSource;
  final MlKitTrackerDataSource _trackerDataSource;
  final TfliteDetectorDataSource _detectorDataSource;
  final int _yoloIntervalFrames;
  final int _roiRefreshFrames;

  int _frameCounter = 0;
  List<Detection> _lastYoloDetections = const [];
  List<Rect> _lastPersonRois = const [];
  final Map<int, Detection> _labelByTrackId = {};

  @override
  CameraLensDirection get currentLensDirection =>
      _cameraDataSource.currentLensDirection;

  @override
  Future<CameraController> initializeCamera() async {
    final controller = await _cameraDataSource.initializeCamera();
    await _trackerDataSource.load();
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
    return _detectHybrid(image);
  }

  Future<List<Detection>> _detectHybrid(CameraImage image) async {
    _frameCounter++;

    final tracked = await _trackerDataSource.track(
      image: image,
      lensDirection: _cameraDataSource.currentLensDirection,
      sensorOrientation: _cameraDataSource.sensorOrientation,
      deviceOrientation: _cameraDataSource.deviceOrientation,
    );

    final needRoiRefresh =
        _lastPersonRois.isEmpty || _frameCounter % _roiRefreshFrames == 0;
    if (needRoiRefresh) {
      _lastPersonRois = await _trackerDataSource.detectPersonRois(
        image: image,
        lensDirection: _cameraDataSource.currentLensDirection,
        sensorOrientation: _cameraDataSource.sensorOrientation,
        deviceOrientation: _cameraDataSource.deviceOrientation,
      );
    }

    final shouldRunYolo =
        _lastYoloDetections.isEmpty || _frameCounter % _yoloIntervalFrames == 0;
    if (shouldRunYolo) {
      _lastYoloDetections = await _runYoloWithRoi(image);
      _refreshTrackLabelCache(tracked, _lastYoloDetections);
    }

    final fused = _fuseTrackedWithLabels(tracked, _lastYoloDetections);
    if (fused.isNotEmpty) {
      return fused;
    }
    return _lastYoloDetections;
  }

  Future<List<Detection>> _runYoloWithRoi(CameraImage image) async {
    if (_lastPersonRois.isEmpty) {
      return _detectorDataSource.detect(image);
    }

    final roiDetections = <Detection>[];
    for (final roi in _lastPersonRois.take(3)) {
      final expanded = _expandRect(roi, factor: 1.2);
      final detected = await _detectorDataSource.detectInRoi(image, expanded);
      roiDetections.addAll(detected);
    }

    if (roiDetections.isEmpty) {
      return _detectorDataSource.detect(image);
    }
    return _nonMaxSuppression(roiDetections, iouThreshold: 0.45);
  }

  void _refreshTrackLabelCache(
    List<MlKitTrackedBox> tracked,
    List<Detection> yolo,
  ) {
    final activeIds = tracked
        .where((t) => t.id != null)
        .map((t) => t.id!)
        .toSet();
    _labelByTrackId.removeWhere((id, _) => !activeIds.contains(id));

    for (final box in tracked) {
      final id = box.id;
      if (id == null) {
        continue;
      }

      final matched = _bestMatch(box.rect, yolo);
      if (matched != null) {
        _labelByTrackId[id] = matched;
      }
    }
  }

  List<Detection> _fuseTrackedWithLabels(
    List<MlKitTrackedBox> tracked,
    List<Detection> yolo,
  ) {
    if (tracked.isEmpty) {
      return const [];
    }

    final fused = <Detection>[];
    for (final box in tracked) {
      final cached = box.id == null ? null : _labelByTrackId[box.id!];
      final fallback = cached ?? _bestMatch(box.rect, yolo);
      if (fallback == null) {
        continue;
      }

      fused.add(
        Detection(
          label: fallback.label,
          score: fallback.score,
          left: box.left,
          top: box.top,
          right: box.right,
          bottom: box.bottom,
        ),
      );
    }

    fused.sort((a, b) => b.score.compareTo(a.score));
    return fused;
  }

  Detection? _bestMatch(Rect rect, List<Detection> detections) {
    Detection? best;
    var bestIou = 0.0;
    for (final detection in detections) {
      final iou = _iouRect(rect, detection);
      if (iou > bestIou) {
        bestIou = iou;
        best = detection;
      }
    }
    if (bestIou < 0.1) {
      return null;
    }
    return best;
  }

  Rect _expandRect(Rect rect, {required double factor}) {
    final cx = (rect.left + rect.right) / 2;
    final cy = (rect.top + rect.bottom) / 2;
    final halfW = rect.width * factor / 2;
    final halfH = rect.height * factor / 2;
    return Rect.fromLTRB(
      (cx - halfW).clamp(0.0, 1.0),
      (cy - halfH).clamp(0.0, 1.0),
      (cx + halfW).clamp(0.0, 1.0),
      (cy + halfH).clamp(0.0, 1.0),
    );
  }

  List<Detection> _nonMaxSuppression(
    List<Detection> detections, {
    required double iouThreshold,
  }) {
    final sorted = [...detections]..sort((a, b) => b.score.compareTo(a.score));
    final selected = <Detection>[];

    while (sorted.isNotEmpty) {
      final current = sorted.removeAt(0);
      selected.add(current);
      sorted.removeWhere((candidate) => _iou(current, candidate) >= iouThreshold);
    }

    return selected;
  }

  double _iouRect(Rect rect, Detection det) {
    final left = max(rect.left, det.left);
    final top = max(rect.top, det.top);
    final right = min(rect.right, det.right);
    final bottom = min(rect.bottom, det.bottom);

    if (right <= left || bottom <= top) {
      return 0.0;
    }
    final inter = (right - left) * (bottom - top);
    final rectArea = rect.width * rect.height;
    final union = rectArea + det.areaRatio - inter;
    if (union <= 0) {
      return 0.0;
    }
    return inter / union;
  }

  double _iou(Detection a, Detection b) {
    final left = max(a.left, b.left);
    final top = max(a.top, b.top);
    final right = min(a.right, b.right);
    final bottom = min(a.bottom, b.bottom);
    if (right <= left || bottom <= top) {
      return 0.0;
    }
    final inter = (right - left) * (bottom - top);
    final union = a.areaRatio + b.areaRatio - inter;
    if (union <= 0) {
      return 0.0;
    }
    return inter / union;
  }

  @override
  Future<void> dispose() async {
    await _cameraDataSource.dispose();
    await _trackerDataSource.dispose();
    _detectorDataSource.dispose();
  }
}
