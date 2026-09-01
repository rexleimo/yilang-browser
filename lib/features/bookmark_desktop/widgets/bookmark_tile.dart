import 'package:flutter/material.dart';

import '../../../core/models/bookmark.dart';
import '../../../core/metrics.dart';
import '../../../theme/app_theme.dart';

/// 书签磁贴（条目 / 文件夹统一渲染）
class BookmarkTile extends StatelessWidget {
  const BookmarkTile({
    super.key,
    required this.entity,
    this.iconSize = BoardMetrics.iconSize,
    this.selected = false,
    this.hovered = false,
    this.merged = false,
    this.jiggling = false,
    this.faded = false,
    this.onTap,
    this.onDelete,
  });

  final BookmarkEntity entity;
  final double iconSize;
  final bool selected;
  final bool hovered; // 吸入目标高亮（蓝）
  final bool merged; // 合并目标高亮（橙）
  final bool jiggling; // 编辑抖动
  final bool faded; // 拖拽中的本体（透明占位）
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(
          opacity: faded ? 0.15 : 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _icon(context),
              const SizedBox(height: 5),
              Text(
                entity.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 11,
                      height: 1.1,
                      color: context.tokens.textPrimary,
                    ),
              ),
              const SizedBox(height: 1),
              Text(
                entity.isFolder
                    ? '${entity.asFolder!.children.length} 项'
                    : (entity.asItem!.category),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      height: 1.1,
                      color: context.tokens.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        if (jiggling && onDelete != null)
          Positioned(
            top: -8,
            left: -8,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 21,
                height: 21,
                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x40000000), blurRadius: 6)
                  ],
                ),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        if (selected)
          Positioned(
            top: -5,
            right: -5,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.check, size: 13, color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _icon(BuildContext context) {
    final size = iconSize;
    final base = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: entity.isFolder ? null : tileGradient(entity.asItem!.url),
        color: entity.isFolder ? const Color(0xB3FFFFFF) : null,
        border:
            entity.isFolder ? Border.all(color: const Color(0x33000000)) : null,
        boxShadow: [
          if (hovered || merged)
            BoxShadow(
              color: hovered ? AppColors.primary : AppColors.warn,
              spreadRadius: 1,
              blurRadius: 0,
            )
          else
            const BoxShadow(
                color: Color(0x2E1E2846), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: entity.isFolder
          ? _folderGrid(entity.asFolder!)
          : _itemContent(entity.asItem!),
    );

    Widget body = base;
    if (jiggling) {
      body = _Jiggle(phase: entity.id.hashCode % 3, child: body);
    }
    return body;
  }

  Widget _itemContent(BookmarkItem item) {
    return Stack(
      children: [
        Center(
          child: Text(
            item.name.characters.first,
            style: TextStyle(
                fontSize: iconSize * 0.42,
                fontWeight: FontWeight.w700,
                color: Colors.white),
          ),
        ),
        if (item.unread)
          const Positioned(top: 4, right: 4, child: _UnreadDot()),
        if (item.progress != null)
          Positioned(
              right: -5, bottom: -5, child: _ProgressRing(item.progress!)),
      ],
    );
  }

  Widget _folderGrid(BookmarkFolder folder) {
    final minis = folder.children.take(9).map((c) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: c.isFolder ? null : tileGradient(c.asItem!.url),
            color: c.isFolder ? const Color(0x668A8F9C) : null,
          ),
        ),
      );
    }).toList();
    return Padding(
      padding: EdgeInsets.all(iconSize * 0.13),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var r = 0; r < 3; r++)
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < 3; c++)
                    r * 3 + c < minis.length
                        ? minis[r * 3 + c]
                        : const Spacer(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Jiggle extends StatefulWidget {
  const _Jiggle({required this.phase, required this.child});

  final int phase;
  final Widget child;

  @override
  State<_Jiggle> createState() => _JiggleState();
}

class _JiggleState extends State<_Jiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dir = widget.phase == 0 ? 1.0 : (widget.phase == 1 ? -1.0 : 0.6);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.rotate(
        angle: (widget.phase % 2 == 0 ? 1 : -1) * (_c.value - 0.5) * 0.06 * dir,
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing(this.progress);

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration:
          const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      padding: const EdgeInsets.all(2),
      child: CircularProgressIndicator(
        value: (progress / 100).clamp(0.0, 1.0),
        strokeWidth: 2.5,
        backgroundColor: const Color(0xFFE5E7EE),
        color: AppColors.success,
      ),
    );
  }
}
