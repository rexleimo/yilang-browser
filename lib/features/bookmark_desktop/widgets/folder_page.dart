import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../core/models/bookmark.dart';
import '../../../core/widgets/ui_kit.dart';
import 'bookmark_tile.dart';

/// iOS 主屏风格的文件夹面板：主页板整体高斯模糊 + 压暗做背景，
/// 文件夹内容悬浮在磨砂玻璃圆角面板中，标题显示在面板上方。
///
/// 与主页书签网格同一套磁贴语言，点条目打开网页，点子文件夹继续深入；
/// 点标题进入行内改名（iOS 文件夹习惯）；点面板外空白关闭面板。
/// 编辑交互（iOS 主屏一致）：
/// - 长按条目拖动 → 在网格内让位重排；
/// - 拖到标题 → 高亮提示，松手把条目拖出文件夹（回到上级）。
class FolderPage extends StatefulWidget {
  const FolderPage({
    super.key,
    required this.folder,
    required this.onBack,
    required this.onOpenFolder,
    required this.onOpenItem,
    this.onRename,
    this.onReorder,
    this.onDragOutItem,
    this.onDragMoved,
    this.onDragFinished,
  });

  final BookmarkFolder folder;
  final VoidCallback onBack;

  /// 子层级文件夹（模型允许文件夹嵌套）
  final ValueChanged<BookmarkFolder> onOpenFolder;
  final ValueChanged<BookmarkItem> onOpenItem;

  /// 改名提交回调（空串/纯空白会被忽略）
  final ValueChanged<String>? onRename;

  /// 文件夹内重排：[child] 落到 [targetIdx] 槽位（模型做让位插入）
  final void Function(BookmarkEntity child, int targetIdx)? onReorder;

  /// 拖出到上级：条目落回文件夹所在层的下一个位置
  final ValueChanged<BookmarkEntity>? onDragOutItem;

  /// 拖出交接：面板收起后，拖拽继续在首页板跟手（每帧全局坐标）
  final ValueChanged<Offset>? onDragMoved;

