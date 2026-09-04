import 'package:flutter/material.dart';

import '../../../core/models/bookmark.dart';
import 'bookmark_tile.dart';

/// 松手落位动画数据。
class SettleAnim {
  const SettleAnim({
    required this.entity,
    required this.from,
    required this.to,
    this.endScale,
  });

  final BookmarkEntity entity;
  final Offset from; // 幽灵当前左上角（手指位置）
  final Offset to; // 落点格子左上角

  /// 幽灵终态缩放（null = 保持抬起尺寸）；合并掉入托盘时 0.45。
  final double? endScale;
}

/// 拖拽中的磁贴（放大 + 投影）。
class BoardDragGhost extends StatelessWidget {
  const BoardDragGhost({super.key, required this.entity, this.endScale});

  final BookmarkEntity entity;

  /// 松手落位终态缩放（null = 保持 1.22 抬起尺寸）；
  /// 合并掉入托盘时由 SettleAnim 传入 0.45。
  final double? endScale;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.22, end: endScale ?? 1.22),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Color(0x66141E3C), blurRadius: 44, offset: Offset(0, 18))
          ],
        ),
        child: BookmarkTile(entity: entity, compact: true),
      ),
    );
  }
}
