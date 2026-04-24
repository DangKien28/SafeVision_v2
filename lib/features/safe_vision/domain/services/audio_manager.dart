import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../domain/entities/detection.dart';
import '../../domain/entities/safe_vision_mode.dart';
import '../../domain/usecases/speak_message_usecase.dart';
import 'safe_vision_policy.dart';

// Priority handled by PriorityLevel enum from SafeVisionPolicy

class AudioManager {
  AudioManager(this._speakMessageUseCase);

  final SpeakMessageUseCase _speakMessageUseCase;
  final AudioPlayer _audioPlayer = AudioPlayer();
 
  DateTime _lastSmartTtsAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSpokenMessageKey = '';
  Set<String> _lastWarningKeys = <String>{};
  bool _isBeeping = false;

  final Map<int, _TrackedAudioState> _trackedAudioStates = {};

  static const int _ttsCooldownMs = 1200;
  static const int _ttsWarningCooldownMs = 500;
  static const int _repeatCooldownMs = 5000;
  // Stale track states older than this are always pruned
  static const int _trackMaxAgeMs = 10000;

  Future<void> processDetections({
    required SafeVisionMode mode,
    required List<Detection> detections,
    required Map<String, SafeVisionLabelMetadata> metadata,
  }) async {
    final now = DateTime.now();

    // FIX: always prune stale tracks, not just when detections are present
    _trackedAudioStates.removeWhere(
      (_, value) =>
          now.difference(value.lastSpokenAt).inMilliseconds > _trackMaxAgeMs,
    );

    final urgentDetections = <Detection>[];
    PriorityLevel highestPriority = PriorityLevel.p3;

    for (final detection in detections) {
      final riskZone = SafeVisionPolicy.getRiskZone(detection, metadata);
      final priority = SafeVisionPolicy.getPriorityLevel(detection, riskZone, metadata);

      if (priority.index < highestPriority.index) {
        highestPriority = priority;
      }

      final trackId = detection.trackingId;
      if (trackId != null) {
        final state = _trackedAudioStates[trackId];
        final isRiskEscalated =
            state != null && riskZone.index > state.lastRiskZone.index;
        final isTimeExpired = state != null &&
            now.difference(state.lastSpokenAt).inMilliseconds >
                _repeatCooldownMs;

        if (state == null || isRiskEscalated || isTimeExpired) {
          urgentDetections.add(detection);
        }
      } else {
        urgentDetections.add(detection);
      }
    }

    if (urgentDetections.isEmpty) {
      return;
    }

    final payload = SafeVisionPolicy.buildSpeechPayload(
      mode: mode,
      detections: urgentDetections,
      metadata: metadata,
    );

    if (payload.message.isEmpty) {
      _lastWarningKeys = payload.warningKeys;
      return;
    }

    // Preemption: Stop if higher priority arrives
    final isHighPriority = highestPriority == PriorityLevel.p0 || highestPriority == PriorityLevel.p1;
    final hasNewWarning =
        payload.warningKeys.difference(_lastWarningKeys).isNotEmpty;

    if (_speakMessageUseCase.isSpeaking) {
      if (isHighPriority || hasNewWarning) {
        await _speakMessageUseCase.stop();
      } else {
        return;
      }
    }

    if (payload.messageKey == _lastSpokenMessageKey && !isHighPriority) {
      return;
    }

    final cooldown = (isHighPriority || hasNewWarning)
        ? _ttsWarningCooldownMs
        : _ttsCooldownMs;
    if (now.difference(_lastSmartTtsAt).inMilliseconds < cooldown) {
      return;
    }

    if (isHighPriority || hasNewWarning) {
      // Spatial Audio Panning & Beep Modulation
      final topDetection = urgentDetections.first;
      final distance = SafeVisionPolicy.estimateDistance(topDetection);
      final balance = (topDetection.centerX * 2) - 1.0; // [-1.0, 1.0]
      
      debugPrint('SafeVision_Audio: Priority=${highestPriority.name}, Label=${topDetection.label}, Dist=${distance.toStringAsFixed(2)}m, Balance=${balance.toStringAsFixed(2)}');
      await _playPriorityBeeps(highestPriority, distance, balance);
    }
 
    if (highestPriority != PriorityLevel.p3) {
      debugPrint('SafeVision_Audio: Speaking message: "${payload.message}"');
      await _speakMessageUseCase(payload.message, interrupt: true);
    } else {
      debugPrint('SafeVision_Audio: Skipping TTS for P3 priority');
    }

    _lastSmartTtsAt = now;
    _lastWarningKeys = payload.warningKeys;
    _lastSpokenMessageKey = payload.messageKey;

    for (final detection in urgentDetections) {
      if (detection.trackingId != null) {
        _trackedAudioStates[detection.trackingId!] = _TrackedAudioState(
          lastSpokenAt: now,
          lastRiskZone: SafeVisionPolicy.getRiskZone(detection, metadata),
        );
      }
    }
  }

  void reset() {
    _lastSmartTtsAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastSpokenMessageKey = '';
    _lastWarningKeys.clear();
    _trackedAudioStates.clear();
    _audioPlayer.stop();
    _isBeeping = false;
  }
 
  Future<void> _playPriorityBeeps(PriorityLevel level, double distance, double balance) async {
    if (_isBeeping) return;
    _isBeeping = true;
    try {
      await _audioPlayer.setBalance(balance);
      
      if (level == PriorityLevel.p0) {
        // Emergency: Fast, urgent beeps
        for (int i = 0; i < 3; i++) {
          await _audioPlayer.play(AssetSource('Beep_Sound.mp3'), volume: 1.0);
          await Future.delayed(const Duration(milliseconds: 250));
        }
      } else if (level == PriorityLevel.p1) {
        // High priority: Normal beeps, rate depends on distance
        final delay = (distance * 100).clamp(300, 800).toInt();
        await _audioPlayer.play(AssetSource('Beep_Sound.mp3'), volume: 0.8);
        await Future.delayed(Duration(milliseconds: delay));
      } else {
        // Lower priority: Subtle beep or nothing
        await _audioPlayer.play(AssetSource('Beep_Sound.mp3'), volume: 0.3);
      }
    } catch (e) {
      debugPrint('Beep error: $e');
    } finally {
      _isBeeping = false;
    }
  }
}

class _TrackedAudioState {
  _TrackedAudioState({
    required this.lastSpokenAt,
    required this.lastRiskZone,
  });

  final DateTime lastSpokenAt;
  final RiskZone lastRiskZone;
}