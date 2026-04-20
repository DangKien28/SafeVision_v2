import '../../domain/repositories/speech_repository.dart';
import '../datasources/tts_data_source.dart';

class SpeechRepositoryImpl implements SpeechRepository {
  SpeechRepositoryImpl({required TtsDataSource ttsDataSource})
    : _ttsDataSource = ttsDataSource;

  final TtsDataSource _ttsDataSource;

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
}
