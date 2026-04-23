import '../../domain/entities/detection.dart';
import '../../domain/entities/safe_vision_mode.dart';
import '../../domain/usecases/speak_message_usecase.dart';
import 'safe_vision_policy.dart';

enum AudioPriority { low, medium, high }

class AudioManager {
  AudioManager(this._speakMessageUseCase);

  final SpeakMessageUseCase _speakMessageUseCase;

  DateTime _lastSmartTtsAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSpokenMessageKey = '';
  Set<String> _lastWarningKeys = <String>{};

  // Track when an object ID was last spoken and at what risk level
  final Map<int, _TrackedAudioState> _trackedAudioStates = {};

  static const int _ttsCooldownMs = 1200;
  static const int _ttsWarningCooldownMs = 500;
  // How long to wait before repeating the same object if its risk hasn't increased
  static const int _repeatCooldownMs = 5000; 

  Future<void> processDetections({
    required SafeVisionMode mode,
    required List<Detection> detections,
    required Map<String, SafeVisionLabelMetadata> metadata,
  }) async {
    // Filter detections that need to be spoken based on state tracking
    final now = DateTime.now();
    final urgentDetections = <Detection>[];
    var highestPriority = AudioPriority.low;

    for (final detection in detections) {
      final riskZone = SafeVisionPolicy.getRiskZone(detection);
      final priority = _getPriority(detection, riskZone, metadata);
      
      if (priority.index > highestPriority.index) {
        highestPriority = priority;
      }

      final trackId = detection.trackingId;
      if (trackId != null) {
        final state = _trackedAudioStates[trackId];
        final isRiskEscalated = state != null && riskZone.index > state.lastRiskZone.index;
        final isTimeExpired = state != null && now.difference(state.lastSpokenAt).inMilliseconds > _repeatCooldownMs;

        if (state == null || isRiskEscalated || isTimeExpired) {
          urgentDetections.add(detection);
          // Don't update state here, update after building payload if it's spoken
        }
      } else {
        // Fallback if no track ID
        urgentDetections.add(detection);
      }
    }

    if (urgentDetections.isEmpty) {
      return; // Nothing urgent or new to say
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

    if (payload.messageKey == _lastSpokenMessageKey && highestPriority != AudioPriority.high) {
      // Don't spam the same exact message unless it's high priority
      return;
    }

    final hasNewWarning = payload.warningKeys.difference(_lastWarningKeys).isNotEmpty;

    if (_speakMessageUseCase.isSpeaking) {
      if (highestPriority == AudioPriority.high || hasNewWarning) {
        await _speakMessageUseCase.stop();
      } else {
        return; // Skip if currently speaking and priority isn't high enough to interrupt
      }
    }

    final cooldown = (highestPriority == AudioPriority.high || hasNewWarning) ? _ttsWarningCooldownMs : _ttsCooldownMs;
    if (now.difference(_lastSmartTtsAt).inMilliseconds < cooldown) {
      return;
    }

    // Speak!
    await _speakMessageUseCase(payload.message, interrupt: true);
    
    // Update states
    _lastSmartTtsAt = now;
    _lastWarningKeys = payload.warningKeys;
    _lastSpokenMessageKey = payload.messageKey;
    
    for (final detection in urgentDetections) {
      if (detection.trackingId != null) {
        _trackedAudioStates[detection.trackingId!] = _TrackedAudioState(
          lastSpokenAt: now,
          lastRiskZone: SafeVisionPolicy.getRiskZone(detection),
        );
      }
    }
    
    // Cleanup old tracking states
    _trackedAudioStates.removeWhere((key, value) => now.difference(value.lastSpokenAt).inMilliseconds > 10000);
  }

  AudioPriority _getPriority(Detection detection, RiskZone riskZone, Map<String, SafeVisionLabelMetadata> metadata) {
    if (SafeVisionPolicy.shouldAlwaysWarn(detection)) {
      return AudioPriority.high;
    }
    if (riskZone == RiskZone.danger) {
      return AudioPriority.high;
    }
    if (riskZone == RiskZone.warning) {
      return AudioPriority.medium;
    }
    return AudioPriority.low;
  }

  void reset() {
    _lastSmartTtsAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastSpokenMessageKey = '';
    _lastWarningKeys.clear();
    _trackedAudioStates.clear();
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
