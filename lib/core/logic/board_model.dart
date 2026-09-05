/// 书签状态机：重排 / 合并 / 吸入 / 组拖 / 翻页 / 选择 / 编辑
///
/// 纯 Dart（不依赖 Flutter），逻辑与 HTML 原型逐条对齐，便于 `flutter test` 回归。
library;

import 'package:flutter/foundation.dart';

import '../models/bookmark.dart';
import '../storage/bookmark_codec.dart';
import '../storage/bookmark_store.dart';
import 'search_engines.dart';

/// 最大页数（防无限翻页拖出新页）
const int maxPages = 4;
const int pageCapacity = 20;

/// 拖拽进行中的状态
class DragInfo {
  DragInfo({required this.entity, required this.id, required this.page});

  final BookmarkEntity entity;
  final String id;

  /// 被整组搬运的其它选中项（不含主项），限同页
  final List<BookmarkEntity> group = [];

  int page;
  BookmarkEntity? lastDisplaced;

  /// 当前悬停候选（重叠面积最大的格子实体）与其重叠比例。
  /// 冻结合并只对"重叠足够大且指针静止停留"的候选生效。
  BookmarkEntity? candidate;
  double candidateRatio = 0;

  /// iOS 挖孔插入位（展示序列中的下标，含末尾空位；-1 = 无孔）。
  /// 拖拽期间其余格子按此让位重排，松手时拖拽项直接落进该格。
  int insertIdx = -1;

  BookmarkEntity? hoverFolder;
  BookmarkEntity? mergeTarget;
  bool frozen = false;

  List<BookmarkEntity> get all => [entity, ...group];
}

/// 设置项（P1 为本地开关，P2 接真逻辑）
class Settings {
  int searchEngineIndex = 1;

  /// 无痕模式下的搜索引擎（与常规模式独立）。
  int privateSearchEngineIndex = 3;
  bool adBlock = true;
  bool incognito = false;
  bool sync = false;
  bool darkMode = false;
  bool hintSeen = false;

  /// 地址栏建议开关：关掉的来源不再出现在下拉里。
  bool suggestRecent = true;
  bool suggestBookmarks = true;
  bool suggestHistory = true;
  bool suggestTabs = true;

  /// 输入时向搜索引擎拉取实时建议词。
  bool suggestRemote = true;

  /// 冷启动时恢复上次退出前的标签页集合。
  bool restoreSession = true;

  /// 全部标签页以桌面版 UA 请求网页。
  bool desktopUA = false;

  /// 首页背景：`home_backgrounds.dart` 预设列表的索引。
  int homeBackground = 0;

  /// 首页自定义背景图片路径（仅当背景预设为「自定义图片」时使用）。
  String? homeBackgroundPath;

  static const List<String> engines = SearchEngines.names;

  Map<String, Object?> toJson() => {
        'se': searchEngineIndex,
        'pse': privateSearchEngineIndex,
        'ad': adBlock,
        'priv': incognito,
        'sync': sync,
        'dark': darkMode,
        'hint': hintSeen,
        'srs': suggestRecent,
        'sbm': suggestBookmarks,
        'shs': suggestHistory,
        'stb': suggestTabs,
        'srm': suggestRemote,
        'rse': restoreSession,
        'dua': desktopUA,
        'hbg': homeBackground,
        'hbgp': homeBackgroundPath,
      };

  factory Settings.fromJson(Map<String, Object?> j) => Settings()
    ..searchEngineIndex = (j['se'] as num?)?.toInt() ?? 1
    ..privateSearchEngineIndex = (j['pse'] as num?)?.toInt() ?? 3
    ..adBlock = (j['ad'] as bool?) ?? true
    ..incognito = (j['priv'] as bool?) ?? false
    ..sync = (j['sync'] as bool?) ?? false
    ..darkMode = (j['dark'] as bool?) ?? false
    ..hintSeen = (j['hint'] as bool?) ?? false
    ..suggestRecent = (j['srs'] as bool?) ?? true
    ..suggestBookmarks = (j['sbm'] as bool?) ?? true
    ..suggestHistory = (j['shs'] as bool?) ?? true
    ..suggestTabs = (j['stb'] as bool?) ?? true
    ..suggestRemote = (j['srm'] as bool?) ?? true
    ..restoreSession = (j['rse'] as bool?) ?? true
    ..desktopUA = (j['dua'] as bool?) ?? false
    ..homeBackground = (j['hbg'] as num?)?.toInt() ?? 0
    ..homeBackgroundPath = j['hbgp'] as String?;

