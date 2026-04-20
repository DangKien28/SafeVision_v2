import 'package:camera/camera.dart';

class CameraDataSource {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  CameraLensDirection _currentLensDirection = CameraLensDirection.back;

  CameraController? get controller => _controller;
  CameraLensDirection get currentLensDirection => _currentLensDirection;

  Future<CameraController> initializeCamera({
    CameraLensDirection lensDirection = CameraLensDirection.back,
  }) async {
    await _loadCameras();
    await _disposeControllerOnly();

    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == lensDirection,
      orElse: () => _cameras.first,
    );
    _currentLensDirection = camera.lensDirection;

    final controller = CameraController(
      camera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await controller.initialize();
    _controller = controller;
    return controller;
  }

  Future<CameraController> switchCamera() async {
    await _loadCameras();
    final nextLens = _currentLensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    return initializeCamera(lensDirection: nextLens);
  }

  Future<void> startImageStream(
    void Function(CameraImage image) onImage,
  ) async {
    final controller = _controller;
    if (controller == null || controller.value.isStreamingImages) {
      return;
    }
    await controller.startImageStream(onImage);
  }

  Future<void> _loadCameras() async {
    if (_cameras.isNotEmpty) {
      return;
    }
    _cameras = await availableCameras();
  }

  Future<void> _disposeControllerOnly() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await controller.dispose();
    _controller = null;
  }

  Future<void> dispose() async {
    await _disposeControllerOnly();
  }
}
