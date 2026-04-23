import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_v2/features/safe_vision/domain/entities/safe_vision_mode.dart';
import 'package:safe_vision_v2/features/safe_vision/presentation/widgets/bottom_action_bar.dart';

void main() {
  testWidgets('BottomActionBar renders all modes and reports selection', (
    tester,
  ) async {
    SafeVisionMode? selectedMode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BottomActionBar(
            mode: SafeVisionMode.outdoor,
            onModeChanged: (mode) => selectedMode = mode,
          ),
        ),
      ),
    );

    expect(find.text('Ngoai troi'), findsOneWidget);
    expect(find.text('Trong nha'), findsOneWidget);
    expect(find.text('Huong dan'), findsOneWidget);

    await tester.tap(find.text('Trong nha'));
    await tester.pump();

    expect(selectedMode, SafeVisionMode.indoor);
  });
}
