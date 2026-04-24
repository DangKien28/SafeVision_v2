import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

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
      rethrow;
    } finally {
      _loadCompleter = null;
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
        debugPrint('TfliteDetector worker error: $error');
        completer.completeError(StateError(error));
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

  Future<List<Detection>> detect(
    CameraImage cameraImage, {
    int rotationDegrees = 0,
    double confidenceThreshold = 0.40,
  }) async {
    if (_workerSendPort == null) {
      return const [];
    }

    return _requestDetection(
      cameraImage,
      rotationDegrees: rotationDegrees,
      confidenceThreshold: confidenceThreshold,
    );
  }

  Future<List<Detection>> detectInRoi(
    CameraImage cameraImage,
    Rect roi, {
    int rotationDegrees = 0,
    double confidenceThreshold = 0.40,
  }) async {
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

    final local = await _requestDetection(
      cameraImage,
      roi: normalized,
      rotationDegrees: rotationDegrees,
      confidenceThreshold: confidenceThreshold,
    );
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
    int rotationDegrees = 0,
    double confidenceThreshold = 0.40,
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
      'vBytesPerRow': vPlane.bytesPerRow,
      'vBytesPerPixel': vPlane.bytesPerPixel ?? 1,
      'roiLeft': roi?.left ?? 0.0,
      'roiTop': roi?.top ?? 0.0,
      'roiRight': roi?.right ?? 1.0,
      'roiBottom': roi?.bottom ?? 1.0,
      'rotationDegrees': rotationDegrees,
      'confidenceThreshold': confidenceThreshold,
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
  List<TensorType> outputTypes = const [];
  List<double> outputScales = const [];
  List<int> outputZeroPoints = const [];
  double inputScale = 1.0;
  int inputZeroPoint = 0;
  final outputBuffers = <int, Object>{};

  try {
    final options = InterpreterOptions()..threads = threads;
    _configureHardwareDelegateWorker(options, enableAndroidAcceleration, mainSendPort);

    final initializedInterpreter = Interpreter.fromBuffer(
      modelBytes,
      options: options,
    );
    interpreter = initializedInterpreter;
    inputType = initializedInterpreter.getInputTensor(0).type;
    inputShape = initializedInterpreter.getInputTensor(0).shape;
    final inputParams = initializedInterpreter.getInputTensor(0).params;
    if (inputParams.scale != 0) {
      inputScale = inputParams.scale;
      inputZeroPoint = inputParams.zeroPoint;
    }

    final outputTensors = initializedInterpreter.getOutputTensors();
    outputShapes = List.generate(
      outputTensors.length,
      (i) => outputTensors[i].shape,
      growable: false,
    );
    outputTypes = List.generate(
      outputTensors.length,
      (i) => outputTensors[i].type,
      growable: false,
    );
    outputScales = List.generate(outputTensors.length, (i) {
      final p = outputTensors[i].params;
      final scale = p.scale;
      return scale == 0 ? 1.0 : scale;
    }, growable: false);
    outputZeroPoints = List.generate(
      outputTensors.length,
      (i) => outputTensors[i].params.zeroPoint,
      growable: false,
    );
    for (var i = 0; i < outputShapes.length; i++) {
      final shape = outputShapes[i];
      outputBuffers[i] = _createOutputBufferForShape(shape, outputTypes[i]);
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
          'inputType': inputType,
          'inputScale': inputScale,
          'inputZeroPoint': inputZeroPoint,
          'yBytes': yBytes,
          'uBytes': uBytes,
          'vBytes': vBytes,
          'yBytesPerRow': rawMessage['yBytesPerRow'] as int,
          'uBytesPerRow': rawMessage['uBytesPerRow'] as int,
          'uBytesPerPixel': rawMessage['uBytesPerPixel'] as int,
          'vBytesPerRow': rawMessage['vBytesPerRow'] as int,
          'vBytesPerPixel': rawMessage['vBytesPerPixel'] as int,
          'roiLeft': (rawMessage['roiLeft'] as num).toDouble(),
          'roiTop': (rawMessage['roiTop'] as num).toDouble(),
          'roiRight': (rawMessage['roiRight'] as num).toDouble(),
          'roiBottom': (rawMessage['roiBottom'] as num).toDouble(),
          'rotationDegrees': (rawMessage['rotationDegrees'] as int?) ?? 0,
        },
      );

      final inputTensor = interpreter!.getInputTensor(0);
      inputTensor.setTo(input);
      
      final stopwatch = Stopwatch()..start();
      interpreter.invoke();
      stopwatch.stop();
      
      if (requestId % 30 == 0) {
        mainSendPort.send({
          'type': 'debug',
          'message': 'Inference time: ${stopwatch.elapsedMilliseconds}ms',
        });
      }

      for (var i = 0; i < outputShapes.length; i++) {
        final outputBuffer = outputBuffers[i];
        if (outputBuffer == null) {
          continue;
        }
        interpreter.getOutputTensor(i).copyTo(outputBuffer);
      }
      final primaryIndex = _pickPrimaryOutputIndex(outputShapes);
      final flattened = _flattenOutputBuffer(
        outputBuffers[primaryIndex],
        outputShapes.isNotEmpty ? outputShapes[primaryIndex] : const [],
        outputTypes.isNotEmpty
            ? outputTypes[primaryIndex]
            : TensorType.float32,
        outputScales.isNotEmpty ? outputScales[primaryIndex] : 1.0,
        outputZeroPoints.isNotEmpty ? outputZeroPoints[primaryIndex] : 0,
      );
      final detections = _parseDetectionsFromBuffer(
        outputBuffer: flattened,
        outputShape: outputShapes.isNotEmpty
            ? outputShapes[primaryIndex]
            : const [],
        outputType: TensorType.float32,
        outputScale: 1.0,
        outputZeroPoint: 0,
        rotationDegrees: ((rawMessage['rotationDegrees'] as int?) ?? 0) % 360,
        labels: labels,
        inW: inputShape[2],
        inH: inputShape[1],
        frameW: width,
        frameH: height,
        roiLeft: (rawMessage['roiLeft'] as num).toDouble(),
        roiTop: (rawMessage['roiTop'] as num).toDouble(),
        roiRight: (rawMessage['roiRight'] as num).toDouble(),
        roiBottom: (rawMessage['roiBottom'] as num).toDouble(),
        confidenceThreshold: (rawMessage['confidenceThreshold'] as num?)?.toDouble() ?? 0.40,
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
  SendPort mainSendPort,
) {
  if (kIsWeb) return;

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      options.addDelegate(GpuDelegateV2());
    } catch (_) {
      // Fallback to CPU
    }
    return;
  }

  if (defaultTargetPlatform == TargetPlatform.android && enableAndroidAcceleration) {
    // Force CPU for better compatibility with this model on this device
    options.threads = 4;
    mainSendPort.send({'type': 'debug', 'message': 'Using CPU mode (4 threads)'});
  } else {
    options.threads = 4;
  }
}

