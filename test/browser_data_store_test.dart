import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yilan_browser/features/browser/browser.dart';

const _historyKey = 'yilan_browser_history_v1';
const _readingKey = 'yilan_reading_list_v1';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BrowserDataStore persistence', () {
    test('history save/load preserves order and every field', () async {
      final store = BrowserDataStore();
      final records = [
        BrowserRecord(
          title: 'First page',
          url: 'https://first.example/path',
          visitedAt: DateTime.utc(2025, 1, 2, 3, 4, 5),
        ),
        BrowserRecord(
          title: 'Second page',
          url: 'https://second.example/?q=test',
          visitedAt: DateTime.utc(2025, 2, 3, 4, 5, 6),
        ),
      ];

      await store.saveHistory(records);

      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString(_historyKey)!) as List<dynamic>,
        [
          {
            'title': 'First page',
            'url': 'https://first.example/path',
            'visitedAt': '2025-01-02T03:04:05.000Z',
          },
          {
            'title': 'Second page',
            'url': 'https://second.example/?q=test',
            'visitedAt': '2025-02-03T04:05:06.000Z',
          },
        ],
      );

      final loaded = await BrowserDataStore().loadHistory();
      expect(loaded, hasLength(2));
      expect(loaded.map((item) => item.title), ['First page', 'Second page']);
      expect(
        loaded.map((item) => item.url),
        ['https://first.example/path', 'https://second.example/?q=test'],
      );
      expect(
        loaded.map((item) => item.visitedAt),
        [DateTime.utc(2025, 1, 2, 3, 4, 5), DateTime.utc(2025, 2, 3, 4, 5, 6)],
      );
    });

    test('reading list save/load preserves order and every field', () async {
      final store = BrowserDataStore();
      final items = [
        ReadingItem(
          title: 'Read first',
          url: 'https://read.example/first',
          savedAt: DateTime.utc(2025, 3, 4, 5, 6, 7),
          excerpt: 'First excerpt',
        ),
        ReadingItem(
          title: 'Read second',
          url: 'https://read.example/second',
          savedAt: DateTime.utc(2025, 4, 5, 6, 7, 8),
          excerpt: 'Second excerpt',
        ),
      ];

      await store.saveReadingList(items);

      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString(_readingKey)!) as List<dynamic>,
        [
          {
            'title': 'Read first',
            'url': 'https://read.example/first',
            'savedAt': '2025-03-04T05:06:07.000Z',
            'excerpt': 'First excerpt',
          },
          {
            'title': 'Read second',
            'url': 'https://read.example/second',
            'savedAt': '2025-04-05T06:07:08.000Z',
            'excerpt': 'Second excerpt',
          },
        ],
      );

      final loaded = await BrowserDataStore().loadReadingList();
      expect(loaded, hasLength(2));
      expect(loaded.map((item) => item.title), ['Read first', 'Read second']);
      expect(
        loaded.map((item) => item.url),
        ['https://read.example/first', 'https://read.example/second'],
      );
      expect(
        loaded.map((item) => item.savedAt),
        [DateTime.utc(2025, 3, 4, 5, 6, 7), DateTime.utc(2025, 4, 5, 6, 7, 8)],
      );
      expect(
        loaded.map((item) => item.excerpt),
        ['First excerpt', 'Second excerpt'],
      );
    });

    test(
        'history query supports calendar date, range, and case-insensitive search',
        () async {
      final store = BrowserDataStore();
      await store.saveHistory([
        BrowserRecord(
          title: 'Dart Language Tour',
          url: 'https://dart.dev/language',
          visitedAt: DateTime.utc(2025, 5, 2, 8),
        ),
        BrowserRecord(
          title: 'Flutter widgets',
          url: 'https://docs.flutter.dev/ui/widgets',
          visitedAt: DateTime.utc(2025, 5, 1, 18),
        ),
        BrowserRecord(
          title: 'Earlier page',
          url: 'https://example.com/earlier',
          visitedAt: DateTime.utc(2025, 4, 30, 23),
        ),
      ]);

      expect(
        (await store.historyForDate(DateTime.utc(2025, 5, 1)))
            .map((item) => item.title),
        ['Flutter widgets'],
      );
      expect(
        (await store.searchHistory('DART')).map((item) => item.title),
        ['Dart Language Tour'],
      );
      expect(
        (await store.queryHistory(
          start: DateTime.utc(2025, 5, 1),
          end: DateTime.utc(2025, 5, 2, 23, 59),
        ))
            .map((item) => item.title),
        ['Dart Language Tour', 'Flutter widgets'],
      );
    });

    test('history add deduplicates canonical URLs and delete/clear persist',
        () async {
      final store = BrowserDataStore();
      await store.addHistory(BrowserRecord(
        title: 'Old title',
        url: 'https://EXAMPLE.com:443/path#old-fragment',
        visitedAt: DateTime.utc(2025, 1, 1),
      ));
      await store.addHistory(BrowserRecord(
        title: 'Newest title',
        url: 'https://example.com/path#new-fragment',
        visitedAt: DateTime.utc(2025, 1, 2),
      ));

      var loaded = await store.loadHistory();
      expect(loaded, hasLength(1));
      expect(loaded.single.title, 'Newest title');
      expect(await store.deleteHistory('https://example.com/path'), isTrue);
      expect(await store.deleteHistory('https://example.com/missing'), isFalse);
      expect(await store.loadHistory(), isEmpty);

      await store.addHistory(BrowserRecord(
        title: 'Again',
        url: 'https://example.com/again',
        visitedAt: DateTime.utc(2025, 1, 3),
      ));
      await store.clearHistory();
      loaded = await store.loadHistory();
      expect(loaded, isEmpty);
    });

    test(
        'reading list supports offline placeholders, query, dedupe, and removal',
        () async {
      final store = BrowserDataStore();
      final oldItem = ReadingItem(
        title: 'Old copy',
        url: 'https://read.example/article#section-one',
        savedAt: DateTime.utc(2025, 6, 1, 9),
      );
      final currentItem = ReadingItem(
        title: 'Offline Architecture',
        url: 'https://read.example/article#section-two',
        savedAt: DateTime.utc(2025, 6, 2, 9),
        excerpt: 'Store HTML and resources safely',
        offlineContentId: 'offline-1',
        offlineHtmlPath: 'pages/offline-1/index.html',
        offlineResourcesPath: 'pages/offline-1/resources',
      );

      await store.saveReadingList([currentItem, oldItem]);

      final loaded = await store.loadReadingList();
      expect(loaded, hasLength(1));
      expect(loaded.single.offlineContentId, 'offline-1');
      expect(loaded.single.offlineHtmlPath, 'pages/offline-1/index.html');
      expect(loaded.single.offlineResourcesPath, 'pages/offline-1/resources');
      expect(await store.searchReadingList('RESOURCES'), hasLength(1));
      expect(
        await store.readingListForDate(DateTime.utc(2025, 6, 2)),
        hasLength(1),
      );
      expect(await store.deleteReadingItem(currentItem.url), isTrue);
      expect(await store.loadReadingList(), isEmpty);

      await store.addReadingItem(oldItem);
      await store.clearReadingList();
      expect(await store.loadReadingList(), isEmpty);
    });

    test('offline metadata supports CRUD, date query, search, and dedupe',
        () async {
      final store = BrowserDataStore();
      final first = OfflineContentMetadata(
        id: 'content-1',
        url: 'https://offline.example/article',
        downloadedAt: DateTime.utc(2025, 7, 3, 10),
        htmlPath: 'offline/content-1.html',
        resourcesPath: 'offline/content-1',
        byteLength: 1200,
        etag: 'v1',
        lastModified: DateTime.utc(2025, 7, 2),
        checksum: 'sha256:first',
      );
      final replacement = OfflineContentMetadata(
        id: 'content-1',
        url: 'https://offline.example/article?fresh=1',
        downloadedAt: DateTime.utc(2025, 7, 4, 10),
        htmlPath: 'offline/content-1-new.html',
        resourcesPath: 'offline/content-1-new',
        mimeType: 'text/html; charset=utf-8',
        byteLength: 2400,
        checksum: 'sha256:replacement',
      );

      await store.upsertOfflineContent(first);
      await store.upsertOfflineContent(replacement);

      final loaded = await store.loadOfflineContent();
      expect(loaded, hasLength(1));
      expect(loaded.single.htmlPath, replacement.htmlPath);
      expect(loaded.single.byteLength, 2400);
      expect(await store.searchOfflineContent('REPLACEMENT'), hasLength(1));
      expect(
        await store.offlineContentForDate(DateTime.utc(2025, 7, 4)),
        hasLength(1),
      );
      expect(await store.deleteOfflineContent('content-1'), isTrue);
      expect(await store.loadOfflineContent(), isEmpty);

      await store.upsertOfflineContent(first);
      await store.clearOfflineContent();
      expect(await store.loadOfflineContent(), isEmpty);
    });

    test('legacy arrays, aliases, and versioned envelopes remain readable',
        () async {
      SharedPreferences.setMockInitialValues({
        _historyKey: jsonEncode({
          'version': 2,
          'items': [
            {
              'title': 'Envelope item',
              'url': 'https://history.example',
              'visited_at': '2025-08-01T02:03:04.000Z',
            },
          ],
        }),
        _readingKey: jsonEncode([
          {
            'title': 'Legacy item',
            'url': 'https://reading.example',
            'createdAt': 1754100000000,
            'description': 'legacy excerpt',
            'localHtmlPath': 'legacy/page.html',
            'resourceDirectoryPath': 'legacy/resources',
          },
        ]),
      });
      final store = BrowserDataStore();

      final history = await store.loadHistory();
      final reading = await store.loadReadingList();
      expect(history.single.visitedAt, DateTime.utc(2025, 8, 1, 2, 3, 4));
      expect(reading.single.excerpt, 'legacy excerpt');
      expect(reading.single.offlineHtmlPath, 'legacy/page.html');
      expect(reading.single.offlineResourcesPath, 'legacy/resources');
    });

    test('clearAll removes all browser collections', () async {
      final store = BrowserDataStore();
      await store.addHistory(BrowserRecord(
        title: 'History',
        url: 'https://history.example',
        visitedAt: DateTime.utc(2025, 1, 1),
      ));
      await store.addReadingItem(ReadingItem(
        title: 'Reading',
        url: 'https://reading.example',
        savedAt: DateTime.utc(2025, 1, 1),
      ));
      await store.upsertOfflineContent(OfflineContentMetadata(
        url: 'https://offline.example',
        downloadedAt: DateTime.utc(2025, 1, 1),
      ));

      await store.clearAll();

      expect(await store.loadHistory(), isEmpty);
      expect(await store.loadReadingList(), isEmpty);
      expect(await store.loadOfflineContent(), isEmpty);
    });

    test('corrupt JSON degrades all collections to empty lists', () async {
      SharedPreferences.setMockInitialValues({
        _historyKey: '{not valid json',
        _readingKey: '[{"title": "incomplete"}',
        'yilan_offline_content_v1': 'not-json',
      });
      final store = BrowserDataStore();

      expect(await store.loadHistory(), isEmpty);
      expect(await store.loadReadingList(), isEmpty);
      expect(await store.loadOfflineContent(), isEmpty);
    });
  });
}