  Settings({
    this.searchEngineIndex = 1,
    this.privateSearchEngineIndex = 3,
    this.adBlock = true,
    this.incognito = false,
    this.sync = false,
    this.darkMode = false,
    this.hintSeen = false,
    this.suggestRecent = true,
    this.suggestBookmarks = true,
    this.suggestHistory = true,
    this.suggestTabs = true,
    this.suggestRemote = true,
    this.restoreSession = true,
    this.desktopUA = false,
    this.homeBackground = 0,
    this.homeBackgroundPath,
  });
}

/// 书签状态机
class BoardModel extends ChangeNotifier {
  BoardModel({required BookmarkStore store, List<BookmarkPage>? seed})
      : _store = store,
        pages = seed ?? _seedData();

  final BookmarkStore _store;
  List<BookmarkPage> pages;
  Settings settings = Settings();
  int cur = 0;
  bool editing = false;
  final Set<String> selection = {};
  DragInfo? drag;
  int _idc = 1000;

  String _nextId() => 'i${_idc++}';

  // ---------- 查找 ----------

  BookmarkEntity? findById(String id) {
    BookmarkEntity? scan(List<BookmarkEntity> list) {
      for (final e in list) {
        if (e.id == id) return e;
        final f = e.asFolder;
        if (f != null) {
          final r = scan(f.children);
          if (r != null) return r;
        }
      }
      return null;
    }

    for (final page in pages) {
      final r = scan(page);
      if (r != null) return r;
    }
    return null;
  }

  /// 找到 id 所在的那一层列表（可能是某文件夹的 children）。
  List<BookmarkEntity>? _listContaining(String id) {
    List<BookmarkEntity>? scan(List<BookmarkEntity> list) {
      for (final e in list) {
        if (e.id == id) return list;
        final f = e.asFolder;
        if (f != null) {
          final r = scan(f.children);
          if (r != null) return r;
        }
      }
      return null;
    }

    for (final page in pages) {
      final r = scan(page);
      if (r != null) return r;
    }
    return null;
  }

  int pageOf(String id) {
    for (var p = 0; p < pages.length; p++) {
      if (pages[p].any((e) => e.id == id)) return p;
    }
    return 0;
  }

  /// 顶层实体列表（文件夹内的不算顶层）
  List<BookmarkEntity> topLevel() => [for (final p in pages) ...p];

  int countItems() => topLevel().fold(
      0, (sum, e) => sum + (e.isFolder ? e.asFolder!.children.length : 1));

  // ---------- 编辑 / 多选 ----------

  void enterEdit() {
    if (editing) return;
    editing = true;
    notifyListeners();
  }

  void exitEdit() {
    cancelDrag();
    editing = false;
    selection.clear();
    notifyListeners();
  }

  void toggleSelect(String id) {
    if (!selection.add(id)) selection.remove(id);
    notifyListeners();
  }

  // ---------- 拖拽核心（与原型逐条对齐） ----------

  /// 长按起拖：编辑态拖选中项 → 整组
  void startDrag(String id) {
    final e = findById(id);
    if (e == null) return;
    final p = pageOf(id);
    final d = DragInfo(entity: e, id: id, page: p);
    if (editing && selection.contains(id) && selection.length > 1) {
      final members = selection
          .where((mid) => mid != id)
          .map(findById)
          .whereType<BookmarkEntity>();
      d.group.addAll(members.where((m) => pageOf(m.id) == p));
    }
    drag = d;
    notifyListeners();
  }