List<Detection> _parseDetectionsFromBuffer({
  required Object outputBuffer,
  required List<int> outputShape,
  required TensorType outputType,
  required double outputScale,
  required int outputZeroPoint,
  required int rotationDegrees,
  required List<String> labels,
  required int inW,
  required int inH,
  required int frameW,
  required int frameH,
  required double roiLeft,
  required double roiTop,
  required double roiRight,
  required double roiBottom,
  required double confidenceThreshold,
}) {
  if (outputShape.length < 3 || _bufferLength(outputBuffer) == 0) {
    return const [];
  }

  final a = outputShape[1];
  final b = outputShape[2];
  final detections = <Detection>[];

  var threshold = confidenceThreshold;

  Detection? topCandidate;
  var topCandidateScore = -1.0;

  if (a >= 5 && b >= 5 && a < b) {
    for (var i = 0; i < b; i++) {
      final x = _readOutputValue(
        outputBuffer,
        i,
        outputType,
        outputScale,
        outputZeroPoint,
      );
      final y = _readOutputValue(
        outputBuffer,
        b + i,
        outputType,
        outputScale,
        outputZeroPoint,
      );
      final w = _readOutputValue(
        outputBuffer,
        2 * b + i,
        outputType,
        outputScale,
        outputZeroPoint,
      );
      final h = _readOutputValue(
        outputBuffer,
        3 * b + i,
        outputType,
        outputScale,
        outputZeroPoint,
      );

      final scored = _bestClassScoreTransposed(
        outputBuffer: outputBuffer,
        outputType: outputType,
        outputScale: outputScale,
        outputZeroPoint: outputZeroPoint,
        channels: a,
        candidates: b,
        candidateIndex: i,
      );
      final bestClass = scored.$1;
      final bestScore = scored.$2;

      final candidate = _toDetectionWorker(
        x: x,
        y: y,
        w: w,
        h: h,
        classIndex: bestClass,
        score: bestScore,
        rotationDegrees: rotationDegrees,
        labels: labels,
        inW: inW,
        inH: inH,
        frameW: frameW,
        frameH: frameH,
        roiLeft: roiLeft,
        roiTop: roiTop,
        roiRight: roiRight,
        roiBottom: roiBottom,
      );
      if (bestScore > topCandidateScore) {
        topCandidateScore = bestScore;
        topCandidate = candidate;
      }

      if (bestScore < threshold) {
        continue;
      }
      detections.add(candidate);
    }
  } else {
    final rows = a;
    final cols = b;
    for (var i = 0; i < rows; i++) {
      final rowStart = i * cols;
      final x = _readOutputValue(
        outputBuffer,
        rowStart,
        outputType,
        outputScale,
        outputZeroPoint,
      );
      final y = _readOutputValue(
        outputBuffer,
        rowStart + 1,
        outputType,
        outputScale,
        outputZeroPoint,
      );
      final w = _readOutputValue(
        outputBuffer,
        rowStart + 2,
        outputType,
        outputScale,
        outputZeroPoint,
      );
      final h = _readOutputValue(
        outputBuffer,
        rowStart + 3,
        outputType,
        outputScale,
        outputZeroPoint,
      );

      final scored = _bestClassScoreRowMajor(
        outputBuffer: outputBuffer,
        outputType: outputType,
        outputScale: outputScale,
        outputZeroPoint: outputZeroPoint,
        rowStart: rowStart,
        cols: cols,
      );
      final bestClass = scored.$1;
      final bestScore = scored.$2;

      final candidate = _toDetectionWorker(
        x: x,
        y: y,
        w: w,
        h: h,
        classIndex: bestClass,
        score: bestScore,
        rotationDegrees: rotationDegrees,
        labels: labels,
        inW: inW,
        inH: inH,
        frameW: frameW,
        frameH: frameH,
        roiLeft: roiLeft,
        roiTop: roiTop,
        roiRight: roiRight,
        roiBottom: roiBottom,
      );
      if (bestScore > topCandidateScore) {
        topCandidateScore = bestScore;
        topCandidate = candidate;
      }

      if (bestScore < threshold) {
        continue;
      }
      detections.add(candidate);
    }
  }

  final filtered = _nonMaxSuppressionWorker(detections, iouThreshold: 0.15);
  if (filtered.isEmpty && topCandidate != null && topCandidateScore > threshold) {
    filtered.add(topCandidate);
  }
  filtered.sort((a, b) => b.score.compareTo(a.score));
  return filtered;
}

