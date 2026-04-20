import 'package:camera/camera.dart';

import '../repositories/vision_repository.dart';

class InitializeVisionUseCase {
  InitializeVisionUseCase(this._visionRepository);

  final VisionRepository _visionRepository;

  Future<CameraController> call() {
    return _visionRepository.initializeCamera();
  }
}