  /// 拖拽移动：插入让位重排，并记录被挤开的项
  void dragTo(int page, int slotIdx) {
    final d = drag;
    if (d == null || d.frozen) return;
    final arr = pages[page];
    final from = arr.indexOf(d.entity);
    if (from < 0) return;
    final t = slotIdx.clamp(0, arr.length - 1);
    if (t == from) return;
    arr.removeAt(from);
    arr.insert(t, d.entity);
    final displaced = t > from ? arr[t - 1] : arr[t + 1];
    d.lastDisplaced =
        (displaced.id != d.id && !d.group.any((g) => g.id == displaced.id))
            ? displaced
            : null;
    notifyListeners();
  }

  /// 拖拽悬停判定（UI 层驱动），iOS 插入式语义：
  /// - [slotIdx] = 挖孔插入位（几何格位）：拖拽期间其余格子按它让位重排，
  ///   拖拽项松手后直接落进该格；
  /// - [target]/[ratio] = 覆盖候选，供静止停留 650ms（freezeOnCandidate）
  ///   触发合并 / 移入文件夹使用。
  /// 拖拽过程不改动列表本身（渲染层按 insertIdx 让位展示）。
  void dragOver(int page, int slotIdx, BookmarkEntity? target, double ratio) {
    final d = drag;
    if (d == null || d.frozen) return;
    final sameSlot = d.page == page && d.insertIdx == slotIdx;
    final sameTarget = identical(d.candidate, target) ||
        (d.candidate?.id == target?.id);
    // 高频指针事件去重：槽位与候选都没变时，比率只服务停留冻结阈值
    // （freezeOnCandidate / dropWillMerge 读 candidateRatio），不参与渲染
    // → 静默更新不发 notify。慢速跨格时比率连续漂移，若每次都 notify
    // 会触发整板重建风暴（UI 线程杀手）。
    if (sameSlot && sameTarget) {
      d.candidateRatio = ratio;
      return;
    }
    d.page = page;
    d.insertIdx = slotIdx;
    // 排除自己与组员：拖过自己的原格不算候选
    if (target != null &&
        target.id != d.id &&
        !d.group.any((g) => g.id == target.id)) {
      d.candidate = target;
      d.candidateRatio = ratio;
    } else {
      d.candidate = null;
      d.candidateRatio = 0;
    }
    // 挖孔插入预览需要板面随 insertIdx 重建
    notifyListeners();
  }

  /// 指针静止停留（页面层计时）后调用：只有当前候选重叠 ≥ 0.6（真正
  /// 压在图标上，而非压在间隙/边缘）才冻结。
  /// 冻结后：候选是文件夹 → 吸入（松手移入文件夹）；是条目 → 合并建夹。
  void freezeOnCandidate() {
    final d = drag;
    if (d == null || d.frozen) return;
    final c = d.candidate;
    // 防自合并：候选是自己 → 不冻结（否则会建出含同一项两次的文件夹）
    if (c == null || c.id == d.id || d.candidateRatio < 0.6) return;
    final arr = pages[d.page];
    if (!arr.contains(c) || d.group.any((g) => g.id == c.id)) return;
    d.hoverFolder = c.isFolder ? c : null;
    d.mergeTarget = c.isFolder ? null : c;
    d.frozen = true;
    // iOS：进入合并/吸入预览时挖孔收起，焦点让给合成预览
    d.insertIdx = -1;
    notifyListeners();
  }

  /// 停留 350ms：冻结重排，选定合并/吸入目标（旧路径，测试兼容）。
  /// 邻位优先文件夹（落在文件夹原位时它就在 idx±1），否则用被挤开的项
  void freezeDwell() {
    final d = drag;
    if (d == null) return;
    final arr = pages[d.page];
    final idx = arr.indexOf(d.entity);
    BookmarkEntity? cand;
    if (idx >= 0) {
      final left = idx > 0 ? arr[idx - 1] : null;
      final right = idx < arr.length - 1 ? arr[idx + 1] : null;
      final nearFolder = (left != null && left.isFolder)
          ? left
          : (right != null && right.isFolder ? right : null);
      cand = nearFolder ?? d.lastDisplaced;
    } else {
      cand = d.lastDisplaced;
    }
    if (cand == null) return;
    final c = cand;
    if (!arr.contains(c) || d.group.any((g) => g.id == c.id)) return;
    d.hoverFolder = c.isFolder ? c : null;
    d.mergeTarget = c.isFolder ? null : c;
    d.frozen = true;
    notifyListeners();
  }

