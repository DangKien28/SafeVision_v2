import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SttDataSource {
  final SpeechToText _stt = SpeechToText();
  bool _isListening = false;

  bool get isListening => _isListening;

  Future<bool> initialize() async {
    try {
      final available = await _stt.initialize(
        onError: (error) {
          debugPrint('STT Error: $error');
          _isListening = false;
        },
        onStatus: (status) {
          debugPrint('STT Status: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
          }
        },
      );
      return available;
    } catch (e) {
      debugPrint('STT Initialize Error: $e');
      return false;
    }
  }

  Future<void> listen({
    required Function(String) onResult,
    Duration listenFor = const Duration(seconds: 5),
  }) async {
    if (_isListening) return;
    
    _isListening = true;
    try {
      await _stt.listen(
        onResult: (result) {
          if (result.finalResult) {
            _isListening = false;
            onResult(result.recognizedWords);
          }
        },
        listenFor: listenFor,
        localeId: 'vi_VN',
        cancelOnError: true,
        partialResults: false,
      );
    } catch (e) {
      debugPrint('STT Listen Error: $e');
      _isListening = false;
    }
  }

  Future<void> stop() async {
    await _stt.stop();
    _isListening = false;
  }

  Future<void> cancel() async {
    await _stt.cancel();
    _isListening = false;
  }
}
