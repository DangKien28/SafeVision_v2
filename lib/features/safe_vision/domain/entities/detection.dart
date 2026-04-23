import 'dart:math';

class Detection {
  const Detection({
    required this.label,
    required this.score,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.trackingId,
  });

  final String label;
  final double score;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final int? trackingId;

  double get width => max(0, right - left);
  double get height => max(0, bottom - top);
  double get areaRatio => width * height;
  double get estimatedDistance => 1 / max(height, 0.0001);
  double get centerX => left + width / 2;

  String get labelVi {
    switch (label) {
      case 'ban':
        return 'bàn';
      case 'cau_thang':
        return 'cầu thang';
      case 'cay':
        return 'cây';
      case 'ghe':
        return 'ghế';
      case 'nguoi_di_bo':
        return 'người đi bộ';
      case 'xe':
        return 'xe';
      case 'cua':
        return 'cửa';
      case 'ho':
        return 'hố';
      case 'balo':
        return 'ba lô';
      case 'vi':
        return 'ví';
      case 'lua':
        return 'lửa';
      case 'laptop':
        return 'laptop';
      case 'dien_thoai':
        return 'điện thoại';
      default:
        return label.replaceAll('_', ' ');
    }
  }
}
