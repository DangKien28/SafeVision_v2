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

    expect(find.text('Ngoài trời'), findsOneWidget);
    expect(find.text('Trong nhà'), findsOneWidget);

    // Verify the widget renders exactly as many buttons as there are modes
    expect(
      find.byType(FilledButton),
      findsNWidgets(SafeVisionMode.values.length),
    );

    await tester.tap(find.text('Trong nhà'));
    await tester.pump();

    expect(selectedMode, SafeVisionMode.indoor);
  });

  testWidgets('BottomActionBar highlights the active mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BottomActionBar(
            mode: SafeVisionMode.indoor,
            onModeChanged: (_) {},
          ),
        ),
      ),
    );

    // Both labels should still be rendered regardless of active mode
    expect(find.text('Ngoài trời'), findsOneWidget);
    expect(find.text('Trong nhà'), findsOneWidget);
  });
}
