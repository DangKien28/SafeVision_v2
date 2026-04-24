import '../../domain/repositories/speech_repository.dart';
import '../datasources/stt_data_source.dart';
import '../datasources/tts_data_source.dart';

class SpeechRepositoryImpl implements SpeechRepository {
  SpeechRepositoryImpl({
    required TtsDataSource ttsDataSource,
    required SttDataSource sttDataSource,
  }) : _ttsDataSource = ttsDataSource,
       _sttDataSource = sttDataSource;

  final TtsDataSource _ttsDataSource;
  final SttDataSource _sttDataSource;

  @override
  bool get isSpeaking => _ttsDataSource.isSpeaking;

  @override
  Future<void> configureVietnamese() => _ttsDataSource.configureVietnamese();

  @override
  Future<void> speak(String message, {bool interrupt = true}) =>
      _ttsDataSource.speak(message, interrupt: interrupt);

  @override
  Future<void> stop() => _ttsDataSource.stop();

  @override
  Future<void> dispose() => _ttsDataSource.dispose();

  @override
  Future<void> setVolume(double volume) => _ttsDataSource.setVolume(volume);

  @override
  bool get isListening => _sttDataSource.isListening;

  @override
  Future<bool> initializeStt() => _sttDataSource.initialize();

  @override
  Future<void> listen({required Function(String) onResult}) =>
      _sttDataSource.listen(onResult: onResult);

  @override
  Future<void> stopListening() => _sttDataSource.stop();
}
