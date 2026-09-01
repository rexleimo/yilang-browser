import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/logic/board_model.dart';
import '../../core/metrics.dart';
import '../../core/models/bookmark.dart';
import '../../core/widgets/browser_chrome.dart';
import '../../theme/app_theme.dart';
import 'widgets/bookmark_tile.dart';
import 'widgets/edit_bar.dart';
import 'widgets/folder_overlay.dart';

/// 书签页：网格 / 翻页 / 长按拖动 / 停留合并 / 多选组拖 / 双指切换
class BookmarkDesktopPage extends StatefulWidget {
  const BookmarkDesktopPage({
    super.key,
    required this.model,
    this.active = true,
    required this.onOpenUrl,
    required this.onOpenBrowser,
    required this.onSubmitAddress,
    this.onOpenSettings,
    this.onOpenTabs,
    this.onOpenReadingList,
    this.onOpenHistory,
    this.tabCount = 1,
  });

  final BoardModel model;
  final bool active;
  final void Function(String url) onOpenUrl;
  final VoidCallback onOpenBrowser;
  final ValueChanged<String> onSubmitAddress;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenTabs;
  final VoidCallback? onOpenReadingList;
  final VoidCallback? onOpenHistory;
  final int tabCount;

  @override
  State<BookmarkDesktopPage> createState() => _BookmarkDesktopPageState();
}

