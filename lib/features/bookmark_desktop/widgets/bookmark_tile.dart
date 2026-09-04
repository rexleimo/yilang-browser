import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/models/bookmark.dart';
import '../../../core/metrics.dart';
import '../../../core/storage/favicon_service.dart';
import '../../../theme/app_theme.dart';

/// 书签磁贴（条目 / 文件夹统一渲染）
class BookmarkTile extends StatelessWidget {
  const BookmarkTile({
    super.key,
    required this.entity,
    this.iconSize = BoardMetrics.iconSize,
    this.hovered = false,
    this.merged = false,
    this.faded = false, // 拖拽项原格：淡出占位
    this.jiggling = false,
    this.jiggle,
    this.compact = false, // 拖拽幽灵：只画图标不画文字（iOS 拖拽中隐藏 label）
    this.onTap,
    this.onDelete,
  });

  final BookmarkEntity entity;
  final double iconSize;
  final bool compact;
  final bool faded;
  final bool hovered; // 悬停文件夹目标高亮（蓝）
  final bool merged; // 冻结合并目标：轻微后退（iOS 松手才生成文件夹）
  final bool jiggling; // 编辑抖动

  /// 页面级共享抖动相位（0..1 循环）。编辑态所有磁贴共用一个
  /// AnimationController，省掉每格一个 ticker；null 时回退自带控制器。
  final Animation<double>? jiggle;

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
              if (!compact) ...[
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
            ],
        ),
        ),
        // iOS 式：白色半透明圆 + 深灰减号，点击弹确认删除。
        if (jiggling && onDelete != null && !merged)
          Positioned(
            top: -8,
            left: -8,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 21,
                height: 21,
                decoration: const BoxDecoration(
                  color: Color(0xE8FFFFFF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x40000000), blurRadius: 6)
                  ],
                ),
                child: const Icon(Icons.remove,
                    size: 15, color: Color(0xFF8E8E93)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _icon(BuildContext context) {
    final size = iconSize;
    // host 统一走 _uriOf（兼容老数据裸域名如 `zhihu.com`）：
    // 否则装饰层判定非网页磁贴 → 全幅渐变底，而图标层照常加载 favicon，
    // 渐变色会从磁贴边角露出来。
    final host =
        entity.isFolder ? null : _uriOf(entity.asItem!.url)?.host;
    final isWebBookmark = host != null && host.isNotEmpty;
    final base = Container(
      width: size,
      height: size,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        gradient: entity.isFolder || isWebBookmark
            ? null
            : tileGradient(entity.asItem!.url),
        color: entity.isFolder
            ? const Color(0xB3FFFFFF)
            : (isWebBookmark ? Colors.white : null),
        border: entity.isFolder
            ? Border.all(color: const Color(0x33000000), width: 1)
            : Border.all(
                color: const Color(0x14000000),
                width: 1,
              ),
        boxShadow: [
          if (hovered)
            const BoxShadow(
              color: AppColors.primary,
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

    // iOS 参考（图二）：合并悬停原图标不动、不缩，外面扩一圈环
    // （圆角矩形光环，200ms 从小放大弹出）；松手才真正生成文件夹。
    // 图标布局尺寸不变，环溢出绘制（clip none）不占布局，邻格不位移。
    final body = merged
        ? Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.8, end: 1.0),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                builder: (context, s, child) => Transform.scale(
                  scale: s,
                  child: child,
                ),
                child: Container(
                  width: size + 10,
                  height: size + 10,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: const Color(0x33000000), width: 1),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x24141E3C),
                          blurRadius: 12,
                          offset: Offset(0, 4)),
                    ],
                  ),
                ),
              ),
              base,
            ],
          )
        : base;
    return jiggling && !merged
        ? _Jiggle(
            phase: entity.id.hashCode % 7 / 7,
            anim: jiggle,
            child: body,
          )
        : body;
  }

  /// 书签 url 可能是裸域名（如 `zhihu.com`），补 scheme 后再取 host。
  static Uri? _uriOf(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    var u = Uri.tryParse(trimmed);
    if (u == null || u.host.isEmpty) {
      u = Uri.tryParse('https://$trimmed');
    }
    return (u != null && u.host.isNotEmpty) ? u : null;
  }

  Widget _itemContent(BookmarkItem item) {
    // 有网址的书签直接显示站点图标（同浏览器标签页）。
    // 图标加载中/失败时露出底层的渐变首字母，不会白板。
    final host = _uriOf(item.url)?.host;
    if (host != null && host.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // 兜底层：白底 + 彩色首字母（与 favicon 磁贴统一观感）
          Container(
            color: Colors.white,
            child: Center(
              child: Text(
                item.name.characters.first,
                style: TextStyle(
                    fontSize: iconSize * 0.42,
                    fontWeight: FontWeight.w700,
                    color: tileGradient(item.url).colors.last),
              ),
            ),
          ),
          // 站点图标层：本地缓存（SQLite blob）优先，未命中才联网抓取并入库。
          // 图标加载中/失败时保持透明，露出底层首字母。
          // 统一缩进到磁贴 66% 的固定盒内：不同站点 favicon 裁切差异大
          // （有的紧贴画布、有的自带留白），不定盒会顶边溢出、
          // 圆角处出现被裁切的「缺口」。
          Positioned.fill(
            child: _FaviconImage(host: host, iconSize: iconSize),
          ),
          if (item.unread)
            const Positioned(top: 4, right: 4, child: _UnreadDot()),
          if (item.progress != null)
            Positioned(right: 3, bottom: 3, child: _ProgressRing(item.progress!)),
        ],
      );
    }
    return _letterFallback(item);
  }

  Widget _letterFallback(BookmarkItem item) {
    final g = tileGradient(item.url);
    return Stack(
      children: [
        Container(
          color: Colors.white,
          child: Center(
            child: Text(
              item.name.characters.first,
              style: TextStyle(
                  fontSize: iconSize * 0.42,
                  fontWeight: FontWeight.w700,
                  color: g.colors.last),
            ),
          ),
        ),
        if (item.unread)
          const Positioned(top: 4, right: 4, child: _UnreadDot()),
        if (item.progress != null)
          Positioned(right: 3, bottom: 3, child: _ProgressRing(item.progress!)),
      ],
    );
  }

  Widget _folderGrid(BookmarkFolder folder) {
    final minis = folder.children.take(9).map((c) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
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

/// 编辑态抖动：优先用外部共享相位（整页一个 ticker），否则自带控制器。
/// Transform 下方垫 RepaintBoundary：磁贴内容栅格被缓存，每帧只在
/// 合成器做旋转变换，不再整块重绘。
class _Jiggle extends StatefulWidget {
  const _Jiggle({
    required this.phase,
    required this.child,
    this.anim,
  });

  final double phase;
  final Widget child;
  final Animation<double>? anim;

  @override
  State<_Jiggle> createState() => _JiggleState();
}

class _JiggleState extends State<_Jiggle> with SingleTickerProviderStateMixin {
  AnimationController? _own;
  Animation<double> get _a {
    final shared = widget.anim;
    if (shared != null) return shared;
    return _own ??= (AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..repeat());
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final dir = widget.phase < 0.5 ? 1.0 : -1.0;
    return AnimatedBuilder(
      animation: a,
      builder: (_, child) => Transform.rotate(
        angle: math.sin((a.value + widget.phase) * 2 * math.pi) * 0.03 * dir,
        child: child,
      ),
      child: RepaintBoundary(child: widget.child),
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

/// 站点图标：本地缓存优先（FaviconService → SQLite blob），命中即无网络等待，
/// 重启/升级后也不重闪。首次抓取期间透明，露出底层的首字母兜底。
class _FaviconImage extends StatefulWidget {
  const _FaviconImage({required this.host, required this.iconSize});

  final String host;
  final double iconSize;

  @override
  State<_FaviconImage> createState() => _FaviconImageState();
}

class _FaviconImageState extends State<_FaviconImage> {
  Uint8List? _bytes;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _FaviconImage old) {
    super.didUpdateWidget(old);
    if (old.host != widget.host) {
      _loaded = false;
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final svc = FaviconService.maybe;
    final bytes = svc == null ? null : await svc.get(widget.host);
    if (mounted) {
      setState(() {
        _bytes = bytes;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.iconSize;
    if (!_loaded || _bytes == null) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      color: Colors.white,
      alignment: Alignment.center,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(s * .2),
        child: SizedBox(
          width: s * .66,
          height: s * .66,
          child: Image.memory(
            _bytes!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            frameBuilder: (ctx, child, frame, _) => AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: frame == null ? 0 : 1,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
