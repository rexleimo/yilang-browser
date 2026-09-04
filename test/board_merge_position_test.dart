import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';

class _MemoryStore implements BookmarkStore {
  _MemoryStore(this.pages);
  List<BookmarkPage> pages;
  @override
  Future<List<BookmarkPage>> loadPages() async => pages;
  @override
  Future<void> savePages(List<BookmarkPage> p) async => pages = p;
  @override
  Future<Map<String, Object?>> loadSettings() async => {};
  @override
  Future<void> saveSettings(Map<String, Object?> s) async {}
}

BookmarkItem _b(String id, String name) =>
    BookmarkItem(id: id, name: name, url: 'https://$id.example.com');

BoardModel _model(List<BookmarkPage> seed) =>
    BoardModel(store: _MemoryStore(seed), seed: seed);

/// 合并落位 = 目标在抽走拖拽项后的压缩位置（目标视觉位不动）；
/// 单子文件夹必须解开归位。
void main() {
  group('合并落位（位置不动）', () {
    test('前拖后：a 压 c → 文件夹落在 c 的压缩位，children=[c,a]', () {
      final m = _model([
        [_b('a', 'A'), _b('b', 'B'), _b('c', 'C'), _b('d', 'D')]
      ]);
      m.startDrag('a');
      m.dragOver(0, 0, m.findById('c'), 0.8);
      m.freezeOnCandidate();
      final folder = m.endDrag();
      expect(folder, isNotNull);
      // 抽走 a 后 [b,c,d]，c 在位 1 → 文件夹在位 1
      expect(m.pages[0].map((e) => e.id).toList(), ['b', folder!.id, 'd']);
      expect(folder.children.map((e) => e.id).toList(), ['c', 'a']);
    });

    test('后拖前：d 压 b → 文件夹落在 b 的压缩位，children=[b,d]', () {
      final m = _model([
        [_b('a', 'A'), _b('b', 'B'), _b('c', 'C'), _b('d', 'D')]
      ]);
      m.startDrag('d');
      m.dragOver(0, 0, m.findById('b'), 0.8);
      m.freezeOnCandidate();
      final folder = m.endDrag();
      expect(folder, isNotNull);
      expect(m.pages[0].map((e) => e.id).toList(), ['a', folder!.id, 'c']);
      expect(folder.children.map((e) => e.id).toList(), ['b', 'd']);
    });
  });

  group('解开归位', () {
    test('2 项夹拖出 1 项 → 夹解散，余项回原位 [a,x,y]', () {
      final f = BookmarkFolder(
          id: 'f1', name: '工具', children: [_b('x', 'X'), _b('y', 'Y')]);
      final m = _model([
        [_b('a', 'A'), f]
      ]);
      final y = m.pages[0][1].asFolder!.children[1];
      m.dragOutFromFolder('f1', y);
      expect(m.pages[0].map((e) => e.id).toList(), ['a', 'x', 'y']);
      expect(m.pages[0].whereType<BookmarkFolder>(), isEmpty);
    });

    test('save 落库前解散单子夹，不持久化空壳', () async {
      final store = _MemoryStore([]);
      final m = BoardModel(store: store, seed: [
        [
          _b('a', 'A'),
          BookmarkFolder(id: 'f1', name: '单', children: [_b('x', 'X')])
        ]
      ]);
      await m.save();
      expect(m.pages[0].map((e) => e.id).toList(), ['a', 'x']);
      expect(store.pages[0].whereType<BookmarkFolder>(), isEmpty);
    });

    test('单选不成夹：createFolderFromSelection 拒绝 1 项', () {
      final m = _model([
        [_b('a', 'A'), _b('b', 'B'), _b('c', 'C')]
      ]);
      m.toggleSelect('a');
      m.createFolderFromSelection();
      expect(m.pages[0].whereType<BookmarkFolder>(), isEmpty);
      expect(m.pages[0].map((e) => e.id).toList(), ['a', 'b', 'c']);
    });
  });

  group('出环即确认（松手成夹）', () {
    test('冻结只是预览：松手才落定成夹（最终形态）', () {
      final m = _model([
        [_b('a', 'A'), _b('b', 'B'), _b('c', 'C'), _b('d', 'D')]
      ]);
      m.startDrag('a');
      m.dragOver(0, 0, m.findById('c'), 0.8);
      m.freezeOnCandidate();
      expect(m.drag!.frozen, isTrue);
      expect(m.pages[0].whereType<BookmarkFolder>(), isEmpty,
          reason: '按住只出环，不提前成夹');
      final folder = m.endDrag();
      expect(folder, isNotNull);
      expect(m.drag, isNull);
      expect(folder!.children.map((e) => e.id).toList(), ['c', 'a']);
    });

    test('ratio 不足（间隙/边缘）不出环', () {
      final m = _model([
        [_b('a', 'A'), _b('b', 'B'), _b('c', 'C'), _b('d', 'D')]
      ]);
      m.startDrag('a');
      m.dragOver(0, 0, m.findById('c'), 0.3); // 间隙：ratio 不足
      m.freezeOnCandidate();
      expect(m.drag!.frozen, isFalse);
      expect(m.drag!.mergeTarget, isNull);
      expect(m.pages[0].whereType<BookmarkFolder>(), isEmpty);
    });

    test('间隙落下不合并：按孔位插入', () {
      final m = _model([
        [_b('a', 'A'), _b('b', 'B'), _b('c', 'C'), _b('d', 'D')]
      ]);
      m.startDrag('a');
      m.dragOver(0, 3, m.findById('c'), 0.3);
      expect(m.dropWillMerge, isFalse);
      expect(m.endDrag(), isNull);
      expect(m.pages[0].map((e) => e.id).toList(), ['b', 'c', 'd', 'a']);
    });
  });
}