  void unfreeze() {
    final d = drag;
    if (d == null) return;
    d.frozen = false;
    d.hoverFolder = null;
    d.mergeTarget = null;
    notifyListeners();
  }

  /// 落夹成夹判定（iOS 习惯）：未冻结、压在某条目上（candidateRatio ≥ 0.6）
  /// 就地成夹并弹开；只有落在间隙/边缘（ratio < 0.6）才按孔位插入。
  /// 候选是文件夹时同样走吸入（与快掠吸入一致）。
  bool get dropWillMerge {
    final d = drag;
    if (d == null || d.frozen) return false;
    final c = d.candidate;
    if (c == null || d.candidateRatio < 0.6) return false;
    if (c.id == d.id || d.group.any((g) => g.id == c.id)) return false;
    return pages[d.page].contains(c);
  }

  /// 松手：合并 / 吸入 / 整块落位。
  /// 返回新建的合并夹或被吸入的文件夹（供调用方感知结果）；
  /// UI 不再自动弹开——夹以磁贴形态留在板面（最终形态）。
  /// 其余情况返回 null。
  BookmarkFolder? endDrag() {
    final d = drag;
    if (d == null) return null;
    final arr = pages[d.page];
    // 翻页后旧目标作废
    if (d.hoverFolder != null && !arr.contains(d.hoverFolder)) {
      d.hoverFolder = null;
    }
    if (d.mergeTarget != null && !arr.contains(d.mergeTarget)) {
      d.mergeTarget = null;
    }

    // 快速掠过文件夹直接松手：当场吸入文件夹末尾并弹开（iOS 习惯）。
    if (!d.frozen &&
        d.candidate != null &&
        d.candidate!.isFolder &&
        d.candidateRatio >= 0.6) {
      final f = findById(d.candidate!.id)?.asFolder;
      if (f != null &&
          arr.contains(f) &&
          !d.all.any((e) => e.id == f.id)) {
        _pullOut(arr, d.all);
        f.children.addAll(d.all);
        selection.removeAll(d.all.map((e) => e.id));
        d.candidate = null;
        d.candidateRatio = 0;
        drag = null;
        _autoDissolveFolders();
        notifyListeners();
        return findById(f.id)?.asFolder;
      }
    }

    // 落夹成夹（iOS 习惯）：压在条目上松手（无论是否停留冻结）就地成夹
    // 并弹开；只有落在间隙/边缘才按孔位插入。
    if (dropWillMerge) {
      return _mergeWith(d.candidate!);
    }

    if (d.hoverFolder != null) {
      final f = d.hoverFolder!;
      // 防自吸入：目标文件夹就是拖拽项自己 → 作废
      if (d.all.any((e) => e.id == f.id)) {
        d.hoverFolder = null;
      } else {
        _pullOut(arr, d.all);
        f.asFolder!.children.addAll(d.all);
        selection.removeAll(d.all.map((e) => e.id));
        drag = null;
        _autoDissolveFolders();
        notifyListeners();
        // 解散后查无此夹则返回 null（调用方不弹开）。
        return findById(f.id)?.asFolder;
      }
    }

    if (d.mergeTarget != null && d.mergeTarget!.id != d.id) {
      return _mergeWith(d.mergeTarget!);
    }

    // iOS 插入式落位：insertIdx 已是"展示序列中的孔位"（UI 层已扣除
    // 被抽走成员的偏移），直接按孔位插入，与挖孔预览完全一致。
    // 冻结合并 / 吸入在上方分支已 return。
    // insertIdx < 0（手指未产生有效移动）→ 原位落回。
    final arr0 = pages[d.page];
    final originIdx = arr0.indexOf(d.entity);
    arr0.removeWhere((e) => d.all.any((x) => x.id == e.id));
    final raw = d.insertIdx < 0 ? originIdx : d.insertIdx;
    final base = raw.clamp(0, arr0.length);
    arr0.insert(base, d.entity);
    for (var i = 0; i < d.group.length; i++) {
      arr0.insert(base + 1 + i, d.group[i]);
    }
    d.candidate = null;
    d.candidateRatio = 0;
    d.insertIdx = -1;
    selection.clear();
    drag = null;
    notifyListeners();
    return null;
  }

