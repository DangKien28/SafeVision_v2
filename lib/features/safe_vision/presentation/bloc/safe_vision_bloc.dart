import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/detection.dart';
import '../../domain/entities/safe_vision_mode.dart';
import '../../domain/repositories/speech_repository.dart';
import '../../domain/repositories/vision_repository.dart';
import '../../domain/usecases/detect_objects_usecase.dart';
import '../../domain/usecases/initialize_vision_usecase.dart';
import '../../domain/usecases/speak_message_usecase.dart';
import 'safe_vision_event.dart';
import 'safe_vision_state.dart';

class SafeVisionBloc extends Bloc<SafeVisionEvent, SafeVisionState> {
  static const int _frameThrottleMs = 33;
  static const int _ttsCooldownMs = 1200;

  SafeVisionBloc({
    required InitializeVisionUseCase initializeVisionUseCase,
    required DetectObjectsUseCase detectObjectsUseCase,
    required SpeakMessageUseCase speakMessageUseCase,
    required VisionRepository visionRepository,
    required SpeechRepository speechRepository,
  }) : _initializeVisionUseCase = initializeVisionUseCase,
       _detectObjectsUseCase = detectObjectsUseCase,
       _speakMessageUseCase = speakMessageUseCase,
       _visionRepository = visionRepository,
       _speechRepository = speechRepository,
       super(SafeVisionState.initial()) {
    on<SafeVisionStarted>(_onStarted);
     on<CameraFrameReceived>(_onFrameReceived);
    on<SafeVisionModeChanged>(_onModeChanged);
    on<SafeVisionModeSwiped>(_onModeSwiped);
    on<CameraLensToggled>(_onCameraLensToggled);
  }

  final InitializeVisionUseCase _initializeVisionUseCase;
  final DetectObjectsUseCase _detectObjectsUseCase;
  final SpeakMessageUseCase _speakMessageUseCase;
  final VisionRepository _visionRepository;
  final SpeechRepository _speechRepository;

  DateTime _lastFrameAcceptedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSmartTtsAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isProcessingFrame = false;
  Map<String, _LabelMetadata> _labelMetadata = const {};
  Set<String> _lastWarningKeys = <String>{};

