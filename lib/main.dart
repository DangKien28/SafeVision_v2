import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera_android/camera_android.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (defaultTargetPlatform == TargetPlatform.android) {
    CameraPlatform.instance = AndroidCamera();
  }

  debugPrint('SafeVision: main started');
  runApp(const SafeVisionApp());
}
