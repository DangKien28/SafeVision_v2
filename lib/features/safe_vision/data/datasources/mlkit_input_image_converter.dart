import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

class MlKitInputImageConverter {
  static const Map<DeviceOrientation, int> _orientationToDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  static Uint8List? _nv21Buffer;

  static InputImage? fromCameraImage({
    required CameraImage image,
    required CameraLensDirection lensDirection,
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
  }) {
    final rotation = _resolveRotation(
      lensDirection: lensDirection,
      sensorOrientation: sensorOrientation,
      deviceOrientation: deviceOrientation,
    );
    if (rotation == null) {
      return null;
    }

    if (Platform.isAndroid) {
      final bytes = _convertYuv420ToNv21(image);
      if (bytes == null) {
        return null;
      }
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }

    final all = <int>[];
    for (final plane in image.planes) {
      all.addAll(plane.bytes);
    }

    return InputImage.fromBytes(
      bytes: Uint8List.fromList(all),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.yuv420,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  static Uint8List? _convertYuv420ToNv21(CameraImage image) {
    if (image.planes.length < 3) {
      return null;
    }

    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final targetSize = width * height * 3 ~/ 2;
    _nv21Buffer ??= Uint8List(targetSize);
    if (_nv21Buffer!.length != targetSize) {
      _nv21Buffer = Uint8List(targetSize);
    }
    final out = _nv21Buffer!;

    var offset = 0;
    for (var y = 0; y < height; y++) {
      final rowStart = y * yPlane.bytesPerRow;
      out.setRange(offset, offset + width, yPlane.bytes, rowStart);
      offset += width;
    }

    final chromaHeight = height ~/ 2;
    final chromaWidth = width ~/ 2;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;

    for (var y = 0; y < chromaHeight; y++) {
      final uRow = y * uPlane.bytesPerRow;
      final vRow = y * vPlane.bytesPerRow;
      for (var x = 0; x < chromaWidth; x++) {
        final uIndex = uRow + x * uPixelStride;
        final vIndex = vRow + x * vPixelStride;
        out[offset++] = vPlane.bytes[vIndex];
        out[offset++] = uPlane.bytes[uIndex];
      }
    }

    return out;
  }

  static InputImageRotation? _resolveRotation({
    required CameraLensDirection lensDirection,
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
  }) {
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    final orientation = _orientationToDegrees[deviceOrientation];
    if (orientation == null) {
      return null;
    }

    final compensation = lensDirection == CameraLensDirection.front
        ? (sensorOrientation + orientation) % 360
        : (sensorOrientation - orientation + 360) % 360;
    return InputImageRotationValue.fromRawValue(compensation);
  }
}