int _bufferLength(Object buffer) {
  if (buffer is Float32List) {
    return buffer.length;
  }
  if (buffer is Uint8List) {
    return buffer.length;
  }
  if (buffer is Int8List) {
    return buffer.length;
  }
  if (buffer is Int32List) {
    return buffer.length;
  }
  return 0;
}

double _readOutputValue(
  Object buffer,
  int index,
  TensorType type,
  double scale,
  int zeroPoint,
) {
  if (buffer is Float32List) {
    return buffer[index];
  }
  if (buffer is Uint8List) {
    final raw = buffer[index];
    return (raw - zeroPoint) * scale;
  }
  if (buffer is Int8List) {
    final raw = buffer[index];
    return (raw - zeroPoint) * scale;
  }
  if (buffer is Int32List) {
    final raw = buffer[index];
    if (type == TensorType.int32) {
      return raw.toDouble();
    }
    return (raw - zeroPoint) * scale;
  }
  return 0.0;
}

(int, double) _bestClassScoreTransposed({
  required Object outputBuffer,
  required TensorType outputType,
  required double outputScale,
  required int outputZeroPoint,
  required int channels,
  required int candidates,
  required int candidateIndex,
}) {
  if (channels <= 4) {
    return (0, 0.0);
  }

  final noObj = _bestFromRangeTransposed(
    outputBuffer: outputBuffer,
    outputType: outputType,
    outputScale: outputScale,
    outputZeroPoint: outputZeroPoint,
    channels: channels,
    candidates: candidates,
    candidateIndex: candidateIndex,
    classStart: 4,
    multiplyObjectness: false,
  );

  final withObj = channels > 5
      ? _bestFromRangeTransposed(
          outputBuffer: outputBuffer,
          outputType: outputType,
          outputScale: outputScale,
          outputZeroPoint: outputZeroPoint,
          channels: channels,
          candidates: candidates,
          candidateIndex: candidateIndex,
          classStart: 5,
          multiplyObjectness: true,
        )
      : (0, 0.0);

  return withObj.$2 > noObj.$2 ? withObj : noObj;
}