  /// 拖出交接结束（松手/取消）
  final VoidCallback? onDragFinished;

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  bool _editingName = false;
  bool _hoverExit = false; // 拖拽悬停在标题拖出区
  bool _handedOff = false; // 拖出交接已触发（本次手势只触发一次）
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.folder.name);
  final FocusNode _nameFocus = FocusNode();

  @override
  void didUpdateWidget(covariant FolderPage old) {
    super.didUpdateWidget(old);
    if (old.folder.id != widget.folder.id) {
      _nameCtrl.text = widget.folder.name;
      _editingName = false;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _commitRename() {
    final value = _nameCtrl.text.trim();
    setState(() => _editingName = false);
    if (value.isNotEmpty && value != widget.folder.name) {
      widget.onRename?.call(value);
    }
  }

  Widget _feedbackTile(BookmarkEntity e) {
    return Transform.scale(
      scale: 1.1,
      child: Container(
        width: 84,
        height: 104,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Color(0x55141E3C), blurRadius: 26, offset: Offset(0, 10))
          ],
        ),
        child: BookmarkTile(entity: e, compact: true),
      ),
    );
  }

  /// 面板上方标题区：显示文件夹名 + 项目数；点标题进入行内改名。
  /// 拖出投放区已改为整个面板外背景（_hoverExit 时标题提示「松手移出文件夹」）。
  Widget _titleArea(ColorScheme scheme, bool canDrag) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _editingName = true),
      onLongPress: () => setState(() => _editingName = true),
      child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 6, 28, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_editingName)
                SizedBox(
                  width: 240,
                  height: 34,
                  child: KeyboardFocusKickoff(
                    focusNode: _nameFocus,
                    child: TextField(
                      controller: _nameCtrl,
                      focusNode: _nameFocus,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 4),
                        border: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.white.withValues(alpha: .4)),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.white.withValues(alpha: .4)),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: Colors.white, width: 1.6),
                        ),
                      ),
                      onSubmitted: (_) => _commitRename(),
                      onTapOutside: (_) => _commitRename(),
                    ),
                  ),
                )
              else
                Text(
                  _hoverExit ? '松手移出文件夹' : widget.folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _hoverExit ? UIKit.accent : Colors.white,
                    shadows: const [
                      BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 12,
                          offset: Offset(0, 2)),
                    ],
                  ),
                ),
              const SizedBox(height: 3),
              Text(
                '${widget.folder.children.length} 个项目',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: .75),
                ),
              ),
            ],
          ),
      ),
    );
  }

  /// 磨砂玻璃圆角面板：模糊透出背后已压暗的主页板。
  Widget _panel(ColorScheme scheme, Widget content) {
    return GestureDetector(
      // 吸收面板内部的点击，避免误触背景关闭
      onTap: () {},
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .62),
              // 圆角与外面图标的圆角（17）保持一致
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: Colors.white.withValues(alpha: .6), width: 1.5),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x59141E3C),
                    blurRadius: 60,
                    offset: Offset(0, 26)),
              ],
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canDrag = widget.onReorder != null || widget.onDragOutItem != null;

    // 面板内容几何：3 列大磁贴（参考图比例），面板宽度固定、高度按行数贴合。
    const int cols = 3;
    const double cellW = 84;
    const double rowH = cellW / 0.78;
    const double panelW = cols * cellW + (cols - 1) * 14 + 2 * 24;
    const double maxPanelH = 470;

    final Widget content = widget.folder.children.isEmpty
        ? SizedBox(
            width: panelW,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(44, 36, 44, 42),
              child: Text(
                '文件夹是空的',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
          )
        : Builder(builder: (context) {
            final rows = (widget.folder.children.length / cols).ceil();
            final contentH =
                16 + rows * rowH + (rows - 1) * 16 + 24;
            final grid = GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 14,
                mainAxisSpacing: 16,
                childAspectRatio: 0.78,
              ),
              itemCount: widget.folder.children.length,
              itemBuilder: (context, i) {
                final child = widget.folder.children[i];
                final tile = InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    if (_editingName) {
                      _commitRename();
                      return;
                    }
                    final f = child.asFolder;
                    if (f != null) {
                      widget.onOpenFolder(f);
                    } else {
                      widget.onOpenItem(child.asItem!);
                    }
                  },
                  child: BookmarkTile(entity: child, iconSize: cellW - 20),
                );
                if (!canDrag) return tile;
              return LongPressDraggable<BookmarkEntity>(
                data: child,
                delay: const Duration(milliseconds: 160),
                // 反馈图标跟随手指（pointer 锚点，iOS 手感）
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: _feedbackTile(child),
                childWhenDragging: Opacity(
                    opacity: .28, child: BookmarkTile(entity: child)),
                onDragCompleted: () {},
                // 拖出交接：把拖拽位置持续转给首页板
                onDragUpdate: (d) =>
                    widget.onDragMoved?.call(d.globalPosition),
                onDragEnd: (_) => widget.onDragFinished?.call(),
                onDraggableCanceled: (_, __) =>
                    widget.onDragFinished?.call(),
                child: DragTarget<BookmarkEntity>(
                    onWillAcceptWithDetails: (details) =>
                        details.data.id != child.id,
                    onAcceptWithDetails: (details) =>
                        widget.onReorder?.call(details.data, i),
                    builder: (context, candidates, _) => tile,
                  ),
                );
              },
            );
            // 高度贴合行数；超出上限才内部滚动
            if (contentH <= maxPanelH) {
              return SizedBox(
                  width: panelW, height: contentH, child: grid);
            }
            return SizedBox(
              width: panelW,
              height: maxPanelH,
              child: SingleChildScrollView(child: grid),
            );
          });

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 背景：主页板高斯模糊 + 压暗；点空白 = 关闭（改名中则提交改名）。
          // 同时是拖出投放区：条目拖出面板边界即触发交接 —— 面板收起，
          // 拖拽继续在首页板跟手（iOS 手感），松手才落位。
          Positioned.fill(
            child: DragTarget<BookmarkEntity>(
              onWillAcceptWithDetails: (details) =>
                  canDrag && widget.onDragOutItem != null,
              onMove: (details) {
                if (!_hoverExit) setState(() => _hoverExit = true);
                // 越过面板边界的第一次移动即交接，避免等松手才结算
                final dragOut = widget.onDragOutItem;
                if (!_handedOff &&
                    canDrag &&
                    dragOut != null &&
                    widget.onDragMoved != null) {
                  _handedOff = true;
                  dragOut(details.data);
                }
              },
              onLeave: (_) {
                if (_hoverExit) setState(() => _hoverExit = false);
              },
              onAcceptWithDetails: (details) {
                if (_handedOff) return; // 已交接，落位交给首页板处理
                widget.onDragOutItem?.call(details.data);
              },
              builder: (context, candidates, _) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _editingName ? _commitRename : widget.onBack,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: const ColoredBox(
                      color: Color(0x43141E3C),
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 前景：标题在面板上方，磨砂圆角面板装网格
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _titleArea(scheme, canDrag),
                _panel(scheme, content),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
