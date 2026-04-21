import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

import 'mlkit_input_image_converter.dart';

class MlKitTrackedBox {
  const MlKitTrackedBox({
    required this.id,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int? id;
  final double left;
  final double top;
  final double right;
  final double bottom;

  Rect get rect => Rect.fromLTRB(left, top, right, bottom);
}

class MlKitTrackerDataSource {
  MlKitTrackerDataSource();

  ObjectDetector? _trackerDetector;
  ObjectDetector? _personDetector;

  Future<void> load() async {
    if (_trackerDetector != null && _personDetector != null) {
      return;
    }

    _trackerDetector = ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.stream,
        classifyObjects: false,
        multipleObjects: true,
      ),
    );

    _personDetector = ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.stream,
        classifyObjects: true,
        multipleObjects: true,
      ),
    );
  }

  Future<List<MlKitTrackedBox>> track({
    required CameraImage image,
    required CameraLensDirection lensDirection,
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
  }) async {
    final detector = _trackerDetector;
    if (detector == null) {
      return const [];
    }

    final input = MlKitInputImageConverter.fromCameraImage(
      image: image,
      lensDirection: lensDirection,
      sensorOrientation: sensorOrientation,
      deviceOrientation: deviceOrientation,
    );
    if (input == null) {
      return const [];
    }

    final objects = await detector.processImage(input);
    if (objects.isEmpty) {
      return const [];
    }

    final w = image.width.toDouble();
    final h = image.height.toDouble();
    return objects
        .map((obj) => _toTrackedBox(obj, w, h))
        .whereType<MlKitTrackedBox>()
        .toList(growable: false);
  }

  Future<List<Rect>> detectPersonRois({
    required CameraImage image,
    required CameraLensDirection lensDirection,
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
  }) async {
    final detector = _personDetector;
    if (detector == null) {
      return const [];
    }

    final input = MlKitInputImageConverter.fromCameraImage(
      image: image,
      lensDirection: lensDirection,
      sensorOrientation: sensorOrientation,
      deviceOrientation: deviceOrientation,
    );
    if (input == null) {
      return const [];
    }

    final objects = await detector.processImage(input);
    if (objects.isEmpty) {
      return const [];
    }

    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final rois = <Rect>[];

    for (final obj in objects) {
      final hasPersonLikeLabel = obj.labels.any((label) {
        final text = label.text.toLowerCase();
        return text.contains('person') || text.contains('human');
      });
      if (!hasPersonLikeLabel) {
        continue;
      }

      final converted = _toTrackedBox(obj, w, h);
      if (converted == null) {
        continue;
      }

      final expanded = _expandRect(converted.rect, factor: 1.2);
      rois.add(expanded);
    }

    return rois;
  }

  MlKitTrackedBox? _toTrackedBox(DetectedObject obj, double frameW, double frameH) {
    final raw = obj.boundingBox;
    final left = (raw.left / frameW).clamp(0.0, 1.0);
    final top = (raw.top / frameH).clamp(0.0, 1.0);
    final right = (raw.right / frameW).clamp(0.0, 1.0);
    final bottom = (raw.bottom / frameH).clamp(0.0, 1.0);
    if (right <= left || bottom <= top) {
      return null;
    }

    return MlKitTrackedBox(
      id: obj.trackingId,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
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

  Future<void> dispose() async {
    final tracker = _trackerDetector;
    final person = _personDetector;
    _trackerDetector = null;
    _personDetector = null;
    if (tracker != null) {
      await tracker.close();
    }
    if (person != null) {
      await person.close();
    }
  }
}