(int, double) _bestFromRangeTransposed({
  required Object outputBuffer,
  required TensorType outputType,
  required double outputScale,
  required int outputZeroPoint,
  required int channels,
  required int candidates,
  required int candidateIndex,
  required int classStart,
  required bool multiplyObjectness,
}) {
  final classCount = channels - classStart;
  if (classCount <= 0) {
    return (0, 0.0);
  }

  final objectnessRaw = multiplyObjectness
      ? _readOutputValue(
          outputBuffer,
          4 * candidates + candidateIndex,
          outputType,
          outputScale,
          outputZeroPoint,
        )
      : 1.0;
  final objectness = _normalizeConfidence(objectnessRaw);

  var bestClass = 0;
  var bestScore = 0.0;
  for (var c = 0; c < classCount; c++) {
    final classProbRaw = _readOutputValue(
      outputBuffer,
      (classStart + c) * candidates + candidateIndex,
      outputType,
      outputScale,
      outputZeroPoint,
    );
    final classProb = _normalizeConfidence(classProbRaw);
    final score = classProb * objectness;
    if (score > bestScore) {
      bestScore = score;
      bestClass = c;
    }
  }
  return (bestClass, bestScore);
}

(int, double) _bestClassScoreRowMajor({
  required Object outputBuffer,
  required TensorType outputType,
  required double outputScale,
  required int outputZeroPoint,
  required int rowStart,
  required int cols,
}) {
  if (cols <= 4) {
    return (0, 0.0);
  }

  final noObj = _bestFromRangeRowMajor(
    outputBuffer: outputBuffer,
    outputType: outputType,
    outputScale: outputScale,
    outputZeroPoint: outputZeroPoint,
    rowStart: rowStart,
    cols: cols,
    classStart: 4,
    multiplyObjectness: false,
  );

  final withObj = cols > 5
      ? _bestFromRangeRowMajor(
          outputBuffer: outputBuffer,
          outputType: outputType,
          outputScale: outputScale,
          outputZeroPoint: outputZeroPoint,
          rowStart: rowStart,
          cols: cols,
          classStart: 5,
          multiplyObjectness: true,
        )
      : (0, 0.0);

  return withObj.$2 > noObj.$2 ? withObj : noObj;
}

