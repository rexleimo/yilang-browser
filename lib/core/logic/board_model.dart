/// 书签状态机：重排 / 合并 / 吸入 / 组拖 / 翻页 / 选择 / 编辑
///
/// 纯 Dart（不依赖 Flutter），逻辑与 HTML 原型逐条对齐，便于 `flutter test` 回归。
library;

import 'package:flutter/foundation.dart';

import '../models/bookmark.dart';
import '../storage/bookmark_store.dart';

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
  BookmarkEntity? hoverFolder;
  BookmarkEntity? mergeTarget;
  bool frozen = false;

  List<BookmarkEntity> get all => [entity, ...group];
}

/// 设置项（P1 为本地开关，P2 接真逻辑）
class Settings {
  int searchEngineIndex = 1;
  bool adBlock = true;
  bool incognito = false;
  bool sync = false;
  bool darkMode = false;
  bool hintSeen = false;

  static const List<String> engines = ['Google', '百度', '必应', 'DuckDuckGo'];

  Map<String, Object?> toJson() => {
        'se': searchEngineIndex,
        'ad': adBlock,
        'priv': incognito,
        'sync': sync,
        'dark': darkMode,
        'hint': hintSeen,
      };

  factory Settings.fromJson(Map<String, Object?> j) => Settings()
    ..searchEngineIndex = (j['se'] as num?)?.toInt() ?? 1
    ..adBlock = (j['ad'] as bool?) ?? true
    ..incognito = (j['priv'] as bool?) ?? false
    ..sync = (j['sync'] as bool?) ?? false
    ..darkMode = (j['dark'] as bool?) ?? false
    ..hintSeen = (j['hint'] as bool?) ?? false;

  Settings({
    this.searchEngineIndex = 1,
    this.adBlock = true,
    this.incognito = false,
    this.sync = false,
    this.darkMode = false,
    this.hintSeen = false,
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
    for (final page in pages) {
      for (final e in page) {
        if (e.id == id) return e;
        final f = e.asFolder;
        if (f != null) {
          for (final c in f.children) {
            if (c.id == id) return c;
          }
        }
      }
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

  /// 停留 350ms：冻结重排，选定合并/吸入目标
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

  /// 松手：合并 / 吸入 / 整块落位
  void endDrag() {
    final d = drag;
    if (d == null) return;
    final arr = pages[d.page];
    // 翻页后旧目标作废
    if (d.hoverFolder != null && !arr.contains(d.hoverFolder)) {
      d.hoverFolder = null;
    }
    if (d.mergeTarget != null && !arr.contains(d.mergeTarget)) {
      d.mergeTarget = null;
    }

    if (d.hoverFolder != null) {
      _pullOut(arr, d.all);
      d.hoverFolder!.asFolder!.children.addAll(d.all);
      selection.removeAll(d.all.map((e) => e.id));
      drag = null;
      notifyListeners();
      return;
    }

    if (d.mergeTarget != null) {
      final mt = d.mergeTarget!;
      final mtIdx = arr.indexOf(mt);
      if (mtIdx >= 0) arr.removeAt(mtIdx);
      _pullOut(arr, d.all);
      final folder =
          BookmarkFolder(id: _nextId(), name: '新文件夹', children: [mt, ...d.all]);
      arr.insert(mtIdx.clamp(0, arr.length), folder);
      selection.removeAll(d.all.map((e) => e.id));
      drag = null;
      notifyListeners();
      return;
    }

    // 整块落位：以主项落点为基准，主项在前、组员按当前位置顺序
    final base0 = arr.indexOf(d.entity);
    final block = [
      d.entity,
      ...(d.group.toList()
        ..sort((a, b) => arr.indexOf(a).compareTo(arr.indexOf(b)))),
    ];
    for (final e in block) {
      final k = arr.indexOf(e);
      if (k >= 0) arr.removeAt(k);
    }
    final base = base0.clamp(0, arr.length);
    arr.insertAll(base, block);
    selection.clear();
    drag = null;
    notifyListeners();
  }

  void cancelDrag() {
    drag = null;
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
    if (selection.isEmpty) return;
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
    notifyListeners();
  }

  Future<void> save() async {
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
