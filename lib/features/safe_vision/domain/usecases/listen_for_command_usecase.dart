import '../repositories/speech_repository.dart';

class ListenForCommandUseCase {
  ListenForCommandUseCase(this._repository);

  final SpeechRepository _repository;

  Future<void> call({
    required Function(String) onResult,
    required String prompt,
  }) async {
    // 1. Speak the prompt
    await _repository.speak(prompt, interrupt: true);
    
    // 2. Wait for TTS to finish speaking (approximate or use completion handler if possible)
    // For simplicity, we'll wait a bit or assume the repository handles it.
    // Ideally we want to listen ONLY after the prompt is done.
    await Future.delayed(const Duration(seconds: 3)); 

    // 3. Initialize STT if not already
    await _repository.initializeStt();

    // 4. Start listening
    await _repository.listen(onResult: onResult);
  }

  Future<void> stop() => _repository.stopListening();
}
