import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_v2/features/safe_vision/domain/entities/detection.dart';
import 'package:safe_vision_v2/features/safe_vision/domain/entities/safe_vision_mode.dart';
import 'package:safe_vision_v2/features/safe_vision/domain/services/safe_vision_policy.dart';

void main() {
  const metadata = <String, SafeVisionLabelMetadata>{
    'xe': SafeVisionLabelMetadata(
      viLabel: 'ô tô',
      bucket: SafeVisionLabelBucket.warning,
    ),
    'cua': SafeVisionLabelMetadata(
      viLabel: 'cửa ra vào',
      bucket: SafeVisionLabelBucket.instruction,
    ),
    'ban': SafeVisionLabelMetadata(
      viLabel: 'bàn',
      bucket: SafeVisionLabelBucket.recognition,
    ),
    'lua': SafeVisionLabelMetadata(
      viLabel: 'lửa',
      bucket: SafeVisionLabelBucket.warning,
    ),
  };

  test('outdoor mode keeps urgent detections and filters small recognition', () {
    final detections = [
      const Detection(
        label: 'ban',
        score: 0.9,
        left: 0.1,
        top: 0.1,
        right: 0.3,
        bottom: 0.3,
      ),
      const Detection(
        label: 'xe',
        score: 0.8,
        left: 0.1,
        top: 0.1,
        right: 0.8,
        bottom: 0.8,
      ),
    ];

    final filtered = SafeVisionPolicy.filterDetectionsForMode(
      SafeVisionMode.outdoor,
      detections,
      metadata,
    );

    expect(filtered.map((item) => item.label), ['xe']);
  });

  test('outdoor speech only announces detections in risk zone', () {
    final payload = SafeVisionPolicy.buildSpeechPayload(
      mode: SafeVisionMode.outdoor,
      detections: const [
        Detection(
          label: 'xe',
          score: 0.9,
          left: 0.1,
          top: 0.1,
          right: 0.8,
          bottom: 0.8,
        ),
        Detection(
          label: 'cua',
          score: 0.7,
          left: 0.1,
          top: 0.1,
          right: 0.25,
          bottom: 0.25,
        ),
      ],
      metadata: metadata,
    );

    expect(payload.message, 'Cảnh báo có ô tô.');
    expect(payload.warningKeys, {'xe'});
  });

  test('indoor speech focuses on recognized object', () {
    final payload = SafeVisionPolicy.buildSpeechPayload(
      mode: SafeVisionMode.indoor,
      detections: const [
        Detection(
          label: 'ban',
          score: 0.9,
          left: 0.1,
          top: 0.1,
          right: 0.6,
          bottom: 0.8,
        ),
      ],
      metadata: metadata,
    );

    expect(payload.message, 'Tìm thấy bàn.');
    expect(payload.warningKeys, isEmpty);
  });

  test('fire is warned even when not occupying large area', () {
    final payload = SafeVisionPolicy.buildSpeechPayload(
      mode: SafeVisionMode.outdoor,
      detections: const [
        Detection(
          label: 'lua',
          score: 0.92,
          left: 0.1,
          top: 0.1,
          right: 0.2,
          bottom: 0.2,
        ),
      ],
      metadata: metadata,
    );

    expect(payload.message, 'Cảnh báo có lửa.');
    expect(payload.messageKey, 'w:lua');
  });

  test('message key stays stable when object count jitters', () {
    final single = SafeVisionPolicy.buildSpeechPayload(
      mode: SafeVisionMode.outdoor,
      detections: const [
        Detection(
          label: 'xe',
          score: 0.9,
          left: 0.1,
          top: 0.1,
          right: 0.8,
          bottom: 0.8,
        ),
      ],
      metadata: metadata,
    );
    final multiple = SafeVisionPolicy.buildSpeechPayload(
      mode: SafeVisionMode.outdoor,
      detections: const [
        Detection(
          label: 'xe',
          score: 0.9,
          left: 0.1,
          top: 0.1,
          right: 0.8,
          bottom: 0.8,
        ),
        Detection(
          label: 'xe',
          score: 0.88,
          left: 0.12,
          top: 0.12,
          right: 0.82,
          bottom: 0.82,
        ),
      ],
      metadata: metadata,
    );

    expect(single.messageKey, 'w:xe');
    expect(multiple.messageKey, 'w:xe');
  });
}
