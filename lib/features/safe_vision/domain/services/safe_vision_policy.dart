import '../entities/detection.dart';
import '../entities/safe_vision_mode.dart';

enum SafeVisionLabelBucket { warning, instruction, recognition }

enum RiskZone { safe, warning, danger }

class SafeVisionLabelMetadata {
  const SafeVisionLabelMetadata({required this.viLabel, required this.bucket});

  final String viLabel;
  final SafeVisionLabelBucket bucket;
}

class SafeVisionSpeechPayload {
  const SafeVisionSpeechPayload({
    required this.message,
    required this.warningKeys,
    required this.messageKey,
  });

  final String message;
  final Set<String> warningKeys;
  final String messageKey;
}

class SafeVisionPolicy {
  // Minimum bounding-box area (as fraction of frame) for a detection to enter
  // the risk zone. Filters out tiny false-positive detections from distant objects.
  static const double riskZoneAreaThreshold = 0.012;
  static const double riskZoneBottomThreshold = 0.70;
  static const Set<String> _alwaysWarnLabels = {'lua', 'fire'};

  static List<Detection> filterDetectionsForMode(
    SafeVisionMode mode,
    List<Detection> detections,
    Map<String, SafeVisionLabelMetadata> metadata,
  ) {
    final filtered = detections
        .where((detection) {
          final bucket =
              metadata[_normalizeLabel(detection.label)]?.bucket ??
              SafeVisionLabelBucket.recognition;

          if (mode == SafeVisionMode.indoor) {
            return true;
          }

          return bucket != SafeVisionLabelBucket.recognition ||
              isInRiskZone(detection) ||
              shouldAlwaysWarn(detection);
        })
        .toList(growable: false);

    filtered.sort((a, b) {
      final dangerCompare = _dangerPriority(
        b,
        metadata,
      ).compareTo(_dangerPriority(a, metadata));
      if (dangerCompare != 0) {
        return dangerCompare;
      }

      final areaCompare = b.areaRatio.compareTo(a.areaRatio);
      if (areaCompare != 0) {
        return areaCompare;
      }
      return b.score.compareTo(a.score);
    });
    return filtered;
  }

  static String buildStatusText(
    SafeVisionMode mode,
    List<Detection> detections,
    Map<String, SafeVisionLabelMetadata> metadata,
  ) {
    switch (mode) {
      case SafeVisionMode.indoor:
        if (detections.isEmpty) {
          return 'Quét để tìm vật dụng xung quanh bạn';
        }
        final top = detections.first;
        final percent = (top.score * 100).toStringAsFixed(0);
        return 'Tìm thấy: ${localizedLabel(top, metadata)} ($percent%)';
      case SafeVisionMode.outdoor:
        final urgentDetections = detections
            .where((detection) {
              return isInRiskZone(detection) || shouldAlwaysWarn(detection);
            })
            .toList(growable: false);
        if (urgentDetections.isEmpty) {
          return detections.isEmpty
              ? 'Không có vật cản nguy hiểm'
              : 'Đã nhận diện vật thể, chưa có vật cản vào vùng nguy hiểm';
        }
        final top = urgentDetections.first;
        final percent = (top.score * 100).toStringAsFixed(0);
        return 'Cảnh báo: ${localizedLabel(top, metadata)} ($percent%)';
    }
  }

