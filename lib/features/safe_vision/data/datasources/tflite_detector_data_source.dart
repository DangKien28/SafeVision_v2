import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

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

  late List<String> _labels;

  Isolate? _workerIsolate;
  ReceivePort? _receivePort;
  SendPort? _workerSendPort;
  StreamSubscription<dynamic>? _workerSubscription;
  Completer<void>? _loadCompleter;
  int _nextRequestId = 0;
  final Map<int, Completer<List<Detection>>> _pendingRequests = {};

  Future<void> load() async {
    if (_workerSendPort != null) {
      return;
    }
    if (_loadCompleter != null) {
      return _loadCompleter!.future;
    }
    _loadCompleter = Completer<void>();

    try {
      _labels = (await rootBundle.loadString(labelsAsset))
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);

      final modelData = await rootBundle.load(modelAsset);
      final modelBytes = modelData.buffer.asUint8List();

      _receivePort = ReceivePort();
      _workerSubscription = _receivePort!.listen(_onWorkerMessage);

      _workerIsolate = await Isolate.spawn(
        _inferenceIsolateEntry,
        {
          'sendPort': _receivePort!.sendPort,
          'modelBytes': modelBytes,
          'labels': _labels,
          'threads': 4,
          'enableAndroidAcceleration': true,
        },
        debugName: 'safe_vision_tflite_worker',
      );

      await _loadCompleter!.future;
    } catch (e) {
      _loadCompleter?.completeError(e);
      rethrow;
    }
  }

  void _onWorkerMessage(dynamic message) {
    if (message is! Map<Object?, Object?>) {
      return;
    }

    final type = message['type'];
    if (type == 'port') {
      _workerSendPort = message['workerPort'] as SendPort?;
      return;
    }

    if (type == 'ready') {
      if (!(_loadCompleter?.isCompleted ?? true)) {
        _loadCompleter?.complete();
      }
      return;
    }

    if (type == 'fatal') {
      if (!(_loadCompleter?.isCompleted ?? true)) {
        _loadCompleter?.completeError(message['error'] ?? 'worker init failed');
      }
      return;
    }

    if (type == 'response') {
      final requestId = message['requestId'] as int;
      final completer = _pendingRequests.remove(requestId);
      if (completer == null || completer.isCompleted) {
        return;
      }

      final error = message['error'] as String?;
      if (error != null) {
        completer.complete(const []);
        return;
      }

      final rawDetections = message['detections'] as List<Object?>? ?? const [];
      final detections = rawDetections
          .whereType<Map<Object?, Object?>>()
          .map(
            (m) => Detection(
              label: (m['label'] as String?) ?? 'vat_can',
              score: (m['score'] as num?)?.toDouble() ?? 0,
              left: (m['left'] as num?)?.toDouble() ?? 0,
              top: (m['top'] as num?)?.toDouble() ?? 0,
              right: (m['right'] as num?)?.toDouble() ?? 0,
              bottom: (m['bottom'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList(growable: false);

      completer.complete(detections);
    }
  }

  Future<List<Detection>> detect(CameraImage cameraImage) async {
    if (_workerSendPort == null) {
      return const [];
    }

    return _requestDetection(cameraImage);
  }

  Future<List<Detection>> detectInRoi(CameraImage cameraImage, Rect roi) async {
    if (_workerSendPort == null) {
      return const [];
    }

    final normalized = Rect.fromLTRB(
      roi.left.clamp(0.0, 1.0),
      roi.top.clamp(0.0, 1.0),
      roi.right.clamp(0.0, 1.0),
      roi.bottom.clamp(0.0, 1.0),
    );
    if (normalized.width <= 0 || normalized.height <= 0) {
      return const [];
    }

    final local = await _requestDetection(cameraImage, roi: normalized);
    return local
        .map(
          (d) => Detection(
            label: d.label,
            score: d.score,
            left: normalized.left + d.left * normalized.width,
            top: normalized.top + d.top * normalized.height,
            right: normalized.left + d.right * normalized.width,
            bottom: normalized.top + d.bottom * normalized.height,
          ),
        )
        .toList(growable: false);
  }

  Future<List<Detection>> _requestDetection(
    CameraImage image, {
    Rect? roi,
  }) {
    final sendPort = _workerSendPort;
    if (sendPort == null || image.planes.length < 3) {
      return Future.value(const []);
    }

    final requestId = _nextRequestId++;
    final completer = Completer<List<Detection>>();
    _pendingRequests[requestId] = completer;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    sendPort.send({
      'type': 'request',
      'requestId': requestId,
      'width': image.width,
      'height': image.height,
      'yBytes': TransferableTypedData.fromList([yPlane.bytes]),
      'uBytes': TransferableTypedData.fromList([uPlane.bytes]),
      'vBytes': TransferableTypedData.fromList([vPlane.bytes]),
      'yBytesPerRow': yPlane.bytesPerRow,
      'uBytesPerRow': uPlane.bytesPerRow,
      'uBytesPerPixel': uPlane.bytesPerPixel ?? 1,
      'roiLeft': roi?.left ?? 0.0,
      'roiTop': roi?.top ?? 0.0,
      'roiRight': roi?.right ?? 1.0,
      'roiBottom': roi?.bottom ?? 1.0,
    });

    return completer.future;
  }

  void dispose() {
    _workerSendPort?.send({'type': 'dispose'});
    _workerSubscription?.cancel();
    _receivePort?.close();
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _receivePort = null;
    _workerSendPort = null;
    for (final pending in _pendingRequests.values) {
      if (!pending.isCompleted) {
        pending.complete(const []);
      }
    }
    _pendingRequests.clear();
    _loadCompleter = null;
  }
}

void _inferenceIsolateEntry(Map<Object?, Object?> initMessage) async {
  final mainSendPort = initMessage['sendPort'] as SendPort;
  final receivePort = ReceivePort();
  mainSendPort.send({'type': 'port', 'workerPort': receivePort.sendPort});

  final modelBytes = initMessage['modelBytes'] as Uint8List;
  final labels = (initMessage['labels'] as List<Object?>)
      .whereType<String>()
      .toList(growable: false);
  final threads = (initMessage['threads'] as int?) ?? 4;
  final enableAndroidAcceleration =
      (initMessage['enableAndroidAcceleration'] as bool?) ?? true;

  Interpreter? interpreter;
  TensorType inputType = TensorType.float32;
  List<int> inputShape = const [1, 320, 320, 3];
  List<List<int>> outputShapes = const [];
  final outputBuffers = <int, Float32List>{};

  try {
    final options = InterpreterOptions()..threads = threads;
    _configureHardwareDelegateWorker(options, enableAndroidAcceleration);

    final initializedInterpreter = Interpreter.fromBuffer(
      modelBytes,
      options: options,
    );
    interpreter = initializedInterpreter;
    inputType = initializedInterpreter.getInputTensor(0).type;
    inputShape = initializedInterpreter.getInputTensor(0).shape;
    outputShapes = List.generate(
      initializedInterpreter.getOutputTensors().length,
      (i) => initializedInterpreter.getOutputTensor(i).shape,
      growable: false,
    );

    for (var i = 0; i < outputShapes.length; i++) {
      final shape = outputShapes[i];
      final total = shape.fold<int>(1, (a, b) => a * b);
      outputBuffers[i] = Float32List(total);
    }

    mainSendPort.send({'type': 'ready'});
  } catch (e) {
    mainSendPort.send({'type': 'fatal', 'error': e.toString()});
    receivePort.close();
    return;
  }

  receivePort.listen((dynamic rawMessage) {
    if (rawMessage is! Map<Object?, Object?>) {
      return;
    }
    final type = rawMessage['type'];
    if (type == 'dispose') {
      interpreter?.close();
      receivePort.close();
      return;
    }
    if (type != 'request') {
      return;
    }

    final requestId = rawMessage['requestId'] as int;
    try {
      final width = rawMessage['width'] as int;
      final height = rawMessage['height'] as int;

      final yBytes = (rawMessage['yBytes'] as TransferableTypedData)
          .materialize()
          .asUint8List();
      final uBytes = (rawMessage['uBytes'] as TransferableTypedData)
          .materialize()
          .asUint8List();
      final vBytes = (rawMessage['vBytes'] as TransferableTypedData)
          .materialize()
          .asUint8List();

      final input = _buildModelInputFromYuv(
        {
          'width': width,
          'height': height,
          'inputWidth': inputShape[2],
          'inputHeight': inputShape[1],
          'isUint8Input': inputType == TensorType.uint8,
          'yBytes': yBytes,
          'uBytes': uBytes,
          'vBytes': vBytes,
          'yBytesPerRow': rawMessage['yBytesPerRow'] as int,
          'uBytesPerRow': rawMessage['uBytesPerRow'] as int,
          'uBytesPerPixel': rawMessage['uBytesPerPixel'] as int,
          'roiLeft': (rawMessage['roiLeft'] as num).toDouble(),
          'roiTop': (rawMessage['roiTop'] as num).toDouble(),
          'roiRight': (rawMessage['roiRight'] as num).toDouble(),
          'roiBottom': (rawMessage['roiBottom'] as num).toDouble(),
        },
      );

      interpreter!.runForMultipleInputs([input], outputBuffers);
      final detections = _parseDetectionsFromBuffer(
        outputBuffer: outputBuffers[0] ?? Float32List(0),
        outputShape: outputShapes.isNotEmpty ? outputShapes.first : const [],
        labels: labels,
        inW: inputShape[2],
        inH: inputShape[1],
      );

      final serialized = detections
          .map(
            (d) => {
              'label': d.label,
              'score': d.score,
              'left': d.left,
              'top': d.top,
              'right': d.right,
              'bottom': d.bottom,
            },
          )
          .toList(growable: false);

      mainSendPort.send({
        'type': 'response',
        'requestId': requestId,
        'detections': serialized,
      });
    } catch (e) {
      mainSendPort.send({
        'type': 'response',
        'requestId': requestId,
        'error': e.toString(),
        'detections': const [],
      });
    }
  });
}

void _configureHardwareDelegateWorker(
  InterpreterOptions options,
  bool enableAndroidAcceleration,
) {
  if (kIsWeb) {
    return;
  }

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      options.addDelegate(GpuDelegateV2());
      return;
    } catch (_) {}
  }

  if (defaultTargetPlatform == TargetPlatform.android &&
      enableAndroidAcceleration) {
    try {
      final dynamic dynamicOptions = options;
      dynamicOptions.useNnApiForAndroid = true;
      return;
    } catch (_) {}

    try {
      options.addDelegate(GpuDelegateV2());
    } catch (_) {}
  }
}

List<Detection> _parseDetectionsFromBuffer({
  required Float32List outputBuffer,
  required List<int> outputShape,
  required List<String> labels,
  required int inW,
  required int inH,
}) {
  if (outputShape.length < 3 || outputBuffer.isEmpty) {
    return const [];
  }

  final a = outputShape[1];
  final b = outputShape[2];
  final detections = <Detection>[];

  var threshold = 0.45;
  if (_modeledClassesCountWorker(outputShape) > 20) {
    threshold = 0.35;
  }

  if (a >= 5 && b >= 5 && a < b) {
    for (var i = 0; i < b; i++) {
      final x = outputBuffer[i];
      final y = outputBuffer[b + i];
      final w = outputBuffer[2 * b + i];
      final h = outputBuffer[3 * b + i];
      const classStart = 4;
      final classCount = a - classStart;

      var bestClass = 0;
      var bestScore = 0.0;
      for (var c = 0; c < classCount; c++) {
        final score = outputBuffer[(classStart + c) * b + i];
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }
      if (bestScore < threshold) {
        continue;
      }
      detections.add(
        _toDetectionWorker(
          x: x,
          y: y,
          w: w,
          h: h,
          classIndex: bestClass,
          score: bestScore,
          labels: labels,
          inW: inW,
          inH: inH,
        ),
      );
    }
  } else {
    final rows = a;
    final cols = b;
    for (var i = 0; i < rows; i++) {
      final rowStart = i * cols;
      final x = outputBuffer[rowStart];
      final y = outputBuffer[rowStart + 1];
      final w = outputBuffer[rowStart + 2];
      final h = outputBuffer[rowStart + 3];
      var bestClass = 0;
      var bestScore = 0.0;
      for (var c = 4; c < cols; c++) {
        final score = outputBuffer[rowStart + c];
        if (score > bestScore) {
          bestScore = score;
          bestClass = c - 4;
        }
      }
      if (bestScore < threshold) {
        continue;
      }
      detections.add(
        _toDetectionWorker(
          x: x,
          y: y,
          w: w,
          h: h,
          classIndex: bestClass,
          score: bestScore,
          labels: labels,
          inW: inW,
          inH: inH,
        ),
      );
    }
  }

  final filtered = _nonMaxSuppressionWorker(detections, iouThreshold: 0.45);
  filtered.sort((a, b) => b.score.compareTo(a.score));
  return filtered;
}

int _modeledClassesCountWorker(List<int> outputShape) {
  if (outputShape.length < 3) {
    return 1;
  }
  final maybe = min(outputShape[1], outputShape[2]) - 4;
  return max(1, maybe);
}

Detection _toDetectionWorker({
  required double x,
  required double y,
  required double w,
  required double h,
  required int classIndex,
  required double score,
  required List<String> labels,
  required int inW,
  required int inH,
}) {
  final scaleW = max(x.abs(), w.abs()) > 2.0 ? inW.toDouble() : 1.0;
  final scaleH = max(y.abs(), h.abs()) > 2.0 ? inH.toDouble() : 1.0;

  final cx = x / scaleW;
  final cy = y / scaleH;
  final bw = w / scaleW;
  final bh = h / scaleH;

  final label = classIndex >= 0 && classIndex < labels.length
      ? labels[classIndex]
      : 'vat_can';

  return Detection(
    label: label,
    score: score,
    left: (cx - bw / 2).clamp(0.0, 1.0),
    top: (cy - bh / 2).clamp(0.0, 1.0),
    right: (cx + bw / 2).clamp(0.0, 1.0),
    bottom: (cy + bh / 2).clamp(0.0, 1.0),
  );
}

List<Detection> _nonMaxSuppressionWorker(
  List<Detection> detections, {
  required double iouThreshold,
}) {
  final sorted = [...detections]..sort((a, b) => b.score.compareTo(a.score));
  final selected = <Detection>[];

  while (sorted.isNotEmpty) {
    final current = sorted.removeAt(0);
    selected.add(current);
    sorted.removeWhere(
      (candidate) => _iouWorker(current, candidate) >= iouThreshold,
    );
  }
  return selected;
}

double _iouWorker(Detection a, Detection b) {
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
  final roiLeft = payload['roiLeft'] as double;
  final roiTop = payload['roiTop'] as double;
  final roiRight = payload['roiRight'] as double;
  final roiBottom = payload['roiBottom'] as double;

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

  final cropX = (roiLeft * width).floor().clamp(0, width - 1);
  final cropY = (roiTop * height).floor().clamp(0, height - 1);
  final cropW = ((roiRight - roiLeft) * width).floor().clamp(1, width - cropX);
  final cropH = ((roiBottom - roiTop) * height).floor().clamp(1, height - cropY);

  final cropped = img.copyCrop(
    rgbImage,
    x: cropX,
    y: cropY,
    width: cropW,
    height: cropH,
  );
  final resized = img.copyResize(cropped, width: inputWidth, height: inputHeight);

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
