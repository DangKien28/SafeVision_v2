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
    this.iouThreshold = 0.15,
    this.maxMissedFrames = 1,
    this.minHitCount = 1,
    this.positionSmoothing = 0.5,
    this.scoreSmoothing = 0.5,
  });

  final double iouThreshold;
  final int maxMissedFrames;
  final int minHitCount;
  final double positionSmoothing;
  final double scoreSmoothing;

  final Map<int, TrackedObject> _tracks = {};
  int _nextId = 1;

  /// Reset all tracks (remove all tracked objects)
  void reset() {
    _tracks.clear();
  }

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
        bestMatch.left = _lerp(bestMatch.left, detection.left, positionSmoothing);
        bestMatch.top = _lerp(bestMatch.top, detection.top, positionSmoothing);
        bestMatch.right = _lerp(
          bestMatch.right,
          detection.right,
          positionSmoothing,
        );
        bestMatch.bottom = _lerp(
          bestMatch.bottom,
          detection.bottom,
          positionSmoothing,
        );
        bestMatch.missedFrames = 0;
        bestMatch.hitCount++;
        bestMatch.smoothedScore = _lerp(
          bestMatch.smoothedScore,
          detection.score,
          scoreSmoothing,
        );
        matchedTrackIds.add(bestMatch.id);

        if (bestMatch.hitCount >= minHitCount) {
          updatedDetections.add(
            Detection(
              label: bestMatch.label,
              score: bestMatch.smoothedScore,
              left: bestMatch.left,
              top: bestMatch.top,
              right: bestMatch.right,
              bottom: bestMatch.bottom,
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
              label: newTrack.label,
              score: newTrack.smoothedScore,
              left: newTrack.left,
              top: newTrack.top,
              right: newTrack.right,
              bottom: newTrack.bottom,
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
    double boxALeft,
    double boxATop,
    double boxARight,
    double boxABottom,
    double boxBLeft,
    double boxBTop,
    double boxBRight,
    double boxBBottom,
  ) {
    final xA = max(boxALeft, boxBLeft);
    final yA = max(boxATop, boxBTop);
    final xB = min(boxARight, boxBRight);
    final yB = min(boxABottom, boxBBottom);

    final interArea = max(0.0, xB - xA) * max(0.0, yB - yA);

    final boxAArea = max(0.0, boxARight - boxALeft) *
        max(0.0, boxABottom - boxATop);
    final boxBArea = max(0.0, boxBRight - boxBLeft) *
        max(0.0, boxBBottom - boxBTop);

    final unionArea = boxAArea + boxBArea - interArea;

    if (unionArea <= 0) return 0.0;
    return interArea / unionArea;
  }

  double _lerp(double current, double target, double t) {
    return current + (target - current) * t;
  }
}