(int, double) _bestFromRangeRowMajor({
  required Object outputBuffer,
  required TensorType outputType,
  required double outputScale,
  required int outputZeroPoint,
  required int rowStart,
  required int cols,
  required int classStart,
  required bool multiplyObjectness,
}) {
  final classCount = cols - classStart;
  if (classCount <= 0) {
    return (0, 0.0);
  }

  final objectnessRaw = multiplyObjectness
      ? _readOutputValue(
          outputBuffer,
          rowStart + 4,
          outputType,
          outputScale,
          outputZeroPoint,
        )
      : 1.0;
  final objectness = _normalizeConfidence(objectnessRaw);

  var bestClass = 0;
  var bestScore = 0.0;
  for (var c = 0; c < classCount; c++) {
    final classProbRaw = _readOutputValue(
      outputBuffer,
      rowStart + classStart + c,
      outputType,
      outputScale,
      outputZeroPoint,
    );
    final classProb = _normalizeConfidence(classProbRaw);
    final score = classProb * objectness;
    if (score > bestScore) {
      bestScore = score;
      bestClass = c;
    }
  }
  return (bestClass, bestScore);
}

double _normalizeConfidence(double value) {
  if (value.isNaN || value.isInfinite) {
    return 0.0;
  }
  if (value >= 0.0 && value <= 1.0) {
    return value;
  }
  return 1.0 / (1.0 + exp(-value));
}

int _pickPrimaryOutputIndex(List<List<int>> outputShapes) {
  if (outputShapes.isEmpty) {
    return 0;
  }

  var bestIndex = 0;
  var bestScore = -1;
  for (var i = 0; i < outputShapes.length; i++) {
    final shape = outputShapes[i];
    if (shape.length < 3) {
      continue;
    }
    final score = shape.fold<int>(1, (a, b) => a * b);
    if (score > bestScore) {
      bestScore = score;
      bestIndex = i;
    }
  }
  return bestIndex;
}

Object _createOutputBufferForShape(List<int> shape, TensorType type) {
  if (shape.isEmpty) {
    return switch (type) {
      TensorType.int32 => 0,
      TensorType.uint8 => 0,
      TensorType.int8 => 0,
      _ => 0.0,
    };
  }

  if (shape.length == 1) {
    return List.generate(
      shape[0],
      (_) => switch (type) {
        TensorType.int32 => 0,
        TensorType.uint8 => 0,
        TensorType.int8 => 0,
        _ => 0.0,
      },
      growable: false,
    );
  }

  final childShape = shape.sublist(1);
  return List.generate(
    shape[0],
    (_) => _createOutputBufferForShape(childShape, type),
    growable: false,
  );
}

Float32List _flattenOutputBuffer(
  Object? buffer,
  List<int> shape,
  TensorType type,
  double scale,
  int zeroPoint,
) {
  final total = shape.isEmpty ? 0 : shape.fold<int>(1, (a, b) => a * b);
  final out = Float32List(total);
  if (total == 0 || buffer == null) {
    return out;
  }

  var cursor = 0;

  void visit(dynamic node) {
    if (node is List) {
      for (final child in node) {
        visit(child);
      }
      return;
    }

    double value;
    if (node is num) {
      value = node.toDouble();
    } else {
      value = 0.0;
    }

    if (type == TensorType.uint8 || type == TensorType.int8) {
      value = (value - zeroPoint) * scale;
    }

    if (cursor < out.length) {
      out[cursor++] = value;
    }
  }

  visit(buffer);
  return out;
}

