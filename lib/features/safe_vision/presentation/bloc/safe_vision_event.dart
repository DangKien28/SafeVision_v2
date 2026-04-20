import 'package:camera/camera.dart';

import '../../domain/entities/safe_vision_mode.dart';

abstract class SafeVisionEvent {
  const SafeVisionEvent();
}

class SafeVisionStarted extends SafeVisionEvent {
  const SafeVisionStarted();
}

class CameraFrameReceived extends SafeVisionEvent {
  const CameraFrameReceived(this.image);

  final CameraImage image;
}

class SafeVisionModeChanged extends SafeVisionEvent {
  const SafeVisionModeChanged(this.mode);

  final SafeVisionMode mode;
}

class SafeVisionModeSwiped extends SafeVisionEvent {
  const SafeVisionModeSwiped({required this.toNext});

  final bool toNext;
}

class CameraLensToggled extends SafeVisionEvent {
  const CameraLensToggled();
}