  Future<void> _onStarted(
    SafeVisionStarted event,
    Emitter<SafeVisionState> emit,
  ) async {
    try {
      await _loadTtsMetadata();
      await _speakMessageUseCase.configure();
      final controller = await _initializeVisionUseCase();

      await _visionRepository.startImageStream((image) {
        _enqueueFrame(image);
      });

      emit(
        state.copyWith(
          isInitializing: false,
          cameraController: controller,
          statusText: 'Safe Vision đang hoạt động',
          isFrontCamera:
              _visionRepository.currentLensDirection ==
              CameraLensDirection.front,
          errorMessage: null,
        ),
      );
      await _speakMessageUseCase(
        'Safe Vision đã sẵn sàng. Hãy đưa camera hướng về phía trước.',
        interrupt: false,
      );
    } catch (e) {
      emit(
        state.copyWith(
          isInitializing: false,
          statusText: 'Không thể khởi tạo: $e',
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _onFrameReceived(
    CameraFrameReceived event,
    Emitter<SafeVisionState> emit,
  ) async {
    try {
      final detections = await _detectObjectsUseCase(event.image);
      final status = _buildStatusText(state.mode, detections);

      emit(
        state.copyWith(
          detections: detections,
          statusText: status,
          errorMessage: null,
        ),
      );

      await _speakRiskAlert(state.mode, detections);
    } catch (_) {
      // Keep stream alive when malformed frame appears.
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _onModeChanged(
    SafeVisionModeChanged event,
    Emitter<SafeVisionState> emit,
  ) async {
    if (event.mode == state.mode) {
      return;
    }

    emit(
      state.copyWith(
        mode: event.mode,
        statusText: _buildStatusText(event.mode, state.detections),
      ),
    );

    switch (event.mode) {
      case SafeVisionMode.outdoor:
        await _speakMessageUseCase('Chế độ di chuyển ngoài trời.');
      case SafeVisionMode.indoor:
        await _speakMessageUseCase('Chế độ tìm vật trong nhà.');
      case SafeVisionMode.tutorial:
        await _speakMessageUseCase(
          'Chế độ hướng dẫn. Vuốt qua trái hoặc phải để chuyển chế độ.',
        );
    }
  }

  Future<void> _onModeSwiped(
    SafeVisionModeSwiped event,
    Emitter<SafeVisionState> emit,
  ) async {
    final nextIndex = event.toNext
        ? (state.mode.index + 1) % SafeVisionMode.values.length
        : (state.mode.index - 1 + SafeVisionMode.values.length) %
              SafeVisionMode.values.length;
    add(SafeVisionModeChanged(SafeVisionMode.values[nextIndex]));
  }

  Future<void> _onCameraLensToggled(
    CameraLensToggled event,
    Emitter<SafeVisionState> emit,
  ) async {
    try {
      emit(state.copyWith(isInitializing: true));
      _isProcessingFrame = false;
      _lastFrameAcceptedAt = DateTime.fromMillisecondsSinceEpoch(0);

      final controller = await _visionRepository.switchCamera();
      await _visionRepository.startImageStream((image) {
        _enqueueFrame(image);
      });

      final isFront =
          _visionRepository.currentLensDirection == CameraLensDirection.front;
      emit(
        state.copyWith(
          isInitializing: false,
          cameraController: controller,
          isFrontCamera: isFront,
          statusText: isFront
              ? 'Đang dùng camera trước'
              : 'Đang dùng camera sau',
        ),
      );

      await _speakMessageUseCase(
        isFront ? 'Đã chuyển sang camera trước.' : 'Đã chuyển sang camera sau.',
      );
    } catch (e) {
      emit(
        state.copyWith(
          isInitializing: false,
          statusText: 'Không thể đổi camera: $e',
          errorMessage: e.toString(),
        ),
      );
    }
  }

  void _enqueueFrame(CameraImage image) {
    if (_isProcessingFrame) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastFrameAcceptedAt).inMilliseconds <
        _frameThrottleMs) {
      return;
    }

    _lastFrameAcceptedAt = now;
    _isProcessingFrame = true;
    add(CameraFrameReceived(image));
  }

  String _buildStatusText(SafeVisionMode mode, List<Detection> detections) {
    if (detections.isEmpty) {
      return mode == SafeVisionMode.tutorial
          ? 'Chế độ hướng dẫn: vuốt trái/phải để đổi chế độ'
          : 'Không có vật cản nguy hiểm';
    }
    final top = detections.first;
    final percent = (top.score * 100).toStringAsFixed(0);
    return 'Phát hiện: ${top.labelVi} ($percent%)';
  }

  Future<void> _speakRiskAlert(
    SafeVisionMode mode,
    List<Detection> detections,
  ) async {
    if (mode == SafeVisionMode.tutorial || detections.isEmpty) {
      return;
    }

    final grouped = <String, int>{};
    final firstByLabel = <String, Detection>{};

    for (final detection in detections) {
      grouped.update(detection.label, (value) => value + 1, ifAbsent: () => 1);
      firstByLabel.putIfAbsent(detection.label, () => detection);
    }

    final warningItems = <_BucketItem>[];
    final instructionItems = <_BucketItem>[];
    final recognitionItems = <_BucketItem>[];

    grouped.forEach((rawLabel, count) {
      final metadata = _labelMetadata[rawLabel.toLowerCase().trim()];
      final viLabel =
          metadata?.viLabel ??
          firstByLabel[rawLabel]?.labelVi ??
          rawLabel.replaceAll('_', ' ');
      final bucket = metadata?.bucket ?? _TtsBucket.recognition;

      final item = _BucketItem(
        rawLabel: rawLabel,
        viLabel: viLabel,
        count: count,
      );

      switch (bucket) {
        case _TtsBucket.warning:
          warningItems.add(item);
        case _TtsBucket.instruction:
          instructionItems.add(item);
        case _TtsBucket.recognition:
          recognitionItems.add(item);
      }
    });

    warningItems.sort((a, b) => b.count.compareTo(a.count));
    instructionItems.sort((a, b) => b.count.compareTo(a.count));
    recognitionItems.sort((a, b) => b.count.compareTo(a.count));

    final warningKeys = warningItems.map((e) => e.key).toSet();
    final hasNewWarning = warningKeys.difference(_lastWarningKeys).isNotEmpty;

    if (_speakMessageUseCase.isSpeaking && !hasNewWarning) {
      return;
    }

    if (_speakMessageUseCase.isSpeaking && hasNewWarning) {
      await _speakMessageUseCase.stop();
    }

    final now = DateTime.now();
    if (!hasNewWarning &&
        now.difference(_lastSmartTtsAt).inMilliseconds < _ttsCooldownMs) {
      return;
    }

    final message = _buildSmartMessage(
      warningItems: warningItems,
      instructionItems: instructionItems,
      recognitionItems: recognitionItems,
    );

    if (message.isEmpty) {
      return;
    }

    await _speakMessageUseCase(message, interrupt: false);
    _lastSmartTtsAt = now;
    _lastWarningKeys = warningKeys;
  }

  String _buildSmartMessage({
    required List<_BucketItem> warningItems,
    required List<_BucketItem> instructionItems,
    required List<_BucketItem> recognitionItems,
  }) {
    final chunks = <String>[];

    if (warningItems.isNotEmpty) {
      chunks.add('Cảnh báo có ${_joinBucketPhrases(warningItems)}.');
    }

    if (instructionItems.isNotEmpty) {
      chunks.add('Hướng dẫn ${_joinBucketPhrases(instructionItems)}.');
    }

    if (warningItems.isEmpty && recognitionItems.isNotEmpty) {
      chunks.add('Nhận diện ${_joinBucketPhrases(recognitionItems)}.');
    }

    return chunks.join(' ').trim();
  }

  String _joinBucketPhrases(List<_BucketItem> items) {
    final phrases = items.map((e) => e.phrase).toList(growable: false);
    if (phrases.isEmpty) {
      return '';
    }
    if (phrases.length == 1) {
      return phrases.first;
    }
    if (phrases.length == 2) {
      return '${phrases[0]} và ${phrases[1]}';
    }
    final head = phrases.sublist(0, phrases.length - 1).join(', ');
    return '$head và ${phrases.last}';
  }

  Future<void> _loadTtsMetadata() async {
    if (_labelMetadata.isNotEmpty) {
      return;
    }

    try {
      final rawJson = await rootBundle.loadString('assets/labels_vi.json');
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        _labelMetadata = _defaultLabelMetadata();
        return;
      }

      final mapped = <String, _LabelMetadata>{};
      decoded.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          final vi = (value['vi'] ?? value['labelVi'] ?? key).toString();
          final group = (value['group'] ?? value['bucket'] ?? 'recognition')
              .toString()
              .toLowerCase();
          mapped[key.toLowerCase().trim()] = _LabelMetadata(
            viLabel: vi,
            bucket: switch (group) {
              'warning' => _TtsBucket.warning,
              'instruction' => _TtsBucket.instruction,
              _ => _TtsBucket.recognition,
            },
          );
          return;
        }

        if (value is String) {
          mapped[key.toLowerCase().trim()] = _LabelMetadata(
            viLabel: value,
            bucket: _TtsBucket.recognition,
          );
        }
      });

      _labelMetadata = mapped.isEmpty ? _defaultLabelMetadata() : mapped;
    } catch (_) {
      _labelMetadata = _defaultLabelMetadata();
    }
  }

