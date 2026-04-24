import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsDataSource {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  Future<void> configureVietnamese() async {
    _tts.setStartHandler(() {
      _isSpeaking = true;
    });
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });
    _tts.setCancelHandler(() {
      _isSpeaking = false;
    });
    _tts.setErrorHandler((error) {
      debugPrint('TTS Error: $error');
      _isSpeaking = false;
    });

    try {
      await _tts.setLanguage('vi-VN');
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(false);
    } catch (e) {
      debugPrint('TTS config error: $e');
    }
  }

  Future<void> speak(String message, {bool interrupt = true}) async {
    if (message.isEmpty) return;
    try {
      if (interrupt && _isSpeaking) {
        await _tts.stop();
      }
      _isSpeaking = true;
      await _tts.speak(message);
    } catch (e) {
      debugPrint('TTS speak error: $e');
      _isSpeaking = false;
    }
  }

  Future<void> setVolume(double volume) async {
    await _tts.setVolume(volume.clamp(0.0, 1.0));
  }

  Future<void> stop() async {
    _isSpeaking = false;
    await _tts.stop();
  }

  Future<void> dispose() async {
    _isSpeaking = false;
    await _tts.stop();
  }
}
