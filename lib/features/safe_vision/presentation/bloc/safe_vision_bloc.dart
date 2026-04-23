import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/safe_vision_mode.dart';
import '../../domain/repositories/speech_repository.dart';
import '../../domain/repositories/vision_repository.dart';
import '../../domain/services/safe_vision_policy.dart';
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
  Map<String, SafeVisionLabelMetadata> _labelMetadata = const {};
  Set<String> _lastWarningKeys = <String>{};
  String _lastSpokenMessageKey = '';

  Future<void> _onStarted(
    SafeVisionStarted event,
    Emitter<SafeVisionState> emit,
  ) async {
    try {
      await _loadTtsMetadata();
      await _speakMessageUseCase.configure();
      final controller = await _initializeVisionUseCase();

      await _visionRepository.startImageStream(_enqueueFrame);

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
      final rawDetections = await _detectObjectsUseCase(event.image);
      final detections = SafeVisionPolicy.filterDetectionsForMode(
        state.mode,
        rawDetections,
        _labelMetadata,
      );
      final status = SafeVisionPolicy.buildStatusText(
        state.mode,
        detections,
        _labelMetadata,
      );

      emit(
        state.copyWith(
          rawDetections: rawDetections,
          detections: detections,
          statusText: status,
          errorMessage: null,
        ),
      );

      await _speakRiskAlert(state.mode, detections);
    } catch (e, st) {
      debugPrint('SafeVision frame error: $e');
      debugPrint('$st');
      emit(
        state.copyWith(
          statusText: 'Lỗi xử lý khung hình: $e',
          errorMessage: e.toString(),
        ),
      );
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

    final modeDetections = SafeVisionPolicy.filterDetectionsForMode(
      event.mode,
      state.rawDetections,
      _labelMetadata,
    );

    emit(
      state.copyWith(
        mode: event.mode,
        detections: modeDetections,
        statusText: SafeVisionPolicy.buildStatusText(
          event.mode,
          modeDetections,
          _labelMetadata,
        ),
      ),
    );

    switch (event.mode) {
      case SafeVisionMode.outdoor:
        _lastWarningKeys = <String>{};
        _lastSpokenMessageKey = '';
        await _speakMessageUseCase('Chế độ di chuyển ngoài trời.');
      case SafeVisionMode.indoor:
        _lastWarningKeys = <String>{};
        _lastSpokenMessageKey = '';
        await _speakMessageUseCase('Chế độ tìm vật trong nhà.');
      case SafeVisionMode.tutorial:
        _lastWarningKeys = <String>{};
        _lastSpokenMessageKey = '';
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
      _lastWarningKeys = <String>{};
      _lastSpokenMessageKey = '';

      final controller = await _visionRepository.switchCamera();
      await _visionRepository.startImageStream(_enqueueFrame);

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
        isFront
            ? 'Đã chuyển sang camera trước.'
            : 'Đã chuyển sang camera sau.',
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

  Future<void> _speakRiskAlert(
    SafeVisionMode mode,
    List<dynamic> detections,
  ) async {
    final payload = SafeVisionPolicy.buildSpeechPayload(
      mode: mode,
      detections: detections.cast(),
      metadata: _labelMetadata,
    );
    if (payload.message.isEmpty) {
      _lastSpokenMessageKey = '';
      _lastWarningKeys = payload.warningKeys;
      return;
    }

    if (payload.messageKey == _lastSpokenMessageKey) {
      return;
    }

    final hasNewWarning =
        payload.warningKeys.difference(_lastWarningKeys).isNotEmpty;

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

    await _speakMessageUseCase(payload.message, interrupt: false);
    _lastSmartTtsAt = now;
    _lastWarningKeys = payload.warningKeys;
    _lastSpokenMessageKey = payload.messageKey;
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

      final mapped = <String, SafeVisionLabelMetadata>{};
      decoded.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          final vi = (value['vi'] ?? value['labelVi'] ?? key).toString();
          final group = (value['group'] ?? value['bucket'] ?? 'recognition')
              .toString()
              .toLowerCase();
          mapped[key.toLowerCase().trim()] = SafeVisionLabelMetadata(
            viLabel: vi,
            bucket: switch (group) {
              'warning' => SafeVisionLabelBucket.warning,
              'instruction' => SafeVisionLabelBucket.instruction,
              _ => SafeVisionLabelBucket.recognition,
            },
          );
          return;
        }

        if (value is String) {
          mapped[key.toLowerCase().trim()] = SafeVisionLabelMetadata(
            viLabel: value,
            bucket: SafeVisionLabelBucket.recognition,
          );
        }
      });

      _labelMetadata = mapped.isEmpty ? _defaultLabelMetadata() : mapped;
    } catch (_) {
      _labelMetadata = _defaultLabelMetadata();
    }
  }

  Map<String, SafeVisionLabelMetadata> _defaultLabelMetadata() {
    return const {
      'car': SafeVisionLabelMetadata(
        viLabel: 'ô tô',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'xe': SafeVisionLabelMetadata(
        viLabel: 'ô tô',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'ho': SafeVisionLabelMetadata(
        viLabel: 'hố',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'hole': SafeVisionLabelMetadata(
        viLabel: 'hố',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'lua': SafeVisionLabelMetadata(
        viLabel: 'lửa',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'fire': SafeVisionLabelMetadata(
        viLabel: 'lửa',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'cau_thang': SafeVisionLabelMetadata(
        viLabel: 'cầu thang',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'stairs': SafeVisionLabelMetadata(
        viLabel: 'cầu thang',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'door': SafeVisionLabelMetadata(
        viLabel: 'cửa ra vào',
        bucket: SafeVisionLabelBucket.instruction,
      ),
      'cua': SafeVisionLabelMetadata(
        viLabel: 'cửa ra vào',
        bucket: SafeVisionLabelBucket.instruction,
      ),
      'person': SafeVisionLabelMetadata(
        viLabel: 'người',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'nguoi_di_bo': SafeVisionLabelMetadata(
        viLabel: 'người đi bộ',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'balo': SafeVisionLabelMetadata(
        viLabel: 'ba lô',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'ban': SafeVisionLabelMetadata(
        viLabel: 'bàn',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'ghe': SafeVisionLabelMetadata(
        viLabel: 'ghế',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'cay': SafeVisionLabelMetadata(
        viLabel: 'cây',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'dien_thoai': SafeVisionLabelMetadata(
        viLabel: 'điện thoại',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'laptop': SafeVisionLabelMetadata(
        viLabel: 'laptop',
        bucket: SafeVisionLabelBucket.recognition,
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
