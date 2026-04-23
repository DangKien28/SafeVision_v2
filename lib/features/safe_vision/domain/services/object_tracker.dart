import 'dart:math';

import '../entities/detection.dart';

class TrackedObject {
  TrackedObject({
    required this.id,
    required this.label,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.smoothedScore,
    this.missedFrames = 0,
    this.hitCount = 1,
  });

  final int id;
  final String label;
  double left;
  double top;
  double right;
  double bottom;
  int missedFrames;
  int hitCount;
  double smoothedScore;
}

class IoUObjectTracker {
  IoUObjectTracker({
    this.iouThreshold = 0.3,
    this.maxMissedFrames = 5,
    this.minHitCount = 3,
  });

  final double iouThreshold;
  final int maxMissedFrames;
  final int minHitCount;

  final Map<int, TrackedObject> _tracks = {};
  int _nextId = 1;

  List<Detection> process(List<Detection> detections) {
    final updatedDetections = <Detection>[];
    final matchedTrackIds = <int>{};

    for (final detection in detections) {
      TrackedObject? bestMatch;
      double bestIou = 0.0;

      for (final track in _tracks.values) {
        if (track.label != detection.label) continue;
        if (matchedTrackIds.contains(track.id)) continue;

        final iou = _calculateIoU(
          detection.left,
          detection.top,
          detection.right,
          detection.bottom,
          track.left,
          track.top,
          track.right,
          track.bottom,
        );

        if (iou > bestIou && iou >= iouThreshold) {
          bestIou = iou;
          bestMatch = track;
        }
      }

      if (bestMatch != null) {
        // Update existing track
        bestMatch.left = detection.left;
        bestMatch.top = detection.top;
        bestMatch.right = detection.right;
        bestMatch.bottom = detection.bottom;
        bestMatch.missedFrames = 0;
        bestMatch.hitCount++;
        bestMatch.smoothedScore = (bestMatch.smoothedScore * 0.5) + (detection.score * 0.5);
        matchedTrackIds.add(bestMatch.id);

        if (bestMatch.hitCount >= minHitCount) {
          updatedDetections.add(
            Detection(
              label: detection.label,
              score: bestMatch.smoothedScore,
              left: detection.left,
              top: detection.top,
              right: detection.right,
              bottom: detection.bottom,
              trackingId: bestMatch.id,
            ),
          );
        }
      } else {
        // Create new track
        final newId = _nextId++;
        final newTrack = TrackedObject(
          id: newId,
          label: detection.label,
          left: detection.left,
          top: detection.top,
          right: detection.right,
          bottom: detection.bottom,
          smoothedScore: detection.score,
        );
        _tracks[newId] = newTrack;
        matchedTrackIds.add(newId);

        if (newTrack.hitCount >= minHitCount) {
          updatedDetections.add(
            Detection(
              label: detection.label,
              score: newTrack.smoothedScore,
              left: detection.left,
              top: detection.top,
              right: detection.right,
              bottom: detection.bottom,
              trackingId: newId,
            ),
          );
        }
      }
    }

    // Handle missed tracks
    final trackIdsToRemove = <int>[];
    for (final trackId in _tracks.keys) {
      if (!matchedTrackIds.contains(trackId)) {
        final track = _tracks[trackId]!;
        track.missedFrames++;
        if (track.missedFrames > maxMissedFrames) {
          trackIdsToRemove.add(trackId);
        }
      }
    }

    for (final id in trackIdsToRemove) {
      _tracks.remove(id);
    }

    return updatedDetections;
  }

  double _calculateIoU(
    double boxA_left,
    double boxA_top,
    double boxA_right,
    double boxA_bottom,
    double boxB_left,
    double boxB_top,
    double boxB_right,
    double boxB_bottom,
  ) {
    final xA = max(boxA_left, boxB_left);
    final yA = max(boxA_top, boxB_top);
    final xB = min(boxA_right, boxB_right);
    final yB = min(boxA_bottom, boxB_bottom);

    final interArea = max(0.0, xB - xA) * max(0.0, yB - yA);

    final boxAArea = max(0.0, boxA_right - boxA_left) *
        max(0.0, boxA_bottom - boxA_top);
    final boxBArea = max(0.0, boxB_right - boxB_left) *
        max(0.0, boxB_bottom - boxB_top);

    final unionArea = boxAArea + boxBArea - interArea;

    if (unionArea <= 0) return 0.0;
    return interArea / unionArea;
  }
}