class _BookmarkDesktopPageState extends State<BookmarkDesktopPage>
    with SingleTickerProviderStateMixin {
  static const double _pageW = BoardMetrics.baseWidth;
  static const double _boardH = BoardMetrics.boardHeight;

  BoardModel get m => widget.model;

  // 手势状态
  final Map<int, Offset> _pointers = {};
  Offset? _downPos;
  String? _downItemId; // pointerdown 命中的顶层实体
  Timer? _lpTimer;
  Timer? _dwellTimer;
  Timer? _edgeTimer;
  bool _swiping = false;
  double _swipeDx = 0;
  late final AnimationController _snapCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..addListener(() {
      _swipeDx =
          _swipeEndDx * (1 - Curves.easeOutCubic.transform(_snapCtrl.value));
      if (_snapCtrl.isCompleted) _swipeDx = 0;
      setState(() {});
    });
  double _swipeEndDx = 0;

  // 拖拽视觉
  Offset? _dragPointer; // 当前指针（视口局部）
  Offset _grabOffset = Offset.zero; // 抓取点在磁贴内的偏移
  Map<String, Offset> _groupOffsets = {}; // 组成员相对主项偏移

  // 双指
  DateTime? _twoFingerAt;
  bool _twoFingerArmed = false;

  // 浮层
  BookmarkFolder? _openFolder;
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocus = FocusNode();
  bool _showingSearch = false;

  @override
  void initState() {
    super.initState();
    _addressFocus.addListener(() {
      if (_addressFocus.hasFocus && _addressController.text.isNotEmpty) {
        _addressController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _addressController.text.length,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant BookmarkDesktopPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _resetInteraction();
  }

  void _resetInteraction() {
    _cancelLp();
    _cancelTimers();
    _pointers.clear();
    _downPos = null;
    _downItemId = null;
    _swiping = false;
    _swipeDx = 0;
    _dragPointer = null;
    _lastPos = null;
    _openFolder = null;
    _showingSearch = false;
    _addressFocus.unfocus();
    if (m.editing || m.selection.isNotEmpty || m.drag != null) m.exitEdit();
  }

  @override
  void dispose() {
    _lpTimer?.cancel();
    _dwellTimer?.cancel();
    _edgeTimer?.cancel();
    _addressController.dispose();
    _addressFocus.dispose();
    _snapCtrl.dispose();
    super.dispose();
  }

  // ---------------- 命中检测 ----------------

  /// 由视口局部坐标返回命中的顶层实体（含删除角标命中信息）
  ({BookmarkEntity? entity, int? idx, bool onDel, bool hit}) _hitTest(
      Offset pos) {
    final page = m.pages[m.cur];
    for (var idx = 0; idx < page.length; idx++) {
      final pos0 = BoardMetrics.xy(idx);
      final rect = Rect.fromLTWH(
          pos0.dx, pos0.dy, BoardMetrics.cellW, BoardMetrics.cellH);
      if (rect.contains(pos)) {
        final onDel = m.editing &&
            Rect.fromLTWH(pos0.dx - 8, pos0.dy - 8, 21, 21).contains(pos);
        return (entity: page[idx], idx: idx, onDel: onDel, hit: true);
      }
    }
    return (entity: null, idx: null, onDel: false, hit: false);
  }

  // ---------------- 指针事件 ----------------

  void _onDown(PointerDownEvent e) {
    if (!widget.active) return;
    _pointers[e.pointer] = e.localPosition;
    if (m.drag != null) return;

    if (_pointers.length == 2) {
      _cancelLp();
      final pts = _pointers.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      _twoFingerArmed = dist < 140;
      _twoFingerAt = DateTime.now();
      return;
    }
    _twoFingerArmed = false;

    if (!m.settings.hintSeen) {
      m.settings.hintSeen = true;
      m.save();
      setState(() {});
    }

    final hit = _hitTest(e.localPosition);
    if (hit.onDel && hit.entity != null) {
      _askDelete(hit.entity!);
      _downPos = null;
      return;
    }
    _downPos = e.localPosition;
    _downItemId = hit.entity?.id;

    if (hit.entity != null) {
      final id = hit.entity!.id;
      _lpTimer = Timer(Duration(milliseconds: m.editing ? 350 : 500), () {
        m.enterEdit();
        m.startDrag(id);
        final cell = BoardMetrics.xy(hit.idx!);
        _grabOffset = e.localPosition - cell;
        _dragPointer = e.localPosition;
        _groupOffsets = _groupOffsetsFor(m.drag);
        setState(() {});
      });
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!widget.active) return;
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;

    if (m.drag != null) {
      _moveDrag(e.localPosition);
      return;
    }
    if (_swiping) {
      final raw = e.localPosition.dx - _downPos!.dx;
      _swipeDx = _rubber(raw);
      setState(() {});
      return;
    }
    if (_downPos == null) return;
    final d = e.localPosition - _downPos!;
    // Any clear movement means this is a gesture, not a long press.
    if (d.distance > 12) _cancelLp();
    if (d.dx.abs() > 10 && d.dx.abs() > d.dy.abs() && !m.editing) {
      _swiping = true;
      _swipeDx = _rubber(d.dx);
      setState(() {});
    } else if (d.distance > 12 && m.editing && _downItemId != null) {
      m.startDrag(_downItemId!);
      final hit = _hitTest(_downPos!);
      _grabOffset = _downPos! - BoardMetrics.xy(hit.idx ?? 0);
      _dragPointer = e.localPosition;
      _groupOffsets = _groupOffsetsFor(m.drag);
      setState(() {});
    }
  }

  void _onUp(PointerUpEvent e) {
    if (!widget.active) return;
    final wasDown = _downPos != null;
    _pointers.remove(e.pointer);

    if (_pointers.isEmpty && _twoFingerArmed && _twoFingerAt != null) {
      _twoFingerArmed = false;
      if (DateTime.now().difference(_twoFingerAt!) <
          const Duration(milliseconds: 450)) {
        m.editing ? m.exitEdit() : m.enterEdit();
        setState(() {});
        return;
      }
    }

    if (m.drag != null) {
      _cancelTimers();
      m.endDrag();
      _dragPointer = null;
      setState(() {});
      return;
    }
    if (_swiping) {
      _finishSwipe();
      return;
    }
    if (wasDown &&
        _downItemId != null &&
        (e.localPosition - _downPos!).distance < 8) {
      final hit = _hitTest(_downPos!);
      if (hit.entity != null) _tapEntity(hit.entity!);
    }
    _downPos = null;
    _downItemId = null;
  }

  void _onCancel(PointerCancelEvent e) {
    if (!widget.active) return;
    _pointers.remove(e.pointer);
    _cancelLp();
    _cancelTimers();
    m.cancelDrag();
    _dragPointer = null;
    _swiping = false;
    _swipeDx = 0;
    _downPos = null;
    _downItemId = null;
    setState(() {});
  }

  // ---------------- 拖拽 ----------------

  void _moveDrag(Offset pos) {
    final d = m.drag!;
    _dragPointer = pos;

    // 组偏移：抓取时按各自格位相对主项计算
    if (_groupOffsets.isEmpty) _groupOffsets = _groupOffsetsFor(d);

    // 页面局部坐标（主项中心）
    final pageLocal = Offset(pos.dx + (m.cur - d.page) * _pageW, pos.dy);
    final topLeft = pageLocal - _grabOffset;
    final cx = topLeft.dx + BoardMetrics.cellW / 2;
    final cy = topLeft.dy + 31;
    m.dragTo(m.cur, BoardMetrics.slotFromCenter(cx, cy));

    // 停留合并 / 移动解除
    if (_lastPos != null && (_lastPos! - pos).distance > 4) {
      if (d.frozen) m.unfreeze();
      _dwellTimer?.cancel();
      _dwellTimer = Timer(const Duration(milliseconds: 350), () {
        if (m.drag != null) m.freezeDwell();
      });
    }
    _lastPos = pos;

    // 边缘翻页（计时器驱动，手停也能翻）
    final edgeZone = pos.dx < 26 || pos.dx > _pageW - 26;
    if (edgeZone && m.drag != null) {
      final dir = pos.dx < 26 ? -1 : 1;
      _edgeTimer ??= Timer(const Duration(milliseconds: 480), () {
        final target = m.cur + dir;
        if (m.drag != null && (target >= 0 && target <= m.pages.length)) {
          m.flipDragTo(target);
        }
      });
    } else {
      _edgeTimer?.cancel();
      _edgeTimer = null;
    }
    setState(() {});
  }

  Offset? _lastPos;

  Map<String, Offset> _groupOffsetsFor(DragInfo? d) {
    final out = <String, Offset>{};
    if (d == null) return out;
    final baseIdx = m.pages[d.page].indexOf(d.entity);
    final basePos = BoardMetrics.xy(baseIdx < 0 ? 0 : baseIdx);
    for (final g in d.group) {
      final gi = m.pages[d.page].indexOf(g);
      if (gi >= 0) out[g.id] = BoardMetrics.xy(gi) - basePos;
    }
    return out;
  }

  double _rubber(double dx) {
    if ((m.cur == 0 && dx > 0) || (m.cur == m.pages.length - 1 && dx < 0)) {
      return dx * 0.35;
    }
    return dx;
  }

  void _finishSwipe() {
    _swiping = false;
    _swipeEndDx = _swipeDx;
    final target =
        _swipeDx < -70 ? m.cur + 1 : (_swipeDx > 70 ? m.cur - 1 : m.cur);
    if (target != m.cur) m.setCur(target);
    _snapCtrl.forward(from: 0);
    _downPos = null;
    _downItemId = null;
  }

  void _cancelLp() {
    _lpTimer?.cancel();
    _lpTimer = null;
  }

  void _cancelTimers() {
    _dwellTimer?.cancel();
    _dwellTimer = null;
    _edgeTimer?.cancel();
    _edgeTimer = null;
  }

  // ---------------- 点击动作 ----------------

  void _tapEntity(BookmarkEntity e) {
    if (m.editing) {
      m.toggleSelect(e.id);
      return;
    }
    final f = e.asFolder;
    if (f != null) {
      setState(() => _openFolder = f);
    } else {
      final item = e.asItem!;
      _resetInteraction();
      widget.onOpenUrl(item.url);
    }
  }

  void _askDelete(BookmarkEntity e) {
    final desc = e.isFolder
        ? '文件夹内含 ${e.asFolder!.children.length} 个书签，将一并删除'
        : '该书签将从书签列表移除';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${e.name}」？'),
        content: Text(desc,
            style: const TextStyle(fontSize: 13, color: AppColors.subText)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              m.removeItem(e.id);
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('已删除「${e.name}」')));
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _openMoveSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final folders = m.topLevel().whereType<BookmarkFolder>().toList();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('移动到…',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('已选 ${m.selection.length} 项',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.subText)),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final f in folders)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.folder_outlined,
                              color: AppColors.accent),
                          title: Text('${f.name}（${f.children.length}）',
                              style: const TextStyle(fontSize: 13)),
                          onTap: () {
                            m.moveSelectionTo(f.id);
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('已移动 ${m.selection.length} 项')));
                          },
                        ),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.create_new_folder_outlined),
                        title: const Text('新建文件夹收纳',
                            style: TextStyle(fontSize: 13)),
                        onTap: () {
                          m.createFolderFromSelection();
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已创建新文件夹')));
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('浏览器设置',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text('P1 原型 · 设置项将在后续版本接入真实逻辑',
                    style: TextStyle(fontSize: 12, color: AppColors.subText)),
                const SizedBox(height: 10),
                _SettingRow(
                  label: '搜索引擎',
                  trailing: TextButton(
                    onPressed: () {
                      m.settings.searchEngineIndex =
                          (m.settings.searchEngineIndex + 1) %
                              Settings.engines.length;
                      m.save();
                      setSheet(() {});
                    },
                    child: Text(
                        '${Settings.engines[m.settings.searchEngineIndex]} ›',
                        style: const TextStyle(color: AppColors.subText)),
                  ),
                ),
                _SettingRow(
                  label: '广告拦截',
                  trailing: _Switch(
                    value: m.settings.adBlock,
                    onChanged: (v) {
                      m.settings.adBlock = v;
                      m.save();
                      setSheet(() {});
                    },
                  ),
                ),
                _SettingRow(
                  label: '无痕浏览',
                  trailing: _Switch(
                    value: m.settings.incognito,
                    onChanged: (v) {
                      m.settings.incognito = v;
                      m.save();
                      setSheet(() {});
                    },
                  ),
                ),
                _SettingRow(
                  label: '书签云同步',
                  trailing: _Switch(
                    value: m.settings.sync,
                    onChanged: (v) {
                      m.settings.sync = v;
                      m.save();
                      setSheet(() {});
                    },
                  ),
                ),
                const _SettingRow(
                    label: '关于一览 Yilan',
                    trailing: Text('v0.1',
                        style: TextStyle(color: AppColors.subText))),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFF0F2F7)),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _dismissTransientSurface() {
    if (_openFolder != null) {
      setState(() => _openFolder = null);
      return;
    }
    if (m.editing) m.exitEdit();
  }

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _openFolder == null && !m.editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismissTransientSurface();
      },
      child: ListenableBuilder(
        listenable: m,
        builder: (context, _) {
          final browser = context.browserTokens;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.black,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: Color(0xFFF5F7FB),
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
            child: ColoredBox(
              color: browser.chromeBackground,
              child: Column(
                children: [
                  if (MediaQuery.paddingOf(context).top > 0)
                    SizedBox(
                      height: MediaQuery.paddingOf(context).top,
                      child: const ColoredBox(color: Colors.black),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            _buildBrowserTabStrip(),
                            BrowserOmnibox(
                              key: const ValueKey('home-omnibox'),
                              controller: _addressController,
                              focusNode: _addressFocus,
                              hintText: '搜索或输入网址',
                              displayText: '',
                              editing: _showingSearch,
                              onActivate: _openSearch,
                              onSubmit: _submitAddress,
                              onClose: _closeSearch,
                            ),
                            Expanded(
                              child: ColoredBox(
                                color: browser.webViewBackground,
                                child: Column(
                                  children: [
                                    _buildHeader(),
                                    Expanded(child: _buildBoard()),
                                    _buildDots(),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              height: 72 + MediaQuery.paddingOf(context).bottom,
                              child: ColoredBox(
                                color: browser.toolbarBackground,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom:
                                        MediaQuery.paddingOf(context).bottom,
                                  ),
                                  child: _buildBrowserToolbar(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (m.editing)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 72 + MediaQuery.paddingOf(context).bottom,
                            child: EditBar(
                              selectionCount: m.selection.length,
                              onMove: _openMoveSheet,
                              onNewFolder: () {
                                m.createFolderFromSelection();
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已创建新文件夹')));
                              },
                              onDone: m.exitEdit,
                            ),
                          ),
                        if (_openFolder != null)
                          FolderOverlay(
                            folder: _openFolder!,
                            onClose: () => setState(() => _openFolder = null),
                            onOpenEntity: (e) {
                              final item = e.asItem;
                              if (item != null) {
                                setState(() => _openFolder = null);
                                widget.onOpenUrl(item.url);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBrowserTabStrip() {
    return BrowserTabStrip(
      onNewTab: widget.onOpenBrowser,
      chips: const [BrowserTabChip(label: '一览', selected: true, width: 116)],
    );
  }

  Widget _buildBrowserToolbar() {
    return BrowserToolbarFrame(
      keyName: 'bookmark-browser-toolbar',
      buttons: [
        BrowserToolbarButton(
          tooltip: '面板',
          icon: Icons.view_sidebar_outlined,
          onPressed: _showBrowserPanel,
        ),
        const BrowserToolbarButton(
          tooltip: '后退',
          icon: Icons.arrow_back,
        ),
        BrowserToolbarButton(
          key: const ValueKey('home-toolbar-button'),
          tooltip: '搜索',
          icon: Icons.search,
          onPressed: _openSearch,
          selected: true,
        ),
        const BrowserToolbarButton(
          tooltip: '前进',
          icon: Icons.arrow_forward,
        ),
        BrowserToolbarButton(
          tooltip: '标签页',
          icon: Icons.copy_outlined,
          onPressed: widget.onOpenTabs ?? widget.onOpenBrowser,
          badge: '${widget.tabCount}',
        ),
      ],
    );
  }

  void _showBrowserPanel() {
    showBrowserMenuSheet(context, tiles: [
      menuTile(context, icon: Icons.history, title: '历史记录', onTap: () {
        Navigator.pop(context);
        (widget.onOpenHistory ?? widget.onOpenBrowser)();
      }),
      menuTile(context, icon: Icons.chrome_reader_mode_outlined, title: '阅读清单',
          onTap: () {
        Navigator.pop(context);
        (widget.onOpenReadingList ?? widget.onOpenBrowser)();
      }),
      menuTile(context, icon: Icons.settings_outlined, title: '设置', onTap: () {
        Navigator.pop(context);
        (widget.onOpenSettings ?? _openSettingsSheet).call();
      }),
    ]);
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('新标签页',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                Text('书签',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Tooltip(
            message: '整理书签',
            child: TextButton.icon(
              onPressed: m.editing
                  ? null
                  : () {
                      _addressFocus.unfocus();
                      m.enterEdit();
                    },
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('整理'),
            ),
          ),
          IconButton(
            tooltip: '更多浏览器操作',
            onPressed: m.editing ? null : _showBrowserPanel,
            icon: const Icon(Icons.more_horiz, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard() {
    final d = m.drag;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: _pageW,
          height: _boardH,
          child: ClipRect(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              onPointerCancel: _onCancel,
              child: Stack(
                children: [
                  // 页面行（含翻页滑动）
                  Transform.translate(
                    offset: Offset(-m.cur * _pageW + _swipeDx, 0),
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: 0,
                      maxWidth: _pageW * m.pages.length,
                      child: SizedBox(
                        width: _pageW * m.pages.length,
                        height: _boardH,
                        child: Stack(
                          children: [
                            for (var p = 0; p < m.pages.length; p++)
                              Positioned(
                                left: p * _pageW,
                                top: 0,
                                width: _pageW,
                                height: _boardH,
                                child: _buildPage(p),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 拖拽浮层
                  if (d != null && _dragPointer != null)
                    ..._buildDragOverlay(d),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(int p) {
    final page = m.pages[p];
    return Stack(
      children: [
        for (var idx = 0; idx < page.length; idx++) _tileAt(page[idx], idx, p),
      ],
    );
  }

  Widget _tileAt(BookmarkEntity e, int idx, int pageIdx) {
    final pos = BoardMetrics.xy(idx);
    final d = m.drag;
    final isDragMember = d != null && d.all.any((x) => x.id == e.id);
    return AnimatedPositioned(
      key: ValueKey('tile-${e.id}'),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      left: pos.dx,
      top: pos.dy,
      width: BoardMetrics.cellW,
      height: BoardMetrics.cellH,
      child: BookmarkTile(
        entity: e,
        jiggling: m.editing && !isDragMember,
        selected: m.selection.contains(e.id),
        hovered: d?.hoverFolder?.id == e.id,
        merged: d?.mergeTarget?.id == e.id,
        faded: isDragMember,
      ),
    );
  }

  List<Widget> _buildDragOverlay(DragInfo d) {
    final ptr = _dragPointer!;
    final topLeft = ptr - _grabOffset;
    final widgets = <Widget>[
      Positioned(
        left: topLeft.dx,
        top: topLeft.dy,
        width: BoardMetrics.cellW,
        height: BoardMetrics.cellH,
        child:
            _DragGhost(entity: d.entity, selected: m.selection.contains(d.id)),
      ),
      for (final g in d.group)
        Positioned(
          left: topLeft.dx + (_groupOffsets[g.id]?.dx ?? 0),
          top: topLeft.dy + (_groupOffsets[g.id]?.dy ?? 0),
          width: BoardMetrics.cellW,
          height: BoardMetrics.cellH,
          child: _DragGhost(entity: g, selected: true),
        ),
    ];
    return widgets;
  }

  Widget _buildDots() {
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var p = 0; p < m.pages.length; p++)
            GestureDetector(
              onTap: () => m.setCur(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: p == m.cur ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: p == m.cur
                      ? const Color(0xBF323A5A)
                      : const Color(0x473C4660),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openSearch() {
    if (m.editing) m.exitEdit();
    setState(() {
      _openFolder = null;
      _showingSearch = true;
      _addressController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _addressFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _addressFocus.unfocus();
    setState(() => _showingSearch = false);
  }

  void _submitAddress(String raw) {
    final value = raw.trim();
    _addressFocus.unfocus();
    setState(() => _showingSearch = false);
    if (value.isEmpty) return;
    widget.onSubmitAddress(value);
    _addressController.clear();
  }
}

/// 拖拽中的磁贴（放大 + 投影）
class _DragGhost extends StatelessWidget {
  const _DragGhost({required this.entity, required this.selected});

  final BookmarkEntity entity;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 1.12,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Color(0x66141E3C), blurRadius: 34, offset: Offset(0, 14))
          ],
        ),
        child: BookmarkTile(entity: entity, selected: selected),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13.5, color: AppColors.ink)),
          trailing,
        ],
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      activeThumbColor: AppColors.success,
      onChanged: onChanged,
    );
  }
}
