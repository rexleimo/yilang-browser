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
  static const double cellH = 96;
  static const double gapX = 14;
  static const double gapY = 14;
  static const double iconSize = 56;

  /// 图标中心相对格位左上角的偏移（iconSize/2，供拖拽命中计算）。
  static double get iconCenterDy => iconSize / 2;

  /// 格位左上角坐标
  static Offset xy(int idx) {
    final col = idx % cols;
    final row = idx ~/ cols;
    return Offset(pad + col * (cellW + gapX), pad + row * (cellH + gapY));
  }

  /// 格位中心坐标
  static Offset center(int idx) =>
      xy(idx) + Offset(cellW / 2, BoardMetrics.iconCenterDy);

  /// 由中心坐标求最近格位
  static int slotFromCenter(double cx, double cy) {
    final col =
        ((cx - pad - cellW / 2) / (cellW + gapX)).round().clamp(0, cols - 1);
    final row = ((cy - pad - iconCenterDy) / (cellH + gapY))
        .round()
        .clamp(0, rows - 1);
    return row * cols + col;
  }

  /// 插入位（挖孔语义）：按"格中心线"分左右——
  /// 拖拽中心落在某格中心线左侧 → 插到该格之前；右侧 → 插到该格之后。
  /// 例：拖到 B 的右半边 = 插到 B 与 C 之间（用户直觉的"放在 B 右边"）。
  static int slotFromInsertion(double cx, double cy) {
    final row = ((cy - pad - iconCenterDy) / (cellH + gapY))
        .round()
        .clamp(0, rows - 1);
    // 以第一格中心为原点的格距数；ceil = 中心线左侧计入本格、右侧计入下一格
    final t = (cx - pad - cellW / 2) / (cellW + gapX);
    final col = t.ceil().clamp(0, cols);
    return row * cols + col;
  }
}