  /// 与 [target] 条目合成新文件夹：children=[target, ...拖拽成员]，
  /// 文件夹落在目标抽走拖拽成员后的压缩位（目标视觉位不动），
  /// 拖拽结束（松手落定成夹）。
  BookmarkFolder? _mergeWith(BookmarkEntity target) {
    final d = drag;
    if (d == null) return null;
    final arr = pages[d.page];
    if (target.id == d.id || d.group.any((g) => g.id == target.id)) {
      return null;
    }
    if (!arr.contains(target)) return null;
    final mtIdx = arr.indexOf(target);
    // 文件夹应落在目标项的视觉位置：先数清 mtIdx 之前除拖拽成员外
    // 还保留几项（抽走成员会让后续下标左移）
    final keptBefore = arr
        .take(mtIdx)
        .where((e) => !d.all.any((x) => x.id == e.id))
        .length;
    arr.removeAt(mtIdx);
    _pullOut(arr, d.all);
    final folder = BookmarkFolder(
        id: _nextId(), name: '新文件夹', children: [target, ...d.all]);
    final folderId = folder.id;
    arr.insert(keptBefore.clamp(0, arr.length), folder);
    selection.removeAll(d.all.map((e) => e.id));
    d.candidate = null;
    d.candidateRatio = 0;
    d.hoverFolder = null;
    d.mergeTarget = null;
    d.insertIdx = -1;
    selection.clear();
    drag = null;
    _autoDissolveFolders();
    notifyListeners();
    return findById(folderId)?.asFolder;
  }

  void cancelDrag() {
    drag = null;
    notifyListeners();
  }

  /// 文件夹内容少于 2 项时自动解散（iOS 习惯）：
  /// 子项提回到文件夹所在位置，文件夹本身消失。含嵌套文件夹递归处理。
  void _autoDissolveFolders() {
    bool dissolve(List<BookmarkEntity> list) {
      var did = false;
      for (var i = list.length - 1; i >= 0; i--) {
        final f = list[i].asFolder;
        if (f == null) continue;
        // 先处理嵌套层
        if (dissolve(f.children)) did = true;
        if (f.children.length < 2) {
          list.removeAt(i);
          list.insertAll(i.clamp(0, list.length), f.children);
          did = true;
        }
      }
      return did;
    }

    var changed = false;
    for (final p in pages) {
      if (dissolve(p)) changed = true;
    }
    if (changed) notifyListeners();
  }

  // ---------- 文件夹内拖拽（重排 / 拖出到上级） ----------

  /// 文件夹内重排：把 [child] 移到当前列表的 [targetIdx] 位置（iOS 让位语义）。
  void reorderInFolder(String folderId, BookmarkEntity child, int targetIdx) {
    final f = findById(folderId)?.asFolder;
    if (f == null) return;
    final cur = f.children.indexWhere((e) => e.id == child.id);
    if (cur < 0) return;
    if (targetIdx < 0 || targetIdx >= f.children.length || cur == targetIdx) {
      return;
    }
    f.children.removeAt(cur);
    var t = targetIdx;
    if (t > cur) t -= 1;
    f.children.insert(t.clamp(0, f.children.length), child);
    notifyListeners();
  }

