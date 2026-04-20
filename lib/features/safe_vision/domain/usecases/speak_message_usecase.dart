import '../repositories/speech_repository.dart';

class SpeakMessageUseCase {
  SpeakMessageUseCase(this._speechRepository);

  final SpeechRepository _speechRepository;

  bool get isSpeaking => _speechRepository.isSpeaking;

  Future<void> configure() => _speechRepository.configureVietnamese();

  Future<void> call(String message, {bool interrupt = true}) =>
      _speechRepository.speak(message, interrupt: interrupt);

  Future<void> stop() => _speechRepository.stop();
}
