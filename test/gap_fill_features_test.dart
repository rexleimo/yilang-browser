import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_codec.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
import 'package:yilan_browser/features/browser/services/browser_data_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookmarkCodec', () {
    test('export produces a Netscape file other browsers can read', () {
      final pages = <BookmarkPage>[
        [
          BookmarkItem(id: 'i1', name: '一览', url: 'https://yilan.app'),
          BookmarkFolder(id: 'f1', name: '开发', children: [
            BookmarkItem(id: 'i2', name: 'Flutter', url: 'https://flutter.dev'),
          ]),
        ],
      ];
      final html = BookmarkCodec.exportHtml(pages);
      expect(html, contains('<!DOCTYPE NETSCAPE-Bookmark-file-1>'));
      expect(html, contains('<A HREF="https://yilan.app">一览</A>'));
      expect(html, contains('<H3>开发</H3>'));
      expect(html, contains('https://flutter.dev'));
    });

    test('export escapes special characters', () {
      final pages = <BookmarkPage>[
        [
          BookmarkItem(
              id: 'i1', name: 'A&B <C>', url: 'https://x.test/?a=1&b=2'),
        ],
      ];
      final html = BookmarkCodec.exportHtml(pages);
      expect(html, contains('A&amp;B &lt;C&gt;'));
      expect(html, contains('a=1&amp;b=2'));
    });

    test('parses nested folders with tolerant matching', () {
      const html = '''
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
  <DT><A HREF="https://a.test/" ADD_DATE="1">A</A>
  <DT><H3>新闻</H3>
  <DL><p>
    <DT><A HREF="https://news.test/">News</A>
    <DT><H3>科技</H3>
    <DL><p>
      <DT><A HREF="https://tech.test/">Tech</A>
    </DL><p>
  </DL><p>
</DL><p>
''';
      final items = BookmarkCodec.parse(html);
      expect(items, hasLength(3));
      expect(items[0].url, 'https://a.test/');
      expect(items[0].folderPath, isEmpty);
      expect(items[1].folderPath, ['新闻']);
      expect(items[2].folderPath, ['新闻', '科技']);
    });

    test('skips entries without a usable url', () {
      const html = '''
<DL><p>
  <DT><A HREF="javascript:void(0)">bad</A>
  <DT><A HREF="mailto:x@y.z">mail</A>
  <DT><A HREF="https://good.test/">good</A>
</DL><p>
''';
      final items = BookmarkCodec.parse(html);
      expect(items, hasLength(1));
      expect(items.single.url, 'https://good.test/');
    });

    test('roundtrip: export then parse keeps names and urls', () {
      final pages = <BookmarkPage>[
        [
          BookmarkItem(id: 'i1', name: ' site 1 ', url: 'https://one.test/x?a=1'),
          BookmarkFolder(id: 'f1', name: '工作', children: [
            BookmarkItem(id: 'i2', name: 'site&2', url: 'https://two.test'),
          ]),
        ],
      ];
      final items = BookmarkCodec.parse(BookmarkCodec.exportHtml(pages));
      expect(items, hasLength(2));
      expect(items[0].url, 'https://one.test/x?a=1');
      // 解析器会修剪名称首尾空白。
      expect(items[0].name, 'site 1');
      expect(items[1].name, 'site&2');
      expect(items[1].folderPath, ['工作']);
    });
  });

  group('BoardModel.importBookmarks', () {
    test('dedupes by url and counts imported items', () async {
      final model = BoardModel(store: _MemoryStore());
      await model.addBookmark(url: 'https://a.test/', name: 'A');
      final imported = await model.importBookmarks(const [
        ImportedBookmark(name: 'A2', url: 'https://a.test/'),
        ImportedBookmark(name: 'B', url: 'https://b.test/'),
        ImportedBookmark(name: 'C', url: 'https://c.test/'),
      ]);
      expect(imported, 2);
    });
  });

  group('ReadingItem read state', () {
    test('json roundtrip keeps readAt and unread helpers', () {
      final unread = ReadingItem(
        title: 't',
        url: 'https://x.test',
        savedAt: DateTime.utc(2026),
      );
      expect(unread.isUnread, isTrue);
      final read = unread.markRead(DateTime.utc(2026, 1, 2));
      expect(read.isUnread, isFalse);
      final restored = ReadingItem.fromJson(read.toJson());
      expect(restored.readAt, DateTime.utc(2026, 1, 2));
      // 旧版本数据没有 readAt 字段也能解析。
      expect(ReadingItem.fromJson(unread.toJson()).isUnread, isTrue);
    });

    test('pruneMissingOfflineContent strips dangling references', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = BrowserDataStore();
      final item = ReadingItem(
        title: 't',
        url: 'https://x.test',
        savedAt: DateTime.utc(2026),
        offlineHtmlPath: '/nonexistent/path/index.html',
        offlineResourcesPath: '/nonexistent/path',
      );
      await store.saveReadingList([item]);
      await store.saveOfflineContent([
        OfflineContentMetadata(
          id: 'dir',
          url: 'https://x.test',
          downloadedAt: DateTime.utc(2026),
          htmlPath: '/nonexistent/path/index.html',
          resourcesPath: '/nonexistent/path',
        ),
      ]);
      final pruned = await store.pruneMissingOfflineContent();
      expect(pruned, 1);
      final items = await store.loadReadingList();
      expect(items.single.hasOfflineCopy, isFalse);
      expect((await store.loadOfflineContent()), isEmpty);
    });
  });

  group('Browser session persistence', () {
    test('save/load roundtrip keeps active index and order', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = BrowserDataStore();
      await store.saveSession(const [
        {'url': 'https://one.test/', 'title': 'One'},
        {'url': 'https://two.test/', 'title': 'Two'},
      ], 1);
      final session = await store.loadSession();
      expect(session, isNotNull);
      expect(session!.tabs, hasLength(2));
      expect(session.tabs[1].url, 'https://two.test/');
      expect(session.activeIndex, 1);
    });

    test('empty session clears and load returns null', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = BrowserDataStore();
      await store.saveSession(const [], 0);
      expect(await store.loadSession(), isNull);
      await store.saveSession(const [
        {'url': 'https://one.test/'},
      ], 0);
      await store.clearSession();
      expect(await store.loadSession(), isNull);
    });

    test('malformed json is treated as no session', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'yilan_browser_session_v1': '{not json',
      });
      final store = BrowserDataStore();
      expect(await store.loadSession(), isNull);
    });
  });

  group('Settings new fields', () {
    test('json roundtrip keeps suggestRemote / restoreSession / desktopUA', () {
      final settings = Settings()
        ..suggestRemote = false
        ..restoreSession = false
        ..desktopUA = true;
      final restored = Settings.fromJson(settings.toJson());
      expect(restored.suggestRemote, isFalse);
      expect(restored.restoreSession, isFalse);
      expect(restored.desktopUA, isTrue);
    });

    test('defaults are on / on / off', () {
      final restored = Settings.fromJson(const {});
      expect(restored.suggestRemote, isTrue);
      expect(restored.restoreSession, isTrue);
      expect(restored.desktopUA, isFalse);
    });
  });
}

/// 测试用内存书签仓（BoardModel 只在 addBookmark/importBookmarks 时调用 save）。
class _MemoryStore implements BookmarkStore {
  @override
  Future<List<BookmarkPage>> loadPages() async => [];

  @override
  Future<void> savePages(List<BookmarkPage> pages) async {}

  @override
  Future<Map<String, Object?>> loadSettings() async => {};

  @override
  Future<void> saveSettings(Map<String, Object?> settings) async {}
}
