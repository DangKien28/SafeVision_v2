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

    if (payload.messageKey == _lastSpokenMessageKey &&
        highestPriority != AudioPriority.high) {
      return;
    }

    final hasNewWarning =
        payload.warningKeys.difference(_lastWarningKeys).isNotEmpty;

    if (_speakMessageUseCase.isSpeaking) {
      if (highestPriority == AudioPriority.high || hasNewWarning) {
        await _speakMessageUseCase.stop();
      } else {
        return;
      }
    }

    final cooldown = (highestPriority == AudioPriority.high || hasNewWarning)
        ? _ttsWarningCooldownMs
        : _ttsCooldownMs;
    if (now.difference(_lastSmartTtsAt).inMilliseconds < cooldown) {
      return;
    }

    await _speakMessageUseCase(payload.message, interrupt: true);

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
  }

  AudioPriority _getPriority(
    Detection detection,
    RiskZone riskZone,
    Map<String, SafeVisionLabelMetadata> metadata,
  ) {
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