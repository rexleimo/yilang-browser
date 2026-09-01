import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';

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
}
