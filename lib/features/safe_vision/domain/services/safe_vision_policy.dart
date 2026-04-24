import '../entities/detection.dart';
import '../entities/safe_vision_mode.dart';

enum SafeVisionLabelBucket { warning, instruction, recognition }

enum PriorityLevel { p0, p1, p2, p3 }

enum RiskZone { safe, warning, danger }

class SafeVisionLabelMetadata {
  const SafeVisionLabelMetadata({
    required this.viLabel,
    required this.bucket,
    this.riskScale = 1.0,
  });

  final String viLabel;
  final SafeVisionLabelBucket bucket;
  final double riskScale;
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
  static const Set<String> _alwaysWarnLabels = {
    'lua',
    'fire',
    'ho',
    'hole',
    'cau_thang',
    'stairs',
  };

  // average width of objects in meters
  static const Map<String, double> _objectRealWidths = {
    'car': 1.8,
    'xe': 1.8,
    'person': 0.5,
    'nguoi_di_bo': 0.5,
    'door': 0.9,
    'cua': 0.9,
    'ho': 1.0,
    'hole': 1.0,
    'lua': 0.5,
    'fire': 0.5,
    'thung_rac': 0.4,
    'den_giao_thong': 0.3,
  };

  // Focal length in pixels (typical for 1080p mobile camera)
  // Formula: F = (P * D) / W. If D=1m, W=0.5m, P=600px -> F=1200
  static const double focalLength = 1000.0;

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

          if (mode == SafeVisionMode.indoor || mode == SafeVisionMode.tutorial) {
            return true;
          }

