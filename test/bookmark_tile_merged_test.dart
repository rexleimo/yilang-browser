/// 合并态目标磁贴视觉回归（外扩托盘模型）：
/// 目标图标完全原样（scale 1、位置零变动、无缩小抖动），
/// 托盘从原位向外扩出（S→1.25S，溢出绘制不占布局）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/features/bookmark_desktop/widgets/bookmark_tile.dart';

void main() {
  testWidgets(
      'merged target: icon untouched (scale 1), tray expands outward to 1.25S',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: BookmarkTile(
          entity: BookmarkItem(id: 'a', name: 'A', url: 'a.com'),
          merged: true,
        ),
      ),
    ));
    await tester.pump();
    // 推进托盘/图标缩放动画（200ms）到终态
    await tester.pump(const Duration(milliseconds: 250));

    // 位置钉死：磁贴布局尺寸不变（托盘溢出绘制不占布局）
    final rect = tester.getRect(find.byType(BookmarkTile));
    expect(rect.width, 56, reason: '托盘不得改变布局尺寸');
    expect(rect.height, 84, reason: '图标 56 + 5 + 名称 + 1 + 分类 = 84');

    // 目标图标纹丝不动：不得出现图标缩小（0.76/0.9 均算回归）
    final scales = tester
        .widgetList<Transform>(find.byType(Transform))
        .map((t) => t.transform.storage[0])
        .toSet();
    expect(
      scales.any((s) => (s - 0.76).abs() < 0.02 || (s - 0.9).abs() < 0.02),
      isFalse,
      reason: '目标图标不得缩小（保持原样）',
    );
    // 托盘弹出：1.0 → 1.25（easeOutBack 抽屉感）
    expect(
      scales.any((s) => (s - 1.25).abs() < 0.01),
      isTrue,
      reason: '托盘应放大到 1.25S',
    );
    // 描边环：空心（无实心底色）+ 白描边 2px + 大圆角，从图标边缘外扩
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == null &&
            (w.decoration! as BoxDecoration).border!.top.width == 2 &&
            (w.decoration! as BoxDecoration).borderRadius ==
                BorderRadius.circular(56 * 0.28),
      ),
      findsOneWidget,
      reason: '合并态应有空心描边环（不得用实心底板，否则图标显小一圈）',
    );
    expect(tester.takeException(), isNull);
  });
}
