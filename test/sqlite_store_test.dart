import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/sqlite_bookmark_store.dart';

void main() {
  test('sqlite store roundtrips pages with nested folders', () async {
    final store = SqliteBookmarkStore.inMemory();
    final pages = [
      [
        BookmarkItem(id: 'a', name: '知乎', url: 'https://zhihu.com'),
        BookmarkFolder(id: 'f', name: '开发', children: [
          BookmarkItem(id: 'b', name: 'GitHub', url: 'https://github.com'),
          BookmarkFolder(id: 'g', name: '嵌套', children: [
            BookmarkItem(
                id: 'c', name: 'MDN', url: 'https://developer.mozilla.org'),
          ]),
        ]),
      ],
      [BookmarkItem(id: 'd', name: '淘宝', url: 'https://taobao.com')],
    ];
    await store.savePages(pages);
    final loaded = await store.loadPages();
    expect(loaded.length, 2);
    expect(loaded[0].length, 2);
    expect(loaded[0][0].asItem!.url, 'https://zhihu.com');
    final f = loaded[0][1].asFolder!;
    expect(f.name, '开发');
    expect(f.children.length, 2);
    expect(f.children[0].asItem!.name, 'GitHub');
    expect(f.children[1].asFolder!.children.first.asItem!.name, 'MDN');
    expect(loaded[1].first.name, '淘宝');
  });

  test('settings roundtrip keeps json values', () async {
    final store = SqliteBookmarkStore.inMemory();
    await store.saveSettings({'searchEngineIndex': 2, 'darkMode': true});
    final s = await store.loadSettings();
    expect(s['searchEngineIndex'], 2);
    expect(s['darkMode'], true);
  });

  test('favicon cache stores bytes and negative marker', () async {
    final store = SqliteBookmarkStore.inMemory();
    expect(store.loadFavicon('zhihu.com'), isNull);
    await store.saveFavicon('zhihu.com', Uint8List.fromList([1, 2, 3]));
    final ok = store.loadFavicon('zhihu.com')!;
    expect(ok.ok, isTrue);
    expect(ok.data, isNotNull);
    await store.saveFavicon('bad.com', null);
    final neg = store.loadFavicon('bad.com')!;
    expect(neg.ok, isFalse);
    expect(neg.data, isNull);
  });

  test('重启后新建文件夹 id 不与旧数据撞号（Duplicate keys 回归）', () async {
    final store = SqliteBookmarkStore.inMemory();
    await store.savePages([
      [
        BookmarkItem(id: 'i1005', name: 'A', url: 'https://a.com'),
        BookmarkItem(id: 'i1006', name: 'B', url: 'https://b.com'),
        BookmarkItem(id: 'i1007', name: 'C', url: 'https://c.com'),
      ],
    ]);
    final m = BoardModel(store: store);
    await m.load();
    // 模拟拖拽 A 覆盖 B 停留 → 冻结 → 松手合并
    m.startDrag('i1005');
    m.dragOver(0, 1, m.pages[0][1], 1.0);
    m.freezeOnCandidate();
    m.endDrag();
    // 全树 id 必须唯一（撞号会让同页出现两个相同 key 的磁贴）
    final ids = <String>[];
    void scan(List<BookmarkEntity> list) {
      for (final e in list) {
        ids.add(e.id);
        final f = e.asFolder;
        if (f != null) scan(f.children);
      }
    }

    for (final p in m.pages) {
      scan(p);
    }
    expect(ids.toSet().length, ids.length, reason: 'id 重复: $ids');
  });
}