Detection _toDetectionWorker({
  required double x,
  required double y,
  required double w,
  required double h,
  required int classIndex,
  required double score,
  required int rotationDegrees,
  required List<String> labels,
  required int inW,
  required int inH,
  required int frameW,
  required int frameH,
  required double roiLeft,
  required double roiTop,
  required double roiRight,
  required double roiBottom,
}) {
  // x, y, w, h come from model in range [0, 1] or pixel space
  double centerX = x;
  double centerY = y;
  double width = w.abs();
  double height = h.abs();

  // If values are large, they're in pixel space - convert to normalized
  if (centerX > 1.0 || centerY > 1.0) {
    centerX = centerX / inW;
    centerY = centerY / inH;
    width = width / inW;
    height = height / inH;
  }

  // Calculate bbox in model space
  double leftModel = centerX - width / 2;
  double topModel = centerY - height / 2;
  double rightModel = centerX + width / 2;
  double bottomModel = centerY + height / 2;

  // Calculate effective crop dimensions with rotation
  final roiWidth = roiRight - roiLeft;
  final roiHeight = roiBottom - roiTop;
  final cropW = max(1.0, roiWidth * frameW);
  final cropH = max(1.0, roiHeight * frameH);

  final deg = ((rotationDegrees % 360) + 360) % 360;
  final isRotated90 = deg == 90 || deg == 270;
  final effectiveCropW = isRotated90 ? cropH : cropW;
  final effectiveCropH = isRotated90 ? cropW : cropH;

  // Reverse letterbox padding
  final letterboxScale = min(inW / effectiveCropW, inH / effectiveCropH);
  final scaledW = effectiveCropW * letterboxScale;
  final scaledH = effectiveCropH * letterboxScale;
  final padX = (inW - scaledW) / 2.0;
  final padY = (inH - scaledH) / 2.0;

  // Remove letterbox padding
  final leftUnpad = (leftModel * inW - padX) / letterboxScale;
  final topUnpad = (topModel * inH - padY) / letterboxScale;
  final rightUnpad = (rightModel * inW - padX) / letterboxScale;
  final bottomUnpad = (bottomModel * inH - padY) / letterboxScale;

  // Convert from crop space to normalized crop space [0, 1]
  final leftCropNorm = leftUnpad / effectiveCropW;
  final topCropNorm = topUnpad / effectiveCropH;
  final rightCropNorm = rightUnpad / effectiveCropW;
  final bottomCropNorm = bottomUnpad / effectiveCropH;

  // Add ROI offset to map back to full frame
  final left = roiLeft + leftCropNorm * roiWidth;
  final top = roiTop + topCropNorm * roiHeight;
  final right = roiLeft + rightCropNorm * roiWidth;
  final bottom = roiTop + bottomCropNorm * roiHeight;

  final label = classIndex >= 0 && classIndex < labels.length
      ? labels[classIndex]
      : 'vat_can';

  final normalized = Detection(
    label: label,
    score: score,
    left: left.clamp(0.0, 1.0),
    top: top.clamp(0.0, 1.0),
    right: right.clamp(0.0, 1.0),
    bottom: bottom.clamp(0.0, 1.0),
  );

  return _mapDetectionBackFromRotated(
    normalized,
    rotationDegrees: rotationDegrees,
  );
}