  /// 把文件夹里的 [child] 拖出：落到文件夹所在层的下一个位置，并从文件夹移除。
  void dragOutFromFolder(String folderId, BookmarkEntity child) {
    final parent = _listContaining(folderId);
    final f = findById(folderId)?.asFolder;
    if (parent == null || f == null) return;
    if (!f.children.remove(child)) return;
    final fi = parent.indexWhere((e) => e.id == folderId);
    parent.insert(
        (fi < 0 ? parent.length : fi + 1).clamp(0, parent.length), child);
    _autoDissolveFolders();
    notifyListeners();
  }

  /// 边缘翻页：把主项+组搬到目标页边缘列（可创建新页）
  void flipDragTo(int target) {
    final d = drag;
    if (d == null) return;
    if (target < 0 || target > pages.length) return;
    if (target == pages.length) {
      if (pages.length >= maxPages) return;
      pages.add([]);
    }
    final oldArr = pages[d.page];
    final moved = <({BookmarkEntity e, int row})>[];
    for (final e in d.all) {
      final k = oldArr.indexOf(e);
      final row = k < 0 ? 0 : k ~/ 4;
      if (k >= 0) oldArr.removeAt(k);
      moved.add((e: e, row: row));
    }
    moved.sort((a, b) => a.row.compareTo(b.row));
    final newArr = pages[target];
    for (final m in moved) {
      final col = target > d.page ? 0 : 3;
      final idx = (m.row * 4 + col).clamp(0, newArr.length);
      newArr.insert(idx, m.e);
    }
    cur = target;
    d.page = target;
    d.lastDisplaced = null;
    d.hoverFolder = null;
    d.mergeTarget = null;
    d.frozen = false;
    notifyListeners();
  }

  static void _pullOut(List<BookmarkEntity> arr, List<BookmarkEntity> items) {
    for (final it in items) {
      final k = arr.indexOf(it);
      if (k >= 0) arr.removeAt(k);
    }
  }

  // ---------- 删除 ----------

  void removeItem(String id) {
    for (final page in pages) {
      final k = page.indexWhere((e) => e.id == id);
      if (k >= 0) {
        page.removeAt(k);
        selection.remove(id);
        notifyListeners();
        return;
      }
    }
    for (final page in pages) {
      for (final e in page) {
        final f = e.asFolder;
        if (f != null) {
          final ck = f.children.indexWhere((c) => c.id == id);
          if (ck >= 0) {
            f.children.removeAt(ck);
            selection.remove(id);
            _autoDissolveFolders();
            notifyListeners();
            return;
          }
        }
      }
    }
  }

  // ---------- 批量移动 ----------

  void moveSelectionTo(String folderId) {
    final f = findById(folderId)?.asFolder;
    if (f == null) return;
    _applySelection((e) {
      _pullOutFromEverywhere(e);
      f.children.add(e);
    });
  }

  void createFolderFromSelection() {
    // 单选不成夹：1 项文件夹会被自动解散规则立刻拆掉，
    // 这里直接拒绝，保证建夹即有 ≥2 项。
    if (selection.length < 2) return;
    var fp = 0, pos = 0;
    for (var p = 0; p < pages.length; p++) {
      final k = pages[p].indexWhere((e) => selection.contains(e.id));
      if (k >= 0) {
        fp = p;
        pos = k;
        break;
      }
    }
    final folder = BookmarkFolder(id: _nextId(), name: '新建文件夹');
    _applySelection((e) {
      _pullOutFromEverywhere(e);
      folder.children.add(e);
    });
    pages[fp].insert(pos.clamp(0, pages[fp].length), folder);
  }

  void _applySelection(void Function(BookmarkEntity) fn) {
    final ids = selection.toList();
    for (final id in ids) {
      final e = findById(id);
      if (e != null) fn(e);
    }
    selection.clear();
    notifyListeners();
  }

