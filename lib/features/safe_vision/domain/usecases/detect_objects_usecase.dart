import 'package:camera/camera.dart';

import '../entities/detection.dart';
import '../repositories/vision_repository.dart';

class DetectObjectsUseCase {
  DetectObjectsUseCase(this._visionRepository);

  final VisionRepository _visionRepository;

  Future<List<Detection>> call(CameraImage image, {double confidenceThreshold = 0.40}) {
    return _visionRepository.detect(image, confidenceThreshold: confidenceThreshold);
  }
}
