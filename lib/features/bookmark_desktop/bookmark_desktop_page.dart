import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/logic/board_model.dart';
import '../../core/metrics.dart';
import '../../core/models/bookmark.dart';
import '../../core/widgets/browser_chrome.dart';
import '../../theme/app_theme.dart';
import '../browser/browser_page.dart';
import 'widgets/bookmark_tile.dart';
import 'widgets/folder_page.dart';

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
    this.tabSummaries = const [],
    this.onSelectBrowserTab,
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

  /// Live browser tabs so Home's strip shows them alongside the 一览 chip.
  final List<BrowserTabSummary> tabSummaries;
  final ValueChanged<int>? onSelectBrowserTab;

  @override
  State<BookmarkDesktopPage> createState() => _BookmarkDesktopPageState();
}

class _BookmarkDesktopPageState extends State<BookmarkDesktopPage>
    with TickerProviderStateMixin {
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
  double _swipeEndDx = 0;

  /// 长按上下文菜单（iOS 式：先弹菜单，按住拖动 → 菜单收起进编辑态顺势拖拽）。
  ({BookmarkEntity entity, int idx})? _ctxMenu;

  /// 编辑态共享抖动相位：整页一个 ticker，替代每格一个。
  late final AnimationController _jiggleCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  /// 翻页滑动偏移走 ValueNotifier，避免每次指针移动重建整页。
  final ValueNotifier<double> _swipeDxNotifier = ValueNotifier(0);

  late final AnimationController _snapCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..addListener(() {
      _swipeDxNotifier.value =
          _swipeEndDx * (1 - Curves.easeOutCubic.transform(_snapCtrl.value));
      if (_snapCtrl.isCompleted) _swipeDxNotifier.value = 0;
    });

  // 拖拽视觉
  /// 拖拽指针位置走 ValueNotifier：拖拽时只有 ghost 层重建，网格不跟着重建。
  final ValueNotifier<Offset?> _dragPointerNotifier = ValueNotifier(null);

  /// 松手落位动画：幽灵从手指位置滑进落点格子（240ms），期间落位磁贴隐藏。
  _SettleAnim? _settle;
  Offset _grabOffset = Offset.zero; // 抓取点在磁贴内的偏移
  Map<String, Offset> _groupOffsets = {}; // 组成员相对主项偏移

  // 双指
  DateTime? _twoFingerAt;
  bool _twoFingerArmed = false;

  // 浮层
  final List<BookmarkFolder> _folderStack = [];
  // 拖出交接：面板已收起但 FolderPage 保持挂载（Offstage），
  // 拖拽继续在首页板跟手，松手时经 onDragFinished 落位。
  bool _folderDragHandoff = false;
  BookmarkFolder? _handoffFolder;
  final GlobalKey _boardKey = GlobalKey();

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
    _swipeDxNotifier.value = 0;
    _dragPointerNotifier.value = null;
    _lastPos = null;
  _freezePos = null;
    _folderStack.clear();
    _ctxMenu = null;
    _showingSearch = false;
    _addressFocus.unfocus();
    if (m.editing || m.drag != null) m.exitEdit();
  }

  @override
  void dispose() {
    _lpTimer?.cancel();
    _dwellTimer?.cancel();
    _edgeTimer?.cancel();
    _addressController.dispose();
    _addressFocus.dispose();
    _snapCtrl.dispose();
    _swipeDxNotifier.dispose();
    _dragPointerNotifier.dispose();
    _jiggleCtrl.dispose();
    super.dispose();
  }

  // ---------------- 命中检测 ----------------

  /// 由视口局部坐标返回命中的顶层实体。
  /// 删除入口只在磁贴左上角的减号徽章（onDelete → _askDelete），不做隐形命中区。
  ({BookmarkEntity? entity, int? idx, bool hit}) _hitTest(Offset pos) {
    final page = m.pages[m.cur];
    for (var idx = 0; idx < page.length; idx++) {
      final pos0 = BoardMetrics.xy(idx);
      final rect = Rect.fromLTWH(
          pos0.dx, pos0.dy, BoardMetrics.cellW, BoardMetrics.cellH);
      if (rect.contains(pos)) {
        return (entity: page[idx], idx: idx, hit: true);
      }
    }
    return (entity: null, idx: null, hit: false);
  }

  // ---------------- 指针事件 ----------------

  void _onDown(PointerDownEvent e) {
    if (!widget.active) return;
    // 菜单开着时按下的必是新指针：只负责收菜单（浮层挡板也会兜住）。
    if (_ctxMenu != null) {
      _dismissCtxMenu();
      return;
    }
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
    _downPos = e.localPosition;
    _downItemId = hit.entity?.id;

    if (hit.entity != null) {
      final id = hit.entity!.id;
      _lpTimer = Timer(Duration(milliseconds: m.editing ? 350 : 500), () {
        if (!mounted) return;
        // 编辑态保持整板无遮挡（iOS 参考）：进入编辑时收起搜索条与键盘。
        if (_showingSearch) _closeSearch();
        if (!m.editing) {
          // iOS 参考（视频 0-1s）：非编辑态长按先弹上下文菜单，
          // 不直接进编辑；按住拖动才收菜单进编辑态顺势拖拽（见 _onMove）。
          setState(() => _ctxMenu = (entity: hit.entity!, idx: hit.idx!));
          return;
        }
        m.startDrag(id);
        _beginDragVisuals(e.localPosition);
        setState(() {});
      });
    }
  }

  /// 起拖视觉初始化（长按起拖 / 菜单拖动接管 / 编辑态拖动共用）。
  /// iOS 参考：拖影图标以手指为中心（不保留抓取点偏移），
  /// 否则抓边缘时拖影落后手指一格，瞄准与悬停判定全部失真。
  void _beginDragVisuals(Offset pos) {
    _grabOffset = const Offset(BoardMetrics.cellW / 2, BoardMetrics.cellH / 2);
    _dragPointerNotifier.value = pos;
    _groupOffsets = _groupOffsetsFor(m.drag);
    _lastPos = null;
  _freezePos = null;
    _lastSentSlot = -9999;
    _lastSentCand = null;
    _lastSentRatio = -1;
    _mergeHiding = false;
  }

  void _onMove(PointerMoveEvent e) {
    if (!widget.active) return;
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;

    if (m.drag != null) {
      _moveDrag(e.localPosition);
      return;
    }
    // iOS 参考（视频 1-2s）：上下文菜单开着时按住不放继续拖 →
    // 菜单收起、进入编辑态、本事件顺势转为拖拽（图标抬手跟手）。
    if (_ctxMenu != null && _downItemId != null && _downPos != null) {
      if ((e.localPosition - _downPos!).distance > 14) {
        final id = _downItemId!;
        _dismissCtxMenu();
        m.enterEdit();
        m.startDrag(id);
        _beginDragVisuals(e.localPosition);
        setState(() {});
        _moveDrag(e.localPosition);
      }
      return;
    }
    if (_swiping) {
      final raw = e.localPosition.dx - _downPos!.dx;
      _swipeDxNotifier.value = _rubber(raw);
      return;
    }
    if (_downPos == null) return;
    final d = e.localPosition - _downPos!;
    // Any clear movement means this is a gesture, not a long press.
    if (d.distance > 12) _cancelLp();
    if (d.dx.abs() > 10 && d.dx.abs() > d.dy.abs() && !m.editing) {
      _swiping = true;
      _swipeDxNotifier.value = _rubber(d.dx);
    } else if (d.distance > 12 && m.editing && _downItemId != null) {
      m.startDrag(_downItemId!);
      // 与长按起拖一致：拖影以手指为中心
      _beginDragVisuals(e.localPosition);
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

    // 菜单开着且没转成拖拽就松手：保持菜单（iOS 习惯），不触发磁贴点击。
    if (_ctxMenu != null) {
      _downPos = null;
      _downItemId = null;
      return;
    }

    if (m.drag != null) {
      _cancelTimers();
      final d = m.drag!;
      // iOS 手感：幽灵从手指位置滑进落点格子。
      // - 插入：滑进孔位；合并/吸入：幽灵「掉进抽屉」——飞向目标格并
      //   缩到 0.45（托盘装进去的手感），落定后托盘收成文件夹磁贴。
      if (!d.frozen && _dragPointerNotifier.value != null) {
        if (!m.dropWillMerge && d.insertIdx >= 0) {
          final postLen = m.pages[d.page].length - d.all.length;
          final base = d.insertIdx.clamp(0, postLen);
          _settle = _SettleAnim(
            entity: d.entity,
            from: _dragPointerNotifier.value! - _grabOffset,
            to: BoardMetrics.xy(base),
          );
        }
      } else if (d.frozen && _dragPointerNotifier.value != null) {
        final targetId = d.mergeTarget?.id ?? d.hoverFolder?.id;
        final idx = targetId == null
            ? -1
            : m.pages[d.page].indexWhere((e) => e.id == targetId);
        if (idx >= 0) {
          _settle = _SettleAnim(
            entity: d.entity,
            from: _dragPointerNotifier.value! - _grabOffset,
            to: BoardMetrics.xy(idx),
            endScale: 0.45,
          );
        }
      }
      // 出环=确认，松手=落定：成夹/吸入只生成板面上的文件夹磁贴
      //（最终形态），不弹开任何面板。
      m.endDrag();
      m.save();
      _dragPointerNotifier.value = null;
      _groupOffsets = {};
      _lastPos = null;
      _freezePos = null;
      _lastSentSlot = -9999;
      _lastSentCand = null;
      _lastSentRatio = -1;
      _mergeHiding = false;
      if (_settle != null) {
        Timer(const Duration(milliseconds: 240), () {
          if (mounted) {
            setState(() => _settle = null);
          }
        });
      }
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
    _ctxMenu = null;
    m.cancelDrag();
    _dragPointerNotifier.value = null;
    _groupOffsets = {};
    _lastPos = null;
  _freezePos = null;
    _lastSentSlot = -9999;
    _lastSentCand = null;
    _lastSentRatio = -1;
    _mergeHiding = false;
    _swiping = false;
    _swipeDxNotifier.value = 0;
    _downPos = null;
    _downItemId = null;
    setState(() {});
  }

  // ---------------- 拖拽 ----------------

  void _moveDrag(Offset pos) {
    final d = m.drag!;
    _dragPointerNotifier.value = pos;

    // 组偏移：抓取时按各自格位相对主项计算
    if (_groupOffsets.isEmpty) _groupOffsets = _groupOffsetsFor(d);

    // 页面局部坐标（主项左上角 = 指针位置 - 抓取点偏移）
    final pageLocal = Offset(pos.dx + (m.cur - d.page) * _pageW, pos.dy);
    final topLeft = pageLocal - _grabOffset;
    final dragRect =
        topLeft & const Size(BoardMetrics.cellW, BoardMetrics.cellH);

    // 重叠判定：按原列表坐标算（静态帧，拖拽中列表不动）。
    // 静态帧手指→目标映射固定，不追尾；合并渲染同样用原位排布，
    // 目标恒在手指下。插入缝另按中心线语义独立计算。
    final arr = m.pages[m.cur];
    const cellArea = BoardMetrics.cellW * BoardMetrics.cellH;
    var bestRatio = 0.0;
    BookmarkEntity? bestEntity;
    for (var i = 0; i < arr.length; i++) {
      final e = arr[i];
      // 跳过自己与组员：自己的原格不是合并/交换候选
      if (e.id == d.id || d.group.any((g) => g.id == e.id)) continue;
      final cell =
          BoardMetrics.xy(i) & const Size(BoardMetrics.cellW, BoardMetrics.cellH);
      final inter = dragRect.intersect(cell);
      if (inter.width <= 0 || inter.height <= 0) continue;
      final ratio = (inter.width * inter.height) / cellArea;
      if (ratio > bestRatio) {
        bestRatio = ratio;
        bestEntity = e;
      }
    }
    // 插入位（中心线语义）：拖到某项中心线左侧 = 插它前面，右侧 = 插它后面。
    // 静态格位换算成展示位（扣除插孔位之前被抽走的成员数），
    // 使挖孔位置与用户眼中的格位一致。与覆盖候选（bestEntity）解耦：
    // 孔位服务插入预览，候选服务停留合并。
    final slotStatic = BoardMetrics.slotFromInsertion(
      topLeft.dx + BoardMetrics.cellW / 2,
      topLeft.dy + BoardMetrics.iconCenterDy,
    );
    var displaySlot = slotStatic;
    for (var i = 0; i < arr.length && i < slotStatic; i++) {
      if (d.all.any((x) => x.id == arr[i].id)) displaySlot--;
    }
    // 先处理移动解冻：冻结后累计位移超 10px 即解冻。
    // 阈值必须对比「冻结那一刻的位置」而不是上一次指针事件——
    // 慢速拖动每次事件只挪 1~3px，用事件间距离永远达不到阈值，
    // 会导致冻结卡死、位置不再计算（用户实测 bug）。
    if (d.frozen &&
        _freezePos != null &&
        (_freezePos! - pos).distance > 10) {
      m.unfreeze();
      _freezePos = null;
      _lastSentSlot = -9999;
      _lastSentCand = null;
      _lastSentRatio = -1;
      _mergeHiding = false;
    }
    // 节流：孔位不变、候选不变、合并显隐不变、比率漂移 <0.05 → 不发 notify。
    // 合并显隐带滞回（≥0.6 进，<0.5 出），手指临界抖动不闪缝。
    final candId = bestEntity?.id;
    final wantHide =
        bestRatio >= 0.6 ? true : (bestRatio < 0.5 ? false : _mergeHiding);
    final hideChanged = wantHide != _mergeHiding;
    final ratioDrift = (bestRatio - _lastSentRatio).abs() > 0.05;
    // 压住候选（wantHide）时挖孔彻底不发：目标格从头到尾不被挤开，
    // 进出合并预览零位移——否则收孔瞬间目标会从被挤开位跳/滑回原位
    //（「离奇错位」的根因）。
    final holeSlot = wantHide ? -1 : displaySlot;
    if (!d.frozen &&
        (holeSlot != _lastSentSlot ||
            hideChanged ||
            (candId != _lastSentCand) ||
            ratioDrift ||
            m.drag?.insertIdx != holeSlot)) {
      m.dragOver(m.cur, holeSlot, bestEntity, bestRatio);
      _lastSentSlot = holeSlot;
      _lastSentCand = candId;
      _lastSentRatio = bestRatio;
      _mergeHiding = wantHide;
    }

    // 停留确认（计时靠"手指静止后不再产生指针事件"触发，每个事件都要
    // 重置）：条目或文件夹候选压住 650ms → 出环确认（预览态）。
    // 按住期间不提前建夹/开夹，松手才落定（成夹弹开 / 吸入文件夹弹开）。
    // 快速滑过不误触发；任何移动都取消计时：必须静止才出环。
    _dwellTimer?.cancel();
    _dwellTimer = Timer(const Duration(milliseconds: 650), () {
      if (m.drag == null) return;
      // 出环即确认（预览态）：按住期间不提前成夹，松手才落定成夹。
      // 记录冻结那一刻的指针位置，供解冻做累计位移对比。
      _freezePos = _lastPos;
      m.freezeOnCandidate();
    });
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
  }

  Offset? _lastPos;
  /// 冻结那一刻的指针位置：解冻阈值按「距冻结点的累计位移」判定
  Offset? _freezePos;
  // 拖拽节流缓存：只有孔位/候选/比率跨阈值变化才调 dragOver（发 notify）。
  int _lastSentSlot = -9999;
  String? _lastSentCand;
  double _lastSentRatio = -1;
  // 合并预览开关（滞回：ratio≥0.6 进，<0.5 出），防缝显隐临界闪烁。
  bool _mergeHiding = false;

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
    _swipeEndDx = _swipeDxNotifier.value;
    final target = _swipeEndDx < -70
        ? m.cur + 1
        : (_swipeEndDx > 70 ? m.cur - 1 : m.cur);
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
    final f = e.asFolder;
    if (f != null) {
      // 文件夹点击始终展开（iOS 风格），编辑态也不例外；改名走面板内点标题。
      _resetInteraction();
      setState(() => _folderStack.add(f));
      return;
    }
    if (m.editing) {
      // iOS 参考：编辑态点击图标不产生任何动作（删除走减号角标，重排走拖拽）。
      return;
    }
    final item = e.asItem!;
    _resetInteraction();
    widget.onOpenUrl(item.url);
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
    if (_ctxMenu != null) {
      _dismissCtxMenu();
      return;
    }
    if (_folderStack.isNotEmpty) {
      setState(() => _folderStack.removeLast());
      return;
    }
    if (m.editing) m.exitEdit();
  }

  // ---------------- 长按上下文菜单（iOS 式） ----------------

  void _dismissCtxMenu() {
    if (_ctxMenu != null && mounted) setState(() => _ctxMenu = null);
  }

  /// 磁贴在屏幕上的全局矩形（板面经 FittedBox 缩放，需按比例换算）。
  Rect _tileGlobalRect(int idx) {
    final rb = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null || !rb.hasSize) return Rect.zero;
    final origin = rb.localToGlobal(Offset.zero);
    final scale = rb.size.width / _pageW;
    final p0 = BoardMetrics.xy(idx);
    return Rect.fromLTWH(origin.dx + p0.dx * scale, origin.dy + p0.dy * scale,
        BoardMetrics.cellW * scale, BoardMetrics.cellH * scale);
  }

  List<Widget> _buildCtxMenuLayer() {
    final ctx = _ctxMenu!;
    final screen = MediaQuery.sizeOf(context);
    const menuW = 218.0;
    const rowH = 44.0;
    final items = <_CtxMenuItem>[
      if (!ctx.entity.isFolder)
        _CtxMenuItem(Icons.open_in_new, '打开', Colors.white, () {
          final url = (ctx.entity.asItem!).url;
          _dismissCtxMenu();
          widget.onOpenUrl(url);
        }),
      if (ctx.entity.isFolder)
        _CtxMenuItem(Icons.folder_open_outlined, '打开', Colors.white, () {
          final f = ctx.entity.asFolder!;
          _dismissCtxMenu();
          _resetInteraction();
          setState(() => _folderStack.add(f));
        }),
      _CtxMenuItem(Icons.edit_outlined, '编辑主屏幕', Colors.white, () {
        _dismissCtxMenu();
        m.enterEdit();
        setState(() {});
      }),
      _CtxMenuItem(Icons.delete_outline, '删除', const Color(0xFFFF453A), () {
        _dismissCtxMenu();
        _askDelete(ctx.entity);
      }),
    ];
    final menuH = items.length * rowH + (items.length - 1) * 0.5 + 10;

    // 锚定磁贴：优先上方，贴顶则放下方；水平收进屏幕。
    final tileRect = _tileGlobalRect(ctx.idx);
    final above = tileRect.top - menuH - 10 >= 8;
    final top = above
        ? (tileRect.top - menuH - 10)
        : (tileRect.bottom + 10);
    final left =
        (tileRect.center.dx - menuW / 2).clamp(10.0, screen.width - menuW - 10);

    return [
      // 挡板：点空白收菜单。长按那根手指的 move 事件按 down 时的命中
      // 结果继续路由回板面 Listener，菜单→拖拽过渡不受挡板影响。
      Positioned.fill(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _dismissCtxMenu(),
          child: const SizedBox.expand(),
        ),
      ),
      Positioned(
        left: left,
        top: top.clamp(8.0, (screen.height - menuH - 8).clamp(8.0, double.infinity)),
        width: menuW,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(
              scale: .72 + .28 * t,
              alignment:
                  above ? Alignment.bottomCenter : Alignment.topCenter,
              child: child,
            ),
          ),
          child: _CtxMenuCard(items: items),
        ),
      ),
    ];
  }

  // ---------------- 文件夹拖出交接 ----------------

  /// 条目越出面板边界：面板立收、文件夹不足两项会自动解散，
  /// 拖拽移交首页板继续跟手（iOS 手感）。
  void _handleFolderDragOut(BookmarkEntity child) {
    // 交接必须知道源文件夹：栈空（面板已被系统返回/重置收掉）且无
    // 交接缓存时直接放弃本次拖出，避免 _folderStack.last 抛 StateError。
    final parent = _folderStack.isNotEmpty ? _folderStack.last : _handoffFolder;
    if (parent == null) return;
    m.dragOutFromFolder(parent.id, child);
    m.save();
    _handoffFolder = parent;
    _folderDragHandoff = true;
    m.startDrag(child.id);
    // 与长按起拖一致：幽灵以手指为中心，节流缓存复位。
    _grabOffset = const Offset(BoardMetrics.cellW / 2, BoardMetrics.cellH / 2);
    _groupOffsets = _groupOffsetsFor(m.drag);
    _lastSentSlot = -9999;
    _lastSentCand = null;
    _lastSentRatio = -1;
    _mergeHiding = false;
    _lastPos = null;
  _freezePos = null;
    setState(() {});
  }

  /// 交接期间 Draggable 的位置流 → 首页板局部坐标 → 走同一套拖拽状态机。
  void _handleFolderDragMoved(Offset global) {
    if (!_folderDragHandoff || m.drag == null) return;
    final rb = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null) return;
    _moveDrag(rb.globalToLocal(global));
  }

  /// 交接结束（松手/取消）：按首页板规则落位（交换/合并/吸回）。
  void _handleFolderDragFinished() {
    if (!_folderDragHandoff) return;
    _folderDragHandoff = false;
    _handoffFolder = null;
    // 文件夹已解散，栈里的引用是僵尸对象，必须清掉，否则面板会复显示
    _folderStack.clear();
    _cancelTimers();
    if (m.drag != null) {
      // 成夹/吸入不自动弹开：新夹以磁贴形态留在板面（最终形态）。
      m.endDrag();
      m.save();
    }
    _dragPointerNotifier.value = null;
    _groupOffsets = {};
    _lastPos = null;
  _freezePos = null;
    _lastSentSlot = -9999;
    _lastSentCand = null;
    _lastSentRatio = -1;
    _mergeHiding = false;
    setState(() {});
  }

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _folderStack.isEmpty && !m.editing && _ctxMenu == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismissTransientSurface();
      },
      child: ListenableBuilder(
        listenable: m,
        builder: (context, _) {
          final browser = context.browserTokens;
          // 编辑态共享抖动：整页一个 ticker；文件夹全屏面板/交接期板面
          // 被盖住时暂停，避免背后空转逐帧驱动磨砂重采样。
          if (m.editing && _folderStack.isEmpty && !_folderDragHandoff) {
            if (!_jiggleCtrl.isAnimating) _jiggleCtrl.repeat();
          } else if (_jiggleCtrl.isAnimating) {
            _jiggleCtrl.stop();
          }
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
                              engineIndex:
                                  m.settings.searchEngineIndex.clamp(0, 3),
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
                        // 文件夹展开层：常驻挂载，push/pop 都有缩放+淡入动画。
                        // 拖出交接期间面板收起但 FolderPage 保持挂载（Offstage），
                        // 让进行中的 Draggable 手势存活，拖拽无缝移交首页板。
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: _folderStack.isEmpty &&
                                !_folderDragHandoff,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(
                                opacity: anim,
                                child: ScaleTransition(
                                  scale: Tween(begin: .72, end: 1.0)
                                      .animate(anim),
                                  child: child,
                                ),
                              ),
                              child: (_folderStack.isEmpty &&
                                      !_folderDragHandoff)
                                  ? const SizedBox.shrink(
                                      key: ValueKey('folder-stack-empty'))
                                  : Offstage(
                                      offstage: _folderDragHandoff,
                                      child: FolderPage(
                                        key: ValueKey(_folderStack.length),
                                        folder: _folderStack.isEmpty
                                            ? _handoffFolder!
                                            : _folderStack.last,
                                        onBack: () => setState(
                                            () => _folderStack.removeLast()),
                                        onOpenFolder: (f) => setState(
                                            () => _folderStack.add(f)),
                                        onRename: (name) {
                                          final target = _folderStack.last;
                                          m.renameFolder(target.id, name);
                                          m.save();
                                          // 栈里的实例要换成本轮替换后的新对象
                                          setState(() {
                                            for (var i = 0;
                                                i < _folderStack.length;
                                                i++) {
                                              final nf = m
                                                  .findById(_folderStack[i].id)
                                                  ?.asFolder;
                                              if (nf != null) {
                                                _folderStack[i] = nf;
                                              }
                                            }
                                          });
                                        },
                                        onOpenItem: (item) {
                                          setState(
                                              () => _folderStack.clear());
                                          widget.onOpenUrl(item.url);
                                        },
                                        onReorder: (child, targetIdx) {
                                          final parent = _folderStack.last;
                                          m.reorderInFolder(
                                              parent.id, child, targetIdx);
                                          m.save();
                                          // children 原地变更；换新实例触发面板刷新
                                          setState(() {
                                            for (var i = 0;
                                                i < _folderStack.length;
                                                i++) {
                                              final nf = m
                                                  .findById(
                                                      _folderStack[i].id)
                                                  ?.asFolder;
                                              if (nf != null) {
                                                _folderStack[i] = nf;
                                              }
                                            }
                                          });
                                        },
                                        onDragOutItem: _handleFolderDragOut,
                                        onDragMoved: _handleFolderDragMoved,
                                        onDragFinished:
                                            _handleFolderDragFinished,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        // 长按上下文菜单：挡板 + 锚定磁贴的磨砂菜单，
                        // 按住拖动 → 菜单收起、编辑态顺势拖拽（见 _onMove）。
                        if (_ctxMenu != null) ..._buildCtxMenuLayer(),
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
    // iOS Safari 起始页模式：一览 chip 在最前，后面跟着所有已打开的网页标签，
    // 点任意 chip 即刻切换到浏览器对应的标签页。
    return BrowserTabStrip(
      scrollable: true,
      // 新建标签不再产生空白页：聚焦主页地址栏，输入网址或点书签后才建标签。
      onNewTab: _openSearch,
      chips: [
        const BrowserTabChip(label: '一览', selected: true, width: 116),
        for (var i = 0; i < widget.tabSummaries.length; i++)
          BrowserTabChip(
            label: widget.tabSummaries[i].title,
            selected: false,
            private: widget.tabSummaries[i].private,
            faviconUrl: widget.tabSummaries[i].faviconUrl,
            width: 116,
            onTap: () => widget.onSelectBrowserTab?.call(i),
          ),
      ],
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
          badge: widget.tabSummaries.isEmpty
              ? null
              : '${widget.tabSummaries.length}',
        ),
      ],
    );
  }

  void _showBrowserPanel() {
    showBrowserMenuSheet(context, categories: [
      BrowserMenuCategory(
        icon: Icons.history,
        title: '浏览数据',
        subtitle: '历史记录、阅读清单',
        actions: [
          menuTile(context, icon: Icons.history, title: '历史记录', onTap: () {
            Navigator.pop(context);
            (widget.onOpenHistory ?? widget.onOpenBrowser)();
          }),
          menuTile(context,
              icon: Icons.chrome_reader_mode_outlined, title: '阅读清单',
              onTap: () {
            Navigator.pop(context);
            (widget.onOpenReadingList ?? widget.onOpenBrowser)();
          }),
        ],
      ),
      BrowserMenuCategory(
        icon: Icons.settings_outlined,
        title: '设置',
        subtitle: '搜索引擎、无痕浏览、外观',
        actions: [
          menuTile(context, icon: Icons.settings_outlined, title: '打开设置',
              onTap: () {
            Navigator.pop(context);
            (widget.onOpenSettings ?? _openSettingsSheet).call();
          }),
        ],
      ),
    ]);
  }

  Widget _buildHeader() {
    // Vivaldi 式文件夹文字 tab：首页 + 顶层文件夹，下划线标记激活项
    final scheme = Theme.of(context).colorScheme;
    final folders = [
      for (final e in m.topLevel())
        if (e.isFolder) e.asFolder!,
    ];
    Widget tab(String label, {required bool active, VoidCallback? onTap}) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? AppColors.brand : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.brandStrong : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  tab(
                    '首页',
                    active: _folderStack.isEmpty,
                    onTap: () {
                      if (_folderStack.isNotEmpty) {
                        setState(() => _folderStack.clear());
                      }
                    },
                  ),
                  for (final f in folders)
                    tab(
                      f.name,
                      active:
                          _folderStack.isNotEmpty && _folderStack.last.id == f.id,
                      onTap: () => setState(() {
                        _folderStack
                          ..clear()
                          ..add(f);
                      }),
                    ),
                ],
              ),
            ),
          ),
          if (m.editing)
            // iOS 参考：编辑态右上角为文字「完成」，点击退出编辑。
            TextButton(
              onPressed: m.exitEdit,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brand,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(48, 40),
              ),
              child: const Text('完成',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            )
          else
            IconButton(
              tooltip: '更多浏览器操作',
              onPressed: _showBrowserPanel,
              icon: const Icon(Icons.more_horiz, size: 22),
            ),
        ],
      ),
    );
  }

  Widget _buildBoard() {
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
                key: _boardKey,
                children: [
                  // 页面行（含翻页滑动；位移走 ValueNotifier，避免逐帧整页重建）
                  ValueListenableBuilder<double>(
                    valueListenable: _swipeDxNotifier,
                    builder: (context, swipeDx, _) => Transform.translate(
                      offset: Offset(-m.cur * _pageW + swipeDx, 0),
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
                                  child: RepaintBoundary(
                                    child: _buildPage(p),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 拖拽浮层：只有 ghost 层随指针重建
                  ValueListenableBuilder<Offset?>(
                    valueListenable: _dragPointerNotifier,
                    builder: (context, pointer, _) {
                      final d = m.drag;
                      if (d == null && _settle == null) {
                        return const SizedBox.shrink();
                      }
                      if (d == null) {
                        // 松手落位动画：幽灵滑进落点格
                        final s = _settle!;
                        return TweenAnimationBuilder<Offset>(
                          tween: Tween(begin: s.from, end: s.to),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          builder: (context, tl, child) => Positioned(
                            left: tl.dx,
                            top: tl.dy,
                            width: BoardMetrics.cellW,
                            height: BoardMetrics.cellH,
                            child: child!,
                          ),
                          child: _DragGhost(
                            entity: s.entity,
                            endScale: s.endScale,
                          ),
                        );
                      }
                      if (pointer == null) {
                        return const SizedBox.shrink();
                      }
                      // 拖出交接期：拖影由文件夹 Draggable 的 feedback
                      // （root Overlay，Offstage 隐藏不掉）继续跟手，
                      // 板面 ghost 不再叠加，否则出现双重拖影——
                      // 板面 ghost 还带板面坐标偏移，浮在手指上方，
                      // 看起来像「目标缩小了一圈」。
                      if (_folderDragHandoff) {
                        return const SizedBox.shrink();
                      }
                      return Stack(
                        children: [
                          ..._buildDragOverlay(d, pointer),
                        ],
                      );
                    },
                  ),
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
    final d = m.drag;
    final isDragPage = d != null && p == m.cur;
    // iOS 式两种预览（列表本身拖拽中不动，全是视觉层）：
    // - 合并预览（正压/冻结）：原位排布，拖拽成员老位置留透明缝，
    //   其余不动，目标恒在手指下；快松弹回原位，停留 650ms 合并/吸入。
    // - 插入预览（偏边）：原格合拢，插入位留透明缝（露底，不画白块），
    //   图标滑动让位，松手占格。
    // _mergeHiding 带滞回（≥0.6 进，<0.5 出），防临界闪烁。
    final mergeView = d != null &&
        p == d.page &&
        (d.frozen || _mergeHiding);
    if (mergeView) {
      return Stack(
        children: [
          for (var i = 0; i < page.length; i++)
            page[i].id == d.id || d.group.any((g) => g.id == page[i].id)
                ? _originGap(page[i], i)
                : _tileAt(page[i], i, p,
                    // 合并确认目标不做让位滑动：出环瞬间原位钉住（用户要求
                    // 目标位置零变动，环从外层附着）；邻格保持 180ms 滑动。
                    snap: d.mergeTarget?.id == page[i].id ||
                        d.hoverFolder?.id == page[i].id),
        ],
      );
    }
    final showHole = isDragPage && !d.frozen;
    final members =
        d == null ? <String>{} : d.all.map((x) => x.id).toSet();
    final display = <BookmarkEntity?>[];
    if (d != null) {
      var k = 0;
      for (final e in page) {
        if (members.contains(e.id)) continue;
        if (showHole && k == d.insertIdx) display.add(null);
        display.add(e);
        k++;
      }
      if (showHole && d.insertIdx >= k) display.add(null);
    } else {
      display.addAll(page);
    }
    return Stack(
      children: [
        for (var i = 0; i < display.length; i++)
          display[i] == null ? _holeTile(i) : _tileAt(display[i]!, i, p),
      ],
    );
  }

  /// 原位透明缝：合并预览时拖拽成员老位置只撑布局（露底），
  /// 其余格子按原位排布，目标恒在手指下。Animated 保证与插入缝切换时滑动过渡。
  Widget _originGap(BookmarkEntity e, int idx) {
    final pos = BoardMetrics.xy(idx);
    return AnimatedPositioned(
      key: ValueKey('origin-gap-${e.id}'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      left: pos.dx,
      top: pos.dy,
      width: BoardMetrics.cellW,
      height: BoardMetrics.cellH,
      child: const SizedBox.shrink(),
    );
  }

  /// 插入缝：透明占位，只撑开布局让图标滑动让位，不画任何白块，
  /// 缝里露出板底（iOS 式）。一路 AnimatedPositioned 滑行动画；
  /// 高频节流保证只在孔位变化时重建，不会每帧重启。
  Widget _holeTile(int displayIdx) {
    final pos = BoardMetrics.xy(displayIdx);
    return AnimatedPositioned(
      key: const ValueKey('drag-hole'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      left: pos.dx,
      top: pos.dy,
      width: BoardMetrics.cellW,
      height: BoardMetrics.cellH,
      child: const SizedBox.shrink(),
    );
  }

  Widget _tileAt(BookmarkEntity e, int idx, int pageIdx,
      {bool snap = false}) {
    final pos = BoardMetrics.xy(idx);
    final d = m.drag;
    final isDragMember = d != null && d.all.any((x) => x.id == e.id);
    final isMergeTarget =
        d?.mergeTarget?.id == e.id || d?.hoverFolder?.id == e.id;
    final body = Opacity(
      // 落位滑入动画期间隐藏落点磁贴，动画结束后显现（与幽灵无缝衔接）
      opacity: _settle?.entity.id == e.id ? 0 : 1,
      child: BookmarkTile(
        entity: e,
        faded: isDragMember,
        // 只抖当前页：非可见页挂起的磁贴不跑动画（编辑态最多省 3/4 ticker 负载）
        // 抽屉不抖：合并确认目标关掉 jiggle（托盘钉死感）
        jiggling:
            m.editing && !isDragMember && pageIdx == m.cur && !isMergeTarget,
        jiggle: _jiggleCtrl,
        // iOS 参考：编辑态每个磁贴左上角显示减号徽章，点击弹确认删除。
        onDelete: m.editing ? () => _askDelete(e) : null,
        // 合并/吸入确认：托盘 + 目标缩入（松手才真正落定）。
        merged: isMergeTarget,
      ),
    );
    // 一路滑动让位（iOS 味）；节流保证只在孔位变化时重建，
    // Animated 不会被高频指针事件重启。
    return AnimatedPositioned(
      key: ValueKey('tile-${e.id}'),
      // snap：合并确认目标原位钉住，不做让位滑动动画
      duration: snap ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      left: pos.dx,
      top: pos.dy,
      width: BoardMetrics.cellW,
      height: BoardMetrics.cellH,
      child: body,
    );
  }

  List<Widget> _buildDragOverlay(DragInfo d, Offset ptr) {
    // iOS 参考：合并悬停时幽灵保持可见，压在目标格上方（不隐藏、不变身）。
    final topLeft = ptr - _grabOffset;
    final widgets = <Widget>[
      Positioned(
        left: topLeft.dx,
        top: topLeft.dy,
        width: BoardMetrics.cellW,
        height: BoardMetrics.cellH,
        child:
            _DragGhost(entity: d.entity),
      ),
      for (final g in d.group)
        Positioned(
          left: topLeft.dx + (_groupOffsets[g.id]?.dx ?? 0),
          top: topLeft.dy + (_groupOffsets[g.id]?.dy ?? 0),
          width: BoardMetrics.cellW,
          height: BoardMetrics.cellH,
          child: _DragGhost(entity: g),
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
      _folderStack.clear();
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

/// 松手落位动画数据。
class _SettleAnim {
  const _SettleAnim({
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

/// 上下文菜单项。
class _CtxMenuItem {
  const _CtxMenuItem(this.icon, this.label, this.color, this.onTap);

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// iOS 式深色磨砂上下文菜单卡片。
class _CtxMenuCard extends StatelessWidget {
  const _CtxMenuCard({required this.items});

  final List<_CtxMenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xE6242426),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: Colors.white.withValues(alpha: .08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Container(
                      height: 0.5,
                      margin: const EdgeInsets.symmetric(horizontal: 15),
                      color: Colors.white24,
                    ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: items[i].onTap,
                    child: SizedBox(
                      height: 44,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(items[i].icon, size: 18, color: items[i].color),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                items[i].label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: items[i].color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 拖拽中的磁贴（放大 + 投影）
class _DragGhost extends StatelessWidget {
  const _DragGhost({required this.entity, this.endScale});

  final BookmarkEntity entity;

  /// 松手落位终态缩放（null = 保持 1.22 抬起尺寸）；
  /// 合并掉入托盘时由 _SettleAnim 传入 0.45。
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
