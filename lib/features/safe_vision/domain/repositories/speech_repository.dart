abstract class SpeechRepository {
  bool get isSpeaking;

  Future<void> configureVietnamese();
  Future<void> speak(String message, {bool interrupt = true});
  Future<void> stop();
  Future<void> dispose();
  Future<void> setVolume(double volume);
}