          return bucket != SafeVisionLabelBucket.recognition ||
              isInRiskZone(detection, metadata) ||
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
      case SafeVisionMode.tutorial:
        return 'Chế độ hướng dẫn sử dụng';
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
              return isInRiskZone(detection, metadata) || shouldAlwaysWarn(detection);
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
    if (detections.isEmpty || mode == SafeVisionMode.tutorial) {
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
      if (!isInRiskZone(detection, metadata) && !shouldAlwaysWarn(detection)) {
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

    if (mode == SafeVisionMode.indoor || mode == SafeVisionMode.tutorial) {
      final items = <_BucketItem>[];
      var hasDanger = false;

      grouped.forEach((rawLabel, count) {
        final detection = firstByLabel[rawLabel]!;
        if (shouldAlwaysWarn(detection)) {
          hasDanger = true;
        }
        items.add(_BucketItem(
          rawLabel: rawLabel,
          viLabel: localizedLabel(detection, metadata),
          count: count,
        ));
      });

      items.sort((a, b) {
        final ap = shouldAlwaysWarn(firstByLabel[a.rawLabel]!) ? 1 : 0;
        final bp = shouldAlwaysWarn(firstByLabel[b.rawLabel]!) ? 1 : 0;
        if (ap != bp) return bp.compareTo(ap);
        return b.count.compareTo(a.count);
      });

      final prefix = hasDanger ? 'Nguy hiểm! ' : 'Tìm thấy ';
      return SafeVisionSpeechPayload(
        message: '$prefix${_joinBucketPhrases(items)}.',
        warningKeys: hasDanger ? items.where((e) => shouldAlwaysWarn(firstByLabel[e.rawLabel]!)).map((e) => e.rawLabel).toSet() : <String>{},
        messageKey: '${mode.name}:${items.map((e) => '${e.count}:${e.rawLabel}').join(',')}',
      );
    }

    final dangerItems = <_BucketItem>[];
    final warningItems = <_BucketItem>[];
    final instructionItems = <_BucketItem>[];
    final recognitionItems = <_BucketItem>[];

    grouped.forEach((rawLabel, count) {
      final detection = firstByLabel[rawLabel]!;
      final distance = estimateDistance(detection);
      final item = _BucketItem(
        rawLabel: rawLabel,
        viLabel: localizedLabel(detection, metadata),
        count: count,
        closestDistance: distance,
      );
      
      if (shouldAlwaysWarn(detection)) {
        dangerItems.add(item);
      } else {
        final bucket = metadata[rawLabel]?.bucket ?? SafeVisionLabelBucket.recognition;
        if (bucket == SafeVisionLabelBucket.warning) {
          warningItems.add(item);
        } else if (bucket == SafeVisionLabelBucket.instruction) {
          instructionItems.add(item);
        } else {
          recognitionItems.add(item);
        }
      }
    });

    dangerItems.sort((a, b) => a.closestDistance.compareTo(b.closestDistance));
    warningItems.sort((a, b) => a.closestDistance.compareTo(b.closestDistance));
    instructionItems.sort((a, b) => a.closestDistance.compareTo(b.closestDistance));
    recognitionItems.sort((a, b) => a.closestDistance.compareTo(b.closestDistance));

    final chunks = <String>[];
    if (dangerItems.isNotEmpty) {
      chunks.add('Cảnh báo có ${_joinBucketPhrases(dangerItems, includeDistance: true)}.');
    }
    if (warningItems.isNotEmpty) {
      chunks.add('Cảnh báo có ${_joinBucketPhrases(warningItems, includeDistance: true)}.');
    }
    if (instructionItems.isNotEmpty) {
      chunks.add('Chú ý: ${_joinBucketPhrases(instructionItems)}.');
    }
    if (recognitionItems.isNotEmpty && mode == SafeVisionMode.outdoor) {
      chunks.add('Phía trước có ${_joinBucketPhrases(recognitionItems)}.');
    }

    final messageKeyParts = <String>[
      ...dangerItems.map((item) => 'd:${item.rawLabel}'),
      ...warningItems.map((item) => 'w:${item.rawLabel}'),
      ...instructionItems.map((item) => 'i:${item.rawLabel}'),
      ...recognitionItems.map((item) => 'r:${item.rawLabel}'),
    ];

    return SafeVisionSpeechPayload(
      message: chunks.join(' ').trim(),
      warningKeys: dangerItems.map((item) => item.rawLabel).toSet().union(warningItems.map((item) => item.rawLabel).toSet()),
      messageKey: messageKeyParts.join('|'),
    );
  }

  static RiskZone getRiskZone(
    Detection detection,
    Map<String, SafeVisionLabelMetadata> metadata,
  ) {
    if (shouldAlwaysWarn(detection)) {
      return RiskZone.danger;
    }

    final distance = estimateDistance(detection);
    if (distance < 1.5) {
      return RiskZone.danger;
    }
    if (distance < 3.0 || detection.bottom >= 0.7) {
      return RiskZone.warning;
    }
    return RiskZone.safe;
  }

  static double estimateDistance(Detection detection) {
    final label = _normalizeLabel(detection.label);
    final realWidth = _objectRealWidths[label] ?? 0.5; // default to 0.5m
    
    // detection.width is area ratio or pixel? 
    // Assuming detection.width is fraction of frame width [0, 1]
    // We need pixel width. Let's assume frame width is 1000 pixels for simplicity
    // or use the fraction directly if focalLength is adjusted.
    // D = (W * F) / P_pixels. If P_pixels = width_ratio * FrameWidth
    // D = (W * F) / (width_ratio * FrameWidth)
    // D = (W * (F/FrameWidth)) / width_ratio
    // We'll use width_ratio and assume F_ratio = F/FrameWidth = 1.0 approx
    
    if (detection.width <= 0) return 100.0;
    return (realWidth * 1.0) / detection.width; 
  }

  static PriorityLevel getPriorityLevel(
    Detection detection,
    RiskZone riskZone,
    Map<String, SafeVisionLabelMetadata> metadata,
  ) {
    final label = _normalizeLabel(detection.label);
    
    // P0: Emergency (Rushing vehicles, holes nearby, or dangerous items in danger zone)
    if (detection.isRushing && riskZone != RiskZone.safe) {
      return PriorityLevel.p0;
    }
    if (shouldAlwaysWarn(detection) && riskZone == RiskZone.danger) {
      return PriorityLevel.p0;
    }
    if ((label == 'car' || label == 'xe') && riskZone == RiskZone.danger) {
      return PriorityLevel.p0;
    }

    // P1: High Priority (Static obstacles nearby)
    if (riskZone == RiskZone.danger) {
      return PriorityLevel.p1;
    }

    // P2: Medium (Instructions, crosswalks, etc.)
    final bucket = metadata[label]?.bucket ?? SafeVisionLabelBucket.recognition;
    if (bucket == SafeVisionLabelBucket.warning || bucket == SafeVisionLabelBucket.instruction) {
      return PriorityLevel.p2;
    }

    // P3: Low (Distant items)
    return PriorityLevel.p3;
  }

  static bool isInRiskZone(
    Detection detection,
    Map<String, SafeVisionLabelMetadata> metadata,
  ) {
    return getRiskZone(detection, metadata) != RiskZone.safe;
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

  static String _joinBucketPhrases(List<_BucketItem> items, {bool includeDistance = false}) {
    final phrases = items.map((item) {
      if (includeDistance && item.closestDistance < 10.0) {
        final distStr = item.closestDistance.toStringAsFixed(1).replaceAll('.', ',');
        return '${item.phrase}, $distStr mét';
      }
      return item.phrase;
    }).toList(growable: false);

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
    this.closestDistance = 0.0,
  });

  final String rawLabel;
  final String viLabel;
  final int count;
  final double closestDistance;

  String get phrase => count > 1 ? '$count $viLabel' : viLabel;
}
