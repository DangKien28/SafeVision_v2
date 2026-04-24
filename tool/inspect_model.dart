import 'dart:io';

import 'package:tflite_flutter/tflite_flutter.dart';

Future<void> main() async {
  final bytes = await File('assets/best_int8.tflite').readAsBytes();
  final interpreter = Interpreter.fromBuffer(bytes);
  final input = interpreter.getInputTensor(0);
  stdout.writeln('inputType=${input.type} shape=${input.shape}');
  final outputs = interpreter.getOutputTensors();
  for (var i = 0; i < outputs.length; i++) {
    stdout.writeln(
      'output[$i] type=${outputs[i].type} shape=${outputs[i].shape}',
    );
  }
  interpreter.close();
}
