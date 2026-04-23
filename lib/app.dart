import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/safe_vision/data/datasources/camera_data_source.dart';
import 'features/safe_vision/data/datasources/tflite_detector_data_source.dart';
import 'features/safe_vision/data/datasources/tts_data_source.dart';
import 'features/safe_vision/data/repositories/speech_repository_impl.dart';
import 'features/safe_vision/data/repositories/vision_repository_impl.dart';
import 'features/safe_vision/domain/usecases/detect_objects_usecase.dart';
import 'features/safe_vision/domain/usecases/initialize_vision_usecase.dart';
import 'features/safe_vision/domain/usecases/speak_message_usecase.dart';
import 'features/safe_vision/presentation/bloc/safe_vision_bloc.dart';
import 'features/safe_vision/presentation/pages/safe_vision_page.dart';

class SafeVisionApp extends StatefulWidget {
  const SafeVisionApp({super.key});

  @override
  State<SafeVisionApp> createState() => _SafeVisionAppState();
}

class _SafeVisionAppState extends State<SafeVisionApp> {
  late final SafeVisionBloc _bloc;

  @override
  void initState() {
    super.initState();

    final cameraDataSource = CameraDataSource();
    final detectorDataSource = TfliteDetectorDataSource(
      modelAsset: 'assets/best_int8.tflite',
      labelsAsset: 'assets/labels.txt',
    );
    final ttsDataSource = TtsDataSource();

    final visionRepository = VisionRepositoryImpl(
      cameraDataSource: cameraDataSource,
      detectorDataSource: detectorDataSource,
    );
    final speechRepository = SpeechRepositoryImpl(ttsDataSource: ttsDataSource);

    _bloc = SafeVisionBloc(
      initializeVisionUseCase: InitializeVisionUseCase(visionRepository),
      detectObjectsUseCase: DetectObjectsUseCase(visionRepository),
      speakMessageUseCase: SpeakMessageUseCase(speechRepository),
      visionRepository: visionRepository,
      speechRepository: speechRepository,
    );
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFFFE400),
        secondary: Color(0xFF00E5FF),
        surface: Color(0xFF000000),
      ),
      scaffoldBackgroundColor: const Color(0xFF000000),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: Color(0xFFFFE400),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
        bodyLarge: TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 18,
          height: 1.35,
        ),
      ),
    );

    return BlocProvider.value(
      value: _bloc,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Safe Vision',
        theme: theme,
        home: const SafeVisionPage(),
      ),
    );
  }
}
