import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
import 'package:yilan_browser/theme/home_backgrounds.dart';

class _FakeStore implements BookmarkStore {
  String? pagesRaw;
  Map<String, Object?> settings = {};

  @override
  Future<List<BookmarkPage>> loadPages() async =>
      pagesRaw == null ? [] : decodeBoard(pagesRaw!);

  @override
  Future<void> savePages(List<BookmarkPage> pages) async {
    pagesRaw = encodeBoard(pages);
  }

  @override
  Future<Map<String, Object?>> loadSettings() async => settings;

  @override
  Future<void> saveSettings(Map<String, Object?> s) async => settings = s;
}

BookmarkItem _b(String id, String name) =>
    BookmarkItem(id: id, name: name, url: '$id.example.com');

List<BookmarkPage> _p4() => [
      [_b('a', 'A'), _b('b', 'B'), _b('c', 'C'), _b('d', 'D')],
    ];

BoardModel _model(List<BookmarkPage> seed) =>
    BoardModel(store: _FakeStore(), seed: seed);

void main() {
  group('重排与挤开项', () {
    test('右移：插入让位，被挤开项在 t-1', () {
      final m = _model(_p4());
      m.startDrag('a');
      m.dragTo(0, 2);
      // 插入语义：a 落在 c 的位置，c 左移让位
      expect(m.pages[0].map((e) => e.id).toList(), ['b', 'c', 'a', 'd']);
      expect(m.drag!.lastDisplaced?.id, 'c');
    });

    test('左移：被挤开项在 t+1', () {
      final m = _model(_p4());
      m.startDrag('d');
      m.dragTo(0, 1);
      expect(m.pages[0].map((e) => e.id).toList(), ['a', 'd', 'b', 'c']);
      expect(m.drag!.lastDisplaced?.id, 'b');
    });

    test('组内成员不会被记为挤开项', () {
      final m = _model(_p4());
      m.enterEdit();
      m.toggleSelect('a');
      m.toggleSelect('b');
      m.startDrag('a');
      m.dragTo(0, 1); // 挤开的是 b（组员）
      expect(m.drag!.lastDisplaced, isNull);
    });
  });

  group('iOS 插入式拖拽（dragOver 挖孔语义）', () {
    test('孔位落在某项之前（slot=该项展示位）→ 该项右移让位', () {
      final m = _model(_p4());
      m.startDrag('a');
      // 偏边插入：重叠低（ratio<0.6），无合并意图
      m.dragOver(0, 2, m.pages[0][2], 0.3); // 孔位 2 = c 之前
      m.endDrag();
      // a 抽走后展示序列 [b, c, d]，孔位 2 = d 之前 → b, c, a, d
      expect(m.pages[0].map((e) => e.id).toList(), ['b', 'c', 'a', 'd']);
    });

    test('手指未产生有效移动 → 原位落回', () {
      final m = _model(_p4());
      m.startDrag('c');
      m.endDrag();
      expect(m.pages[0].map((e) => e.id).toList(), ['a', 'b', 'c', 'd']);
    });

    test('挖孔插入位跟随 dragOver 更新；冻结时收起', () {
      final m = _model(_p4());
      m.startDrag('a');
      m.dragOver(0, 1, m.pages[0][1], 1.0);
      expect(m.drag!.insertIdx, 1);
      m.dragOver(0, 3, m.pages[0][3], 1.0);
      expect(m.drag!.insertIdx, 3);
      m.freezeOnCandidate();
      expect(m.drag!.insertIdx, -1);
      m.endDrag(); // 冻结合并优先
      expect(m.pages[0].whereType<BookmarkFolder>().length, 1);
    });

    test('拖到末尾之后（slot = 长度）→ 追加到队尾', () {
      final m = _model(_p4());
      m.startDrag('a');
      m.dragOver(0, 4, null, 0);
      m.endDrag();
      expect(m.pages[0].map((e) => e.id).toList(), ['b', 'c', 'd', 'a']);
    });

    test('重叠不足（压在间隙/边缘，ratio<0.6）→ 停留不冻结，松手按孔位插入', () {
      final m = _model(_p4());
      m.startDrag('a');
      // UI 层已把静态格位换算成展示孔位：c 右半边 → 展示孔位 3 = d 之后
      m.dragOver(0, 3, m.pages[0][2], 0.45);
      m.freezeOnCandidate();
      expect(m.drag!.frozen, isFalse, reason: '间隙停留不得触发合并');
      m.endDrag();
      // a 抽走后展示序列 [b, c, d]，插到 3 = 队尾
      expect(m.pages[0].map((e) => e.id).toList(), ['b', 'c', 'd', 'a']);
    });

    test('落夹成夹（ratio>=0.6 即便未停留）→ 就地成夹并弹开', () {
      final m = _model(_p4());
      m.startDrag('a');
      m.dragOver(0, 2, m.pages[0][2], 0.9);
      expect(m.dropWillMerge, isTrue);
      final folder = m.endDrag();
      expect(folder, isNotNull);
      expect(m.drag, isNull);
      expect(m.pages[0].map((e) => e.id).toList(), ['b', folder!.id, 'd']);
      expect(folder.children.map((e) => e.id).toList(), ['c', 'a']);
    });
  });

  group('合并与吸入', () {
    test('停留合并：拖到书签上 → 新文件夹(2项)', () {
      final m = _model(_p4());
      m.startDrag('a');
      m.dragTo(0, 2);
      m.freezeDwell();
      expect(m.drag!.mergeTarget?.id, 'c');
      m.endDrag();
      final folder = m.pages[0].whereType<BookmarkFolder>().single;
      expect(folder.children.map((e) => e.id).toList(), ['c', 'a']);
      expect(m.pages[0].length, 3);
    });

    test('拖到文件夹上停留 → 吸入', () {
      final f = BookmarkFolder(id: 'f', name: '工具', children: [_b('x', 'X')]);
      final m = _model([
        [_b('a', 'A'), f, _b('c', 'C')],
      ]);
      m.startDrag('a');
      m.dragTo(0, 1);
      m.freezeDwell();
      expect(m.drag!.hoverFolder?.id, 'f');
      m.endDrag();
      expect(f.children.map((e) => e.id).toList(), ['x', 'a']);
      expect(m.pages[0].length, 2);
    });

    test('整组拖到书签 → 合并为3项文件夹', () {
      final m = _model(_p4());
      m.enterEdit();
      m.toggleSelect('a');
      m.toggleSelect('b');
      m.startDrag('a');
      expect(m.drag!.group.map((e) => e.id).toList(), ['b']);
      m.dragTo(0, 3);
      m.freezeDwell();
      expect(m.drag!.mergeTarget?.id, 'd');
      m.endDrag();
      final folder = m.pages[0].whereType<BookmarkFolder>().single;
      expect(folder.children.map((e) => e.id).toList(), ['d', 'a', 'b']);
    });

    test('整块落位：组保持相对顺序', () {
      final m = _model(_p4());
      m.enterEdit();
      m.toggleSelect('a');
      m.toggleSelect('b');
      m.startDrag('a');
      m.dragTo(0, 2);
      m.endDrag();
      // 主项 a 落在投放格位 2，组员 b 紧随其后
      expect(m.pages[0].map((e) => e.id).toList(), ['c', 'd', 'a', 'b']);
    });
  });

  group('翻页', () {
    test('拖到边缘 → 跨页到新页边列（可建新页）', () {
      final m = _model(_p4());
      m.startDrag('d');
      m.flipDragTo(1);
      expect(m.cur, 1);
      expect(m.pages[1].map((e) => e.id).toList(), ['d']);
      expect(m.pages[0].length, 3);
      // 再拖出新页
      m.drag!.page = 1;
      m.flipDragTo(2);
      expect(m.pages.length, 3);
    });

    test('翻页后旧目标作废，不会误吸', () {
      final f = BookmarkFolder(id: 'f', name: '工具', children: []);
      final m = _model([
        [f, _b('a', 'A')],
      ]);
      m.startDrag('a');
      m.dragTo(0, 0);
      m.freezeDwell();
      expect(m.drag!.hoverFolder, isNotNull);
      m.flipDragTo(1);
      m.endDrag();
      expect(m.pages[1].map((e) => e.id).toList(), ['a']);
      expect(f.children, isEmpty);
    });
  });

  group('选择与批量', () {
    test('多选 → 新建文件夹收纳', () {
      final m = _model(_p4());
      m.enterEdit();
      m.toggleSelect('b');
      m.toggleSelect('c');
      m.createFolderFromSelection();
      final folder = m.pages[0].whereType<BookmarkFolder>().single;
      expect(folder.children.map((e) => e.id).toSet(), {'b', 'c'});
      expect(m.selection, isEmpty);
    });

    test('多选 → 移动到已有文件夹', () {
      final f = BookmarkFolder(id: 'f', name: '工具', children: []);
      final m = _model([
        [_b('a', 'A'), f],
      ]);
      m.enterEdit();
      m.toggleSelect('a');
      m.moveSelectionTo('f');
      expect(f.children.map((e) => e.id).toList(), ['a']);
      expect(m.pages[0].any((e) => e.id == 'a'), isFalse);
    });

    test('文件夹改名：替换实例、嵌套可达、空名忽略', () {
      final inner = BookmarkFolder(id: 'inner', name: '内层', children: []);
      final outer =
          BookmarkFolder(id: 'outer', name: '外层', children: [inner]);
      final m = _model([
        [_b('a', 'A'), outer],
      ]);
      m.renameFolder('outer', '  开发工具  ');
      final renamed = m.pages[0][1].asFolder!;
      expect(renamed.name, '开发工具');
      expect(renamed.children.single.id, 'inner');
      expect(identical(renamed, outer), isFalse);
      // 嵌套层改名
      m.renameFolder('inner', '内层改');
      expect(
          m.pages[0][1].asFolder!.children.single.asFolder!.name, '内层改');
      // 空名忽略
      m.renameFolder('inner', '   ');
      expect(
          m.pages[0][1].asFolder!.children.single.asFolder!.name, '内层改');
    });
  });

  group('删除 / 收藏 / 序列化', () {
    test('删除顶层与文件夹内条目', () {
      final m = _model(_p4());
      m.removeItem('b');
      expect(m.pages[0].map((e) => e.id).toList(), ['a', 'c', 'd']);
      m.removeItem('c');
      expect(m.pages[0].length, 2);
    });

    test('收藏新书签到书签首页', () async {
      final m = _model(_p4());
      await m.addBookmark(url: 'https://new.example.com', name: '新站');
      expect(m.pages[0].first.id, isNot('a'));
      expect((m.pages[0].first as BookmarkItem).url, 'https://new.example.com');
    });

    test('收藏时满页项目自动流转到下一页', () async {
      final first = List.generate(20, (i) => _b('p$i', 'P$i'));
      final m = _model([first]);
      await m.addBookmark(url: 'https://overflow.example.com', name: '新站');
      expect(m.pages[0].length, pageCapacity);
      expect((m.pages[0].first as BookmarkItem).url,
          'https://overflow.example.com');
      expect(m.pages[1].length, 1);
      expect(m.pages[1].first.id, 'p19');
    });

    test('序列化往返一致', () {
      final m = _model(_p4());
      m.startDrag('a');
      m.dragTo(0, 1);
      m.endDrag();
      final raw = encodeBoard(m.pages);
      final back = decodeBoard(raw);
      expect(back[0].map((e) => e.id).toList(),
          m.pages[0].map((e) => e.id).toList());
    });

    test('持久化 save/load 往返', () async {
      final store = _FakeStore();
      final m = BoardModel(store: store, seed: _p4());
      await m.addBookmark(url: 'https://x.example.com', name: 'X');
      final m2 = BoardModel(store: store, seed: []);
      await m2.load();
      expect(m2.pages[0].map((e) => e.id).toList(),
          m.pages[0].map((e) => e.id).toList());
    });
  });

  group('首页背景设置', () {
    test('默认值：背景索引 0、无自定义图片', () {
      final m = _model(_p4());
      expect(m.settings.homeBackground, 0);
      expect(m.settings.homeBackgroundPath, isNull);
    });

    test('背景索引与图片路径随 save/load 往返', () async {
      final store = _FakeStore();
      final m = BoardModel(store: store, seed: _p4());
      m.settings.homeBackground = 3;
      m.settings.homeBackgroundPath = '/data/bg.jpg';
      await m.save();

      final m2 = BoardModel(store: store, seed: []);
      await m2.load();
      expect(m2.settings.homeBackground, 3);
      expect(m2.settings.homeBackgroundPath, '/data/bg.jpg');
    });

    test('旧数据缺字段 → 回落默认值', () async {
      final store = _FakeStore();
      store.settings = {'se': 1};
      final m = BoardModel(store: store, seed: _p4());
      await m.load();
      expect(m.settings.homeBackground, 0);
      expect(m.settings.homeBackgroundPath, isNull);
    });

    test('预设解析：越界索引回落默认预设', () {
      expect(identical(resolveHomeBackground(-1), homeBackgroundPresets[0]),
          isTrue);
      expect(identical(resolveHomeBackground(99), homeBackgroundPresets[0]),
          isTrue);
      expect(identical(resolveHomeBackground(2), homeBackgroundPresets[2]),
          isTrue);
    });
  });

  group('文件夹内拖拽', () {
    BookmarkFolder folder() => BookmarkFolder(
          id: 'f1',
          name: '工具',
          children: [_b('x', 'X'), _b('y', 'Y'), _b('z', 'Z')],
        );

    List<BookmarkPage> seedF(BookmarkFolder f) => [
          [_b('a', 'A'), f],
        ];

    test('文件夹内重排：让位插入', () {
      final f = folder();
      final m = _model(seedF(f));
      m.reorderInFolder('f1', f.children[2], 0);
      final saved = m.pages[0][1].asFolder!;
      expect(saved.children.map((e) => e.id).toList(), ['z', 'x', 'y']);
    });

    test('文件夹内重排：同位与越界索引安全', () {
      final f = folder();
      final m = _model(seedF(f));
      m.reorderInFolder('f1', f.children[0], 0);
      m.reorderInFolder('f1', f.children[0], 99);
      final saved = m.pages[0][1].asFolder!;
      expect(saved.children.map((e) => e.id).toList(), ['x', 'y', 'z']);
    });

    test('拖出到上级：紧跟文件夹之后', () {
      final f = folder();
      final m = _model(seedF(f));
      final child = m.pages[0][1].asFolder!.children[1]; // Y
      m.dragOutFromFolder('f1', child);
      expect(m.pages[0].map((e) => e.id).toList(), ['a', 'f1', 'y']);
      final saved = m.pages[0][1].asFolder!;
      expect(saved.children.map((e) => e.id).toList(), ['x', 'z']);
    });

    test('拖出后持久化往返保留结构', () async {
      final store = _FakeStore();
      final m = BoardModel(store: store, seed: seedF(folder()));
      m.dragOutFromFolder('f1', m.pages[0][1].asFolder!.children[0]);
      await m.save();
      final back = decodeBoard(store.pagesRaw!);
      expect(back[0].map((e) => e.id).toList(), ['a', 'f1', 'x']);
      expect(back[0][1].asFolder!.children.map((e) => e.id).toList(),
          ['y', 'z']);
    });
  });
}
