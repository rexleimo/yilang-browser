import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/metrics.dart';

/// 插入位判定：按"格中心线"分左右——
/// 拖拽中心在某格中心线左侧 → 插到该格之前；右侧 → 插到该格之后。
/// 用户直觉：拖到某项右半边 = 放到它右边（它与下一项之间）。
void main() {
  group('slotFromInsertion 按格中心线分左右', () {
    // 第一格中心 x = pad + cellW/2；格距 = cellW + gapX；
    // 行中心 y = pad + iconSize/2（iconCenterDy）。
    const double c0 = BoardMetrics.pad + BoardMetrics.cellW / 2;
    const double pitch = BoardMetrics.cellW + BoardMetrics.gapX;
    const double yRow0 = BoardMetrics.pad + BoardMetrics.iconSize / 2;

    test('第一格中心线左侧 → 插到最前', () {
      expect(BoardMetrics.slotFromInsertion(c0 - 10, yRow0), 0);
    });

    test('B 中心线右侧 = 放在 B 右边（B 与 C 之间）', () {
      const c1 = c0 + pitch;
      expect(BoardMetrics.slotFromInsertion(c1 + 10, yRow0), 2);
    });

    test('C 中心线左侧 = 插到 C 之前（同样是 B 与 C 之间）', () {
      const c2 = c0 + 2 * pitch;
      expect(BoardMetrics.slotFromInsertion(c2 - 10, yRow0), 2);
    });

    test('最后一格中心线右侧 → 追加到行尾之后', () {
      const c3 = c0 + 3 * pitch;
      expect(BoardMetrics.slotFromInsertion(c3 + 30, yRow0), 4);
    });

    test('第二行 C 中心线左侧 = 全局第 6 位', () {
      const yRow1 = yRow0 + BoardMetrics.cellH + BoardMetrics.gapY;
      const c2 = c0 + 2 * pitch;
      expect(BoardMetrics.slotFromInsertion(c2 - 10, yRow1), 6);
    });
  });
}