  /// 文件夹改名（BookmarkFolder.name 不可变，这里以新实例替换原位置）。
  void renameFolder(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    void replace(List<BookmarkEntity> arr) {
      final k = arr.indexWhere((e) => e.id == id && e.isFolder);
      if (k >= 0) {
        final f = arr[k].asFolder!;
        arr[k] = BookmarkFolder(id: f.id, name: trimmed, children: f.children);
      } else {
        for (final e in arr) {
          final child = e.asFolder;
          if (child != null) replace(child.children);
        }
      }
    }

    for (final page in pages) {
      replace(page);
    }
    notifyListeners();
  }

  void _pullOutFromEverywhere(BookmarkEntity e) {
    for (final page in pages) {
      final k = page.indexOf(e);
      if (k >= 0) {
        page.removeAt(k);
        return;
      }
    }
    for (final page in pages) {
      for (final x in page) {
        final f = x.asFolder;
        if (f != null) {
          final ck = f.children.indexOf(e);
          if (ck >= 0) {
            f.children.removeAt(ck);
            return;
          }
        }
      }
    }
  }

  // ---------- 收藏（浏览器页调用） ----------

  Future<void> addBookmark({required String url, required String name}) async {
    if (pages.isEmpty) pages.add([]);
    final item = BookmarkItem(id: _nextId(), name: name, url: url);
    // Saved bookmarks always appear on the main bookmarks page.
    pages.first.insert(0, item);
    // Keep every saved item inside a visible page instead of overflowing the grid.
    for (var p = 0; p < pages.length; p++) {
      if (pages[p].length <= pageCapacity) continue;
      if (p + 1 >= pages.length) {
        if (pages.length >= maxPages) break;
        pages.add([]);
      }
      final overflow = pages[p].removeLast();
      pages[p + 1].insert(0, overflow);
    }
    cur = 0;
    notifyListeners();
    await save();
  }

  /// 批量导入书签（HTML 导入用）：按 URL 去重，追加到第一个还有空位的页。
  ///
  /// 返回实际导入的条数；放不下的部分会被静默丢弃（页数有上限）。
  Future<int> importBookmarks(List<ImportedBookmark> items) async {
    if (items.isEmpty) return 0;
    final existing = <String>{};
    bool walk(List<BookmarkEntity> list) {
      for (final e in list) {
        final item = e.asItem;
        if (item != null) {
          existing.add(item.url);
        } else {
          walk(e.asFolder?.children ?? const []);
        }
      }
      return true;
    }

    for (final page in pages) {
      walk(page);
    }
    var imported = 0;
    for (final entry in items) {
      if (existing.contains(entry.url)) continue;
      existing.add(entry.url);
      final item = BookmarkItem(id: _nextId(), name: entry.name, url: entry.url);
      _appendWithOverflow(item);
      imported++;
    }
    if (imported > 0) {
      notifyListeners();
      await save();
    }
    return imported;
  }

  /// 把条目放进第一个未满的页；都满了就在上限内开新页。
  void _appendWithOverflow(BookmarkItem item) {
    for (var p = 0; p < pages.length; p++) {
      if (pages[p].length < pageCapacity) {
        pages[p].add(item);
        return;
      }
    }
    if (pages.length < maxPages) {
      pages.add([item]);
      return;
    }
    // 全满：塞进最后一页末尾（不挤掉已有条目）。
    pages.last.add(item);
  }

  // ---------- 翻页 ----------

  void setCur(int p) {
    if (p < 0 || p >= pages.length) return;
    cur = p;
    notifyListeners();
  }

  // ---------- 持久化 ----------

  Future<void> load() async {
    final loaded = await _store.loadPages();
    if (loaded.isNotEmpty) pages = loaded;
    settings = Settings.fromJson(await _store.loadSettings());
    if (pages.isEmpty) pages = _seedData();
    // 关键：把 id 计数器推进到所有已存在 id 之后。
    // 否则重启后 _idc 从种子计数起步，新建文件夹会与 DB 里的旧 id 撞号，
    // 导致同一页出现两个相同 key 的磁贴（Duplicate keys 红屏）。
    _rebaseIdCounter();
    // 自愈：清掉历史数据里遗留的空/单子文件夹（0项 空壳）
    _autoDissolveFolders();
    notifyListeners();
  }

