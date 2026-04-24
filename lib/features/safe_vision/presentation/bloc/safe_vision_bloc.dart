import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/safe_vision_mode.dart';
import '../../domain/repositories/speech_repository.dart';
import '../../domain/repositories/vision_repository.dart';
import '../../domain/services/audio_manager.dart';
import '../../domain/services/object_tracker.dart';
import '../../domain/services/safe_vision_policy.dart';
import '../../domain/usecases/detect_objects_usecase.dart';
import '../../domain/usecases/initialize_vision_usecase.dart';
import '../../domain/usecases/speak_message_usecase.dart';
import 'safe_vision_event.dart';
import 'safe_vision_state.dart';

class SafeVisionBloc extends Bloc<SafeVisionEvent, SafeVisionState> {
  static const int _frameThrottleMs = 67;

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
       _audioManager = AudioManager(speakMessageUseCase),
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
  final AudioManager _audioManager;
  final IoUObjectTracker _objectTracker = IoUObjectTracker();

  DateTime _lastFrameAcceptedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isProcessingFrame = false;
  Map<String, SafeVisionLabelMetadata> _labelMetadata = const {};

  DateTime _lastFpsCalculationTime = DateTime.now();
  int _frameCount = 0;
  double _currentFps = 0.0;
  final double _confidenceThreshold = 0.40;

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
          statusText: 'Safe Vision dang hoat dong',
          isFrontCamera:
              _visionRepository.currentLensDirection ==
              CameraLensDirection.front,
          errorMessage: null,
        ),
      );
      await _speakMessageUseCase(
        'Safe Vision da san sang. Hay dua camera huong ve phia truoc.',
        interrupt: false,
      );
    } catch (e) {
      emit(
        state.copyWith(
          isInitializing: false,
          statusText: 'Khong the khoi tao: $e',
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
      _frameCount++;
      final now = DateTime.now();
      final diff = now.difference(_lastFpsCalculationTime).inMilliseconds;
      if (diff >= 1000) {
        _currentFps = _frameCount * 1000 / diff;
        _frameCount = 0;
        _lastFpsCalculationTime = now;
      }

      final rawDetections = await _detectObjectsUseCase(
        event.image,
        confidenceThreshold: _confidenceThreshold,
      );
      
      // If no detections, clear tracker to remove old boxes immediately
      if (rawDetections.isEmpty) {
        _objectTracker.reset();
      }
      
      final trackedDetections = _objectTracker.process(rawDetections);
      final detections = SafeVisionPolicy.filterDetectionsForMode(
        state.mode,
        trackedDetections,
        _labelMetadata,
      );
      final status = SafeVisionPolicy.buildStatusText(
        state.mode,
        detections,
        _labelMetadata,
      );
      final fpsText = 'FPS: ${_currentFps.toStringAsFixed(1)}';

      emit(
        state.copyWith(
          rawDetections: rawDetections,
          detections: detections,
          statusText: '$status | $fpsText',
          errorMessage: null,
        ),
      );

      await _audioManager.processDetections(
        mode: state.mode,
        detections: detections,
        metadata: _labelMetadata,
      );
    } catch (e, st) {
      debugPrint('SafeVision frame error: $e');
      debugPrint('$st');
      emit(
        state.copyWith(
          statusText: 'Loi xu ly khung hinh: $e',
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

    _objectTracker.reset();
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

    _audioManager.reset();
    switch (event.mode) {
      case SafeVisionMode.outdoor:
        await _speakMessageUseCase('Che do di chuyen ngoai troi.');
      case SafeVisionMode.indoor:
        await _speakMessageUseCase('Che do tim vat trong nha.');
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
      _audioManager.reset();
      _objectTracker.reset();

      final controller = await _visionRepository.switchCamera();
      await _visionRepository.startImageStream(_enqueueFrame);

      final isFront =
          _visionRepository.currentLensDirection == CameraLensDirection.front;
      emit(
        state.copyWith(
          isInitializing: false,
          cameraController: controller,
          isFrontCamera: isFront,
          statusText: isFront ? 'Dang dung camera truoc' : 'Dang dung camera sau',
        ),
      );

      await _speakMessageUseCase(
        isFront
            ? 'Da chuyen sang camera truoc.'
            : 'Da chuyen sang camera sau.',
      );
    } catch (e) {
      emit(
        state.copyWith(
          isInitializing: false,
          statusText: 'Khong the doi camera: $e',
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

      _labelMetadata = {
        ..._defaultLabelMetadata(),
        ...mapped,
      };
    } catch (_) {
      _labelMetadata = _defaultLabelMetadata();
    }
  }

  Map<String, SafeVisionLabelMetadata> _defaultLabelMetadata() {
    return const {
      'car': SafeVisionLabelMetadata(
        viLabel: 'o to',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'xe': SafeVisionLabelMetadata(
        viLabel: 'o to',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'ho': SafeVisionLabelMetadata(
        viLabel: 'ho',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'hole': SafeVisionLabelMetadata(
        viLabel: 'ho',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'lua': SafeVisionLabelMetadata(
        viLabel: 'lua',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'fire': SafeVisionLabelMetadata(
        viLabel: 'lua',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'cau_thang': SafeVisionLabelMetadata(
        viLabel: 'cau thang',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'stairs': SafeVisionLabelMetadata(
        viLabel: 'cau thang',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'door': SafeVisionLabelMetadata(
        viLabel: 'cua ra vao',
        bucket: SafeVisionLabelBucket.instruction,
      ),
      'cua': SafeVisionLabelMetadata(
        viLabel: 'cua ra vao',
        bucket: SafeVisionLabelBucket.instruction,
      ),
      'person': SafeVisionLabelMetadata(
        viLabel: 'nguoi',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'nguoi_di_bo': SafeVisionLabelMetadata(
        viLabel: 'nguoi di bo',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'balo': SafeVisionLabelMetadata(
        viLabel: 'ba lo',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'vi': SafeVisionLabelMetadata(
        viLabel: 'vi',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'ban': SafeVisionLabelMetadata(
        viLabel: 'ban',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'ghe': SafeVisionLabelMetadata(
        viLabel: 'ghe',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'cay': SafeVisionLabelMetadata(
        viLabel: 'cay',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'dien_thoai': SafeVisionLabelMetadata(
        viLabel: 'dien thoai',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'laptop': SafeVisionLabelMetadata(
        viLabel: 'laptop',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'den_giao_thong': SafeVisionLabelMetadata(
        viLabel: 'den giao thong',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      'mep_duong': SafeVisionLabelMetadata(
        viLabel: 'mep duong',
        bucket: SafeVisionLabelBucket.warning,
      ),
      'thung_rac': SafeVisionLabelMetadata(
        viLabel: 'thung rac',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      '1k': SafeVisionLabelMetadata(
        viLabel: 'mot nghin',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      '2k': SafeVisionLabelMetadata(
        viLabel: 'hai nghin',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      '5k': SafeVisionLabelMetadata(
        viLabel: 'nam nghin',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      '10k': SafeVisionLabelMetadata(
        viLabel: 'muoi nghin',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      '20k': SafeVisionLabelMetadata(
        viLabel: 'hai muoi nghin',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      '50k': SafeVisionLabelMetadata(
        viLabel: 'nam muoi nghin',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      '100k': SafeVisionLabelMetadata(
        viLabel: 'mot tram nghin',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      '200k': SafeVisionLabelMetadata(
        viLabel: 'hai tram nghin',
        bucket: SafeVisionLabelBucket.recognition,
      ),
      '500k': SafeVisionLabelMetadata(
        viLabel: 'nam tram nghin',
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
