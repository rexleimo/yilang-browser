/// 书签网格常量（与 HTML 原型一致；UI 以 390 逻辑宽度为基准）
library;

import 'dart:ui' show Offset;

class BoardMetrics {
  BoardMetrics._();

  static const double baseWidth = 390; // pad*2 + cols*cellW + (cols-1)*gapX
  static const double boardHeight = 592; // pad*2 + rows*cellH + (rows-1)*gapY
  static const double pad = 18;
  static const int cols = 4;
  static const int rows = 5;
  static const double cellW = 78;
  static const double cellH = 98;
  static const double gapX = 14;
  static const double gapY = 16;
  static const double iconSize = 62;

  /// 格位左上角坐标
  static Offset xy(int idx) {
    final col = idx % cols;
    final row = idx ~/ cols;
    return Offset(pad + col * (cellW + gapX), pad + row * (cellH + gapY));
  }

  /// 格位中心坐标
  static Offset center(int idx) => xy(idx) + const Offset(cellW / 2, 31);

  /// 由中心坐标求最近格位
  static int slotFromCenter(double cx, double cy) {
    final col =
        ((cx - pad - cellW / 2) / (cellW + gapX)).round().clamp(0, cols - 1);
    final row = ((cy - pad - 31) / (cellH + gapY)).round().clamp(0, rows - 1);
    return row * cols + col;
  }
}