  static SafeVisionSpeechPayload buildSpeechPayload({
    required SafeVisionMode mode,
    required List<Detection> detections,
    required Map<String, SafeVisionLabelMetadata> metadata,
  }) {
    if (detections.isEmpty) {
      return const SafeVisionSpeechPayload(
        message: '',
        warningKeys: <String>{},
        messageKey: '',
      );
    }

    if (mode == SafeVisionMode.indoor) {
      final grouped = <String, int>{};
      final firstByLabel = <String, Detection>{};

      for (final detection in detections) {
        final key = _normalizeLabel(detection.label);
        grouped.update(key, (value) => value + 1, ifAbsent: () => 1);
        firstByLabel.putIfAbsent(key, () => detection);
      }

      final items = <_BucketItem>[];
      grouped.forEach((rawLabel, count) {
        items.add(
          _BucketItem(
            rawLabel: rawLabel,
            viLabel: localizedLabel(firstByLabel[rawLabel]!, metadata),
            count: count,
          ),
        );
      });
      items.sort((a, b) => b.count.compareTo(a.count));

      return SafeVisionSpeechPayload(
        message: 'Tìm thấy ${_joinBucketPhrases(items)}.',
        warningKeys: <String>{},
        messageKey:
            'indoor:${items.map((e) => '${e.count}:${e.rawLabel}').join(',')}',
      );
    }

    final grouped = <String, int>{};
    final firstByLabel = <String, Detection>{};

    for (final detection in detections) {
      if (!isInRiskZone(detection) && !shouldAlwaysWarn(detection)) {
        continue;
      }
      final key = _normalizeLabel(detection.label);
      grouped.update(key, (value) => value + 1, ifAbsent: () => 1);
      firstByLabel.putIfAbsent(key, () => detection);
    }

    if (grouped.isEmpty) {
      return const SafeVisionSpeechPayload(
        message: '',
        warningKeys: <String>{},
        messageKey: '',
      );
    }

    final warningItems = <_BucketItem>[];
    final instructionItems = <_BucketItem>[];
    final recognitionItems = <_BucketItem>[];

    grouped.forEach((rawLabel, count) {
      final item = _BucketItem(
        rawLabel: rawLabel,
        viLabel: localizedLabel(firstByLabel[rawLabel]!, metadata),
        count: count,
      );
      final bucket =
          metadata[rawLabel]?.bucket ?? SafeVisionLabelBucket.recognition;
      if (bucket == SafeVisionLabelBucket.warning) {
        warningItems.add(item);
      } else if (bucket == SafeVisionLabelBucket.instruction) {
        instructionItems.add(item);
      } else {
        recognitionItems.add(item);
      }
    });

    warningItems.sort((a, b) => b.count.compareTo(a.count));
    instructionItems.sort((a, b) => b.count.compareTo(a.count));
    recognitionItems.sort((a, b) => b.count.compareTo(a.count));

    final chunks = <String>[];
    if (warningItems.isNotEmpty) {
      chunks.add('Cảnh báo có ${_joinBucketPhrases(warningItems)}.');
    }
    if (instructionItems.isNotEmpty) {
      chunks.add('Chú ý: ${_joinBucketPhrases(instructionItems)}.');
    }
    if (recognitionItems.isNotEmpty) {
      chunks.add('Phía trước có ${_joinBucketPhrases(recognitionItems)}.');
    }

    final messageKeyParts = <String>[
      ...warningItems.map((item) => 'w:${item.rawLabel}'),
      ...instructionItems.map((item) => 'i:${item.rawLabel}'),
      ...recognitionItems.map((item) => 'r:${item.rawLabel}'),
    ];

    return SafeVisionSpeechPayload(
      message: chunks.join(' ').trim(),
      warningKeys: warningItems.map((item) => item.rawLabel).toSet(),
      messageKey: messageKeyParts.join('|'),
    );
  }

  static RiskZone getRiskZone(Detection detection) {
    if (shouldAlwaysWarn(detection)) {
      return RiskZone.danger;
    }

    // FIX: apply area threshold — ignore detections too small to be in-scene
    if (detection.areaRatio < riskZoneAreaThreshold) {
      return RiskZone.safe;
    }

    if (detection.estimatedDistance < 2.5 || detection.bottom >= 0.8) {
      return RiskZone.danger;
    }
    if (detection.estimatedDistance < 4.0 || detection.bottom >= 0.6) {
      return RiskZone.warning;
    }
    return RiskZone.safe;
  }

  static bool isInRiskZone(Detection detection) {
    return getRiskZone(detection) != RiskZone.safe;
  }

  static bool shouldAlwaysWarn(Detection detection) {
    return _alwaysWarnLabels.contains(_normalizeLabel(detection.label));
  }

  static String localizedLabel(
    Detection detection,
    Map<String, SafeVisionLabelMetadata> metadata,
  ) {
    return metadata[_normalizeLabel(detection.label)]?.viLabel ??
        detection.labelVi;
  }

  static String _normalizeLabel(String label) {
    return label.toLowerCase().trim();
  }

  static int _dangerPriority(
    Detection detection,
    Map<String, SafeVisionLabelMetadata> metadata,
  ) {
    if (shouldAlwaysWarn(detection)) {
      return 2;
    }
    final bucket =
        metadata[_normalizeLabel(detection.label)]?.bucket ??
        SafeVisionLabelBucket.recognition;
    if (bucket == SafeVisionLabelBucket.warning) {
      return 1;
    }
    return 0;
  }

  static String _joinBucketPhrases(List<_BucketItem> items) {
    final phrases = items.map((item) => item.phrase).toList(growable: false);
    if (phrases.isEmpty) {
      return '';
    }
    if (phrases.length == 1) {
      return phrases.first;
    }
    if (phrases.length == 2) {
      return '${phrases[0]} và ${phrases[1]}';
    }
    final head = phrases.sublist(0, phrases.length - 1).join(', ');
    return '$head và ${phrases.last}';
  }
}

class _BucketItem {
  const _BucketItem({
    required this.rawLabel,
    required this.viLabel,
    required this.count,
  });

  final String rawLabel;
  final String viLabel;
  final int count;

  String get phrase => count > 1 ? '$count $viLabel' : viLabel;
}
