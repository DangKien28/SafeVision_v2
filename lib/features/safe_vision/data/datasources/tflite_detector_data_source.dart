import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../domain/entities/detection.dart';

class TfliteDetectorDataSource {
  TfliteDetectorDataSource({
    required this.modelAsset,
    required this.labelsAsset,
  });

  final String modelAsset;
  final String labelsAsset;

  Interpreter? _interpreter;
  late List<String> _labels;

  List<int> _inputShape = const [1, 640, 640, 3];
  TensorType _inputType = TensorType.float32;
  List<List<int>> _outputShapes = const [];

  Future<void> load() async {
    if (_interpreter != null) {
      return;
    }

    _labels = (await rootBundle.loadString(labelsAsset))
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final options = InterpreterOptions()..threads = 4;
    _configureHardwareDelegate(options);

    _interpreter = await Interpreter.fromAsset(modelAsset, options: options);
    _inputShape = _interpreter!.getInputTensor(0).shape;
    _inputType = _interpreter!.getInputTensor(0).type;
    _outputShapes = List.generate(
      _interpreter!.getOutputTensors().length,
      (i) => _interpreter!.getOutputTensor(i).shape,
      growable: false,
    );
  }

  void _configureHardwareDelegate(InterpreterOptions options) {
    if (kIsWeb) {
      return;
    }

    final platform = defaultTargetPlatform;

    if (platform == TargetPlatform.iOS) {
      try {
        options.addDelegate(GpuDelegateV2());
      } catch (_) {
        // Fallback to CPU/XNNPACK if GPU delegate is not available.
      }
    }
  }

  Future<List<Detection>> detect(CameraImage cameraImage) async {
    if (_interpreter == null) {
      return const [];
    }

    final inputWidth = _inputShape[2];
    final inputHeight = _inputShape[1];

    final input = await _buildModelInputInBackground(
      cameraImage,
      inputWidth,
      inputHeight,
    );

    final outputs = <int, Object>{};
    for (var i = 0; i < _outputShapes.length; i++) {
      outputs[i] = _createTensorBuffer(_outputShapes[i], TensorType.float32);
    }

    _interpreter!.runForMultipleInputs([input], outputs);
    return _parseDetections(outputs.values.first, inputWidth, inputHeight);
  }

  Future<dynamic> _buildModelInputInBackground(
    CameraImage image,
    int inputWidth,
    int inputHeight,
  ) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final payload = <String, Object>{
      'width': image.width,
      'height': image.height,
      'inputWidth': inputWidth,
      'inputHeight': inputHeight,
      'isUint8Input': _inputType == TensorType.uint8,
      'yBytes': Uint8List.fromList(yPlane.bytes),
      'uBytes': Uint8List.fromList(uPlane.bytes),
      'vBytes': Uint8List.fromList(vPlane.bytes),
      'yBytesPerRow': yPlane.bytesPerRow,
      'uBytesPerRow': uPlane.bytesPerRow,
      'uBytesPerPixel': uPlane.bytesPerPixel ?? 1,
    };