  /// 扫描全树，取数字后缀最大值，把 [_idc] 推到其上。
  void _rebaseIdCounter() {
    final re = RegExp(r'(\d+)$');
    var max = _idc;
    void scan(List<BookmarkEntity> list) {
      for (final e in list) {
        final m = re.firstMatch(e.id);
        if (m != null) {
          final v = int.parse(m.group(1)!);
          if (v >= max) max = v + 1;
        }
        final f = e.asFolder;
        if (f != null) scan(f.children);
      }
    }

    for (final p in pages) {
      scan(p);
    }
    _idc = max;
  }

  Future<void> save() async {
    // 落库前先解散单子文件夹（<2 项拆回原位），否则单子夹会被持久化，
    // 下次 load 才拆——用户看到的就是"没解开"。
    _autoDissolveFolders();
    // 空页清理：只保留首页可为空
    while (pages.length > 1 && pages.last.isEmpty) {
      pages.removeLast();
    }
    if (cur > pages.length - 1) cur = pages.length - 1;
    await _store.savePages(pages);
    await _store.saveSettings(settings.toJson());
    notifyListeners();
  }

  // ---------- 种子数据（与原型一致） ----------

  static List<BookmarkPage> _seedData() {
    var n = 0;
    String id() => 'i${n++}';
    BookmarkItem b(String name, String url, String cat,
            {bool unread = false, double? progress}) =>
        BookmarkItem(
            id: id(),
            name: name,
            url: url,
            category: cat,
            unread: unread,
            progress: progress);
    BookmarkFolder f(String name, List<BookmarkEntity> children) =>
        BookmarkFolder(id: id(), name: name, children: children);

    return [
      [
        b('知乎', 'zhihu.com', '社区'),
        b('哔哩哔哩', 'bilibili.com', '视频'),
        b('GitHub', 'github.com', '技术'),
        b('掘金', 'juejin.cn', '技术'),
        b('少数派', 'sspai.com', '资讯', progress: 62),
        b('微博', 'weibo.com', '社区'),
        b('淘宝', 'taobao.com', '购物'),
        b('豆瓣', 'douban.com', '社区'),
        f('开发工具', [
          b('Stack Overflow', 'stackoverflow.com', '技术'),
          b('MDN', 'developer.mozilla.org', '技术'),
          b('npm', 'npmjs.com', '技术'),
          b('Can I Use', 'caniuse.com', '技术'),
        ]),
        f('设计灵感', [
          b('Figma', 'figma.com', '设计'),
          b('Dribbble', 'dribbble.com', '设计'),
          b('Behance', 'behance.net', '设计'),
          b('花瓣', 'huaban.com', '设计'),
        ]),
        b('Hacker News', 'news.ycombinator.com', '资讯', unread: true),
        b('Product Hunt', 'producthunt.com', '资讯'),
        b('YouTube', 'youtube.com', '视频'),
        b('网易云音乐', 'music.163.com', '音乐'),
        b('36氪', '36kr.com', '资讯'),
        b('Notion', 'notion.so', '工具'),
        b('京东', 'jd.com', '购物'),
        b('V2EX', 'v2ex.com', '技术'),
        b('虎扑', 'hupu.com', '体育'),
        b('X / Twitter', 'x.com', '社区'),
      ],
      [
        b('小红书', 'xiaohongshu.com', '社区'),
        b('抖音', 'douyin.com', '视频'),
        b('爱奇艺', 'iqiyi.com', '视频'),
        b('IT之家', 'ithome.com', '资讯'),
        b('虎嗅', 'huxiu.com', '资讯'),
        b('爱范儿', 'ifanr.com', '资讯'),
        b('阿里云', 'aliyun.com', '云服务'),
        b('腾讯云', 'cloud.tencent.com', '云服务'),
        b('豆瓣读书', 'book.douban.com', '阅读', progress: 35),
        b('极客公园', 'geekpark.net', '资讯'),
      ],
    ];
  }
}
