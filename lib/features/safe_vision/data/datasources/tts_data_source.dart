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
    _tts.setErrorHandler((_) {
      _isSpeaking = false;
    });

    await _tts.setLanguage('vi-VN');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> speak(String message, {bool interrupt = true}) async {
    if (interrupt) {
      await _tts.stop();
    }
    _isSpeaking = true;
    await _tts.speak(message);
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