  Map<String, _LabelMetadata> _defaultLabelMetadata() {
    return const {
      'car': _LabelMetadata(viLabel: 'ô tô', bucket: _TtsBucket.warning),
      'xe': _LabelMetadata(viLabel: 'ô tô', bucket: _TtsBucket.warning),
      'ho': _LabelMetadata(viLabel: 'hố', bucket: _TtsBucket.warning),
      'hole': _LabelMetadata(viLabel: 'hố', bucket: _TtsBucket.warning),
      'lua': _LabelMetadata(viLabel: 'lửa', bucket: _TtsBucket.warning),
      'fire': _LabelMetadata(viLabel: 'lửa', bucket: _TtsBucket.warning),
      'cau_thang': _LabelMetadata(
        viLabel: 'cầu thang',
        bucket: _TtsBucket.warning,
      ),
      'stairs': _LabelMetadata(
        viLabel: 'cầu thang',
        bucket: _TtsBucket.warning,
      ),
      'door': _LabelMetadata(
        viLabel: 'cửa ra vào',
        bucket: _TtsBucket.instruction,
      ),
      'cua': _LabelMetadata(
        viLabel: 'cửa ra vào',
        bucket: _TtsBucket.instruction,
      ),
      'person': _LabelMetadata(
        viLabel: 'người',
        bucket: _TtsBucket.recognition,
      ),
      'nguoi_di_bo': _LabelMetadata(
        viLabel: 'người đi bộ',
        bucket: _TtsBucket.recognition,
      ),
      'balo': _LabelMetadata(viLabel: 'ba lô', bucket: _TtsBucket.recognition),
      'ban': _LabelMetadata(viLabel: 'bàn', bucket: _TtsBucket.recognition),
      'ghe': _LabelMetadata(viLabel: 'ghế', bucket: _TtsBucket.recognition),
      'cay': _LabelMetadata(viLabel: 'cây', bucket: _TtsBucket.recognition),
      'dien_thoai': _LabelMetadata(
        viLabel: 'điện thoại',
        bucket: _TtsBucket.recognition,
      ),
      'laptop': _LabelMetadata(
        viLabel: 'laptop',
        bucket: _TtsBucket.recognition,
      ),
    };
  }

  @override
  Future<void> close() async {
    await _speakMessageUseCase.stop();
    await _visionRepository.dispose();
    await _speechRepository.dispose();
    return super.close();
  }
}

enum _TtsBucket { warning, instruction, recognition }

class _LabelMetadata {
  const _LabelMetadata({required this.viLabel, required this.bucket});

  final String viLabel;
  final _TtsBucket bucket;
}

class _BucketItem {
  const _BucketItem({
    required this.rawLabel,
    required this.viLabel,
    required this.count,
  });

  final String rawLabel;
  final String viLabel;
  final int count;

  String get phrase => '$count $viLabel';
  String get key => '$rawLabel:$count';
}