Detection _mapDetectionBackFromRotated(
  Detection detection, {
  required int rotationDegrees,
}) {
  final deg = ((rotationDegrees % 360) + 360) % 360;
  if (deg == 0) {
    return detection;
  }

  Offset mapPoint(double x, double y) {
    switch (deg) {
      case 90:
        return Offset(1.0 - y, x);
      case 180:
        return Offset(1.0 - x, 1.0 - y);
      case 270:
        return Offset(y, 1.0 - x);
      default:
        return Offset(x, y);
    }
  }

  final p1 = mapPoint(detection.left, detection.top);
  final p2 = mapPoint(detection.right, detection.top);
  final p3 = mapPoint(detection.right, detection.bottom);
  final p4 = mapPoint(detection.left, detection.bottom);

  final left = min(min(p1.dx, p2.dx), min(p3.dx, p4.dx)).clamp(0.0, 1.0);
  final top = min(min(p1.dy, p2.dy), min(p3.dy, p4.dy)).clamp(0.0, 1.0);
  final right = max(max(p1.dx, p2.dx), max(p3.dx, p4.dx)).clamp(0.0, 1.0);
  final bottom = max(max(p1.dy, p2.dy), max(p3.dy, p4.dy)).clamp(0.0, 1.0);

  return Detection(
    label: detection.label,
    score: detection.score,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
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
  final inputType = payload['inputType'] as TensorType;
  final inputScale = payload['inputScale'] as double;
  final inputZeroPoint = payload['inputZeroPoint'] as int;

  final yBytes = payload['yBytes'] as Uint8List;
  final uBytes = payload['uBytes'] as Uint8List;
  final vBytes = payload['vBytes'] as Uint8List;
  final yBytesPerRow = payload['yBytesPerRow'] as int;
  final uBytesPerRow = payload['uBytesPerRow'] as int;
  final uBytesPerPixel = payload['uBytesPerPixel'] as int;
  final vBytesPerRow = payload['vBytesPerRow'] as int;
  final vBytesPerPixel = payload['vBytesPerPixel'] as int;
  final roiLeft = payload['roiLeft'] as double;
  final roiTop = payload['roiTop'] as double;
  final roiRight = payload['roiRight'] as double;
  final roiBottom = payload['roiBottom'] as double;
  final rotationDegrees = (payload['rotationDegrees'] as int?) ?? 0;

  final cropX = (roiLeft * width).floor().clamp(0, width - 1);
  final cropY = (roiTop * height).floor().clamp(0, height - 1);
  final cropW = ((roiRight - roiLeft) * width).floor().clamp(1, width - cropX);
  final cropH = ((roiBottom - roiTop) * height).floor().clamp(1, height - cropY);

  // 1. Convert ROI to img.Image (Optimized YUV -> RGB)
  final image = img.Image(width: cropW, height: cropH);
  for (var y = 0; y < cropH; y++) {
    for (var x = 0; x < cropW; x++) {
      final sx = cropX + x;
      final sy = cropY + y;

      final yp = yBytes[sy * yBytesPerRow + sx];
      final uvIndex = (sy ~/ 2) * uBytesPerRow + (sx ~/ 2) * uBytesPerPixel;
      final up = uBytes[uvIndex];
      final vp = vBytes[(sy ~/ 2) * vBytesPerRow + (sx ~/ 2) * vBytesPerPixel];

      final c = max(0, yp - 16);
      final d = up - 128;
      final e = vp - 128;

      final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
      final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
      final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);

      image.setPixelRgb(x, y, r, g, b);
    }
  }

  // 2. Rotate using library
  var processed = image;
  if (rotationDegrees != 0) {
    processed = img.copyRotate(image, angle: rotationDegrees);
  }

  // 3. Resize with Letterboxing using library
  final resized = img.copyResize(
    processed,
    width: inputWidth,
    height: inputHeight,
    maintainAspect: true,
    backgroundColor: img.ColorRgb8(0, 0, 0),
  );

  // 4. Fill Tensor Buffer
  final inputSize = inputWidth * inputHeight * 3;
  if (inputType == TensorType.uint8 || inputType == TensorType.int8) {
    if (inputType == TensorType.uint8) {
      final flat = Uint8List(inputSize);
      var cursor = 0;
      for (final pixel in resized) {
        flat[cursor++] = ((pixel.r / 255.0) / inputScale + inputZeroPoint).round().clamp(0, 255);
        flat[cursor++] = ((pixel.g / 255.0) / inputScale + inputZeroPoint).round().clamp(0, 255);
        flat[cursor++] = ((pixel.b / 255.0) / inputScale + inputZeroPoint).round().clamp(0, 255);
      }
      return flat;
    } else {
      final flat = Int8List(inputSize);
      var cursor = 0;
      for (final pixel in resized) {
        flat[cursor++] = ((pixel.r / 255.0) / inputScale + inputZeroPoint).round().clamp(-128, 127);
        flat[cursor++] = ((pixel.g / 255.0) / inputScale + inputZeroPoint).round().clamp(-128, 127);
        flat[cursor++] = ((pixel.b / 255.0) / inputScale + inputZeroPoint).round().clamp(-128, 127);
      }
      return flat;
    }
  } else {
    // float16 or float32 models use Float32List
    final flat = Float32List(inputSize);
    var cursor = 0;
    for (final pixel in resized) {
      flat[cursor++] = pixel.r / 255.0;
      flat[cursor++] = pixel.g / 255.0;
      flat[cursor++] = pixel.b / 255.0;
    }
    return flat;
  }
}