    return compute(_buildModelInputFromYuv, payload);
  }

  dynamic _createTensorBuffer(List<int> shape, TensorType type) {
    if (shape.isEmpty) {
      return type == TensorType.float32 ? 0.0 : 0;
    }
    return List.generate(
      shape.first,
      (_) => _createTensorBuffer(shape.sublist(1), type),
      growable: false,
    );
  }

  List<double> _flatten(dynamic data) {
    if (data is num) {
      return [data.toDouble()];
    }
    if (data is List) {
      return data
          .expand<double>((item) => _flatten(item))
          .toList(growable: false);
    }
    return const [];
  }

  List<Detection> _parseDetections(dynamic rawOutput, int inW, int inH) {
    if (_outputShapes.isEmpty) {
      return const [];
    }

    final shape = _outputShapes.first;
    if (shape.length < 3) {
      return const [];
    }

    final flat = _flatten(rawOutput);
    final a = shape[1];
    final b = shape[2];
    final detections = <Detection>[];

    var threshold = 0.45;
    if (_modeledClassesCount(shape) > 20) {
      threshold = 0.35;
    }

    if (a >= 5 && b >= 5 && a < b) {
      for (var i = 0; i < b; i++) {
        final x = flat[i];
        final y = flat[b + i];
        final w = flat[2 * b + i];
        final h = flat[3 * b + i];
        const classStart = 4;
        final classCount = a - classStart;

        var bestClass = 0;
        var bestScore = 0.0;
        for (var c = 0; c < classCount; c++) {
          final score = flat[(classStart + c) * b + i];
          if (score > bestScore) {
            bestScore = score;
            bestClass = c;
          }
        }
        if (bestScore < threshold) {
          continue;
        }
        detections.add(
          _toDetection(x, y, w, h, bestClass, bestScore, inW, inH),
        );
      }
    } else {
      final rows = a;
      final cols = b;
      for (var i = 0; i < rows; i++) {
        final rowStart = i * cols;
        final x = flat[rowStart];
        final y = flat[rowStart + 1];
        final w = flat[rowStart + 2];
        final h = flat[rowStart + 3];
        var bestClass = 0;
        var bestScore = 0.0;
        for (var c = 4; c < cols; c++) {
          final score = flat[rowStart + c];
          if (score > bestScore) {
            bestScore = score;
            bestClass = c - 4;
          }
        }
        if (bestScore < threshold) {
          continue;
        }
        detections.add(
          _toDetection(x, y, w, h, bestClass, bestScore, inW, inH),
        );
      }
    }

    final filtered = _nonMaxSuppression(detections, iouThreshold: 0.45);
    filtered.sort((a, b) => b.score.compareTo(a.score));
    return filtered;
  }

  int _modeledClassesCount(List<int> outputShape) {
    if (outputShape.length < 3) {
      return _labels.length;
    }
    final maybe = min(outputShape[1], outputShape[2]) - 4;
    return max(1, maybe);
  }

  Detection _toDetection(
    double x,
    double y,
    double w,
    double h,
    int classIndex,
    double score,
    int inW,
    int inH,
  ) {
    final scaleW = max(x.abs(), w.abs()) > 2.0 ? inW.toDouble() : 1.0;
    final scaleH = max(y.abs(), h.abs()) > 2.0 ? inH.toDouble() : 1.0;

    final cx = x / scaleW;
    final cy = y / scaleH;
    final bw = w / scaleW;
    final bh = h / scaleH;

    final left = (cx - bw / 2).clamp(0.0, 1.0);
    final top = (cy - bh / 2).clamp(0.0, 1.0);
    final right = (cx + bw / 2).clamp(0.0, 1.0);
    final bottom = (cy + bh / 2).clamp(0.0, 1.0);

    final label = classIndex >= 0 && classIndex < _labels.length
        ? _labels[classIndex]
        : 'vat_can';

    return Detection(
      label: label,
      score: score,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
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
      sorted.removeWhere(
        (candidate) => _iou(current, candidate) >= iouThreshold,
      );
    }
    return selected;
  }

  double _iou(Detection a, Detection b) {
    final interLeft = max(a.left, b.left);
    final interTop = max(a.top, b.top);
    final interRight = min(a.right, b.right);
    final interBottom = min(a.bottom, b.bottom);

    final interW = max(0.0, interRight - interLeft);
    final interH = max(0.0, interBottom - interTop);
    final intersection = interW * interH;
    final union = a.areaRatio + b.areaRatio - intersection;
    if (union <= 0) {
      return 0;
    }
    return intersection / union;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

dynamic _buildModelInputFromYuv(Map<String, Object> payload) {
  final width = payload['width'] as int;
  final height = payload['height'] as int;
  final inputWidth = payload['inputWidth'] as int;
  final inputHeight = payload['inputHeight'] as int;
  final isUint8Input = payload['isUint8Input'] as bool;

  final yBytes = payload['yBytes'] as Uint8List;
  final uBytes = payload['uBytes'] as Uint8List;
  final vBytes = payload['vBytes'] as Uint8List;
  final yBytesPerRow = payload['yBytesPerRow'] as int;
  final uBytesPerRow = payload['uBytesPerRow'] as int;
  final uBytesPerPixel = payload['uBytesPerPixel'] as int;

  final rgbImage = img.Image(width: width, height: height);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final yIndex = y * yBytesPerRow + x;
      final uvIndex = (y ~/ 2) * uBytesPerRow + (x ~/ 2) * uBytesPerPixel;

      final yp = yBytes[yIndex];
      final up = uBytes[uvIndex];
      final vp = vBytes[uvIndex];

      final r = (yp + 1.403 * (vp - 128)).round().clamp(0, 255);
      final g = (yp - 0.344 * (up - 128) - 0.714 * (vp - 128)).round().clamp(
        0,
        255,
      );
      final b = (yp + 1.770 * (up - 128)).round().clamp(0, 255);

      rgbImage.setPixelRgb(x, y, r, g, b);
    }
  }

  final resized = img.copyResize(
    rgbImage,
    width: inputWidth,
    height: inputHeight,
  );

  if (isUint8Input) {
    return List.generate(
      1,
      (_) => List.generate(
        inputHeight,
        (y) => List.generate(inputWidth, (x) {
          final pixel = resized.getPixel(x, y);
          return [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
        }, growable: false),
        growable: false,
      ),
      growable: false,
    );
  }

  return List.generate(
    1,
    (_) => List.generate(
      inputHeight,
      (y) => List.generate(inputWidth, (x) {
        final pixel = resized.getPixel(x, y);
        return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
      }, growable: false),
      growable: false,
    ),
    growable: false,
  );
}
