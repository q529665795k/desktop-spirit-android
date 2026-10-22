import 'package:flutter/foundation.dart';

@immutable
class OverlayPosition {
  final double x;
  final double y;

  const OverlayPosition(this.x, this.y);

  factory OverlayPosition.fromMap(Map<Object?, Object?>? map) =>
      OverlayPosition(map?['x'] as double? ?? 0, map?['y'] as double? ?? 0);

  Map<String, dynamic> toMap() =>
      <String, dynamic>{'x': x.toInt(), 'y': y.toInt()};

  @override
  String toString() {
    return 'OverlayPosition{x=$x, y=$y}';
  }
}

/// v0.8.3 漫游:屏幕物理尺寸(dp),由悬浮窗服务返回
@immutable
class OverlayScreenSize {
  final double width;
  final double height;

  const OverlayScreenSize(this.width, this.height);

  @override
  String toString() {
    return 'OverlayScreenSize{w=$width, h=$height}';
  }
}
