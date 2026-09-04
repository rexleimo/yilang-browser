import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yilan_browser/core/logic/search_engines.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/features/browser/logic/ad_blocker.dart'
    show isAdUrl, isBadUrl, isTrackerUrl, adBlockerScript;
import 'package:yilan_browser/features/browser/services/browser_data_store.dart';

void main() {
  group('SearchEngines', () {
    test('catalog has five engines with stable indices', () {
      expect(SearchEngines.names, hasLength(5));
      expect(SearchEngines.name(0), 'Google');
      expect(SearchEngines.name(4), '维基百科');
      // 越界钳制而不是抛异常
      expect(SearchEngines.name(99), '维基百科');
      expect(SearchEngines.name(-1), 'Google');
    });

    test('searchUrl builds per-engine queries', () {
      expect(SearchEngines.searchUrl(0, 'hello 世界'),
          contains('google.com/search?q='));
      expect(SearchEngines.searchUrl(1, 'q'), contains('baidu.com/s?wd='));
      expect(SearchEngines.searchUrl(2, 'q'), contains('bing.com/search'));
      expect(SearchEngines.searchUrl(3, 'q'), contains('duckduckgo.com'));
      expect(SearchEngines.searchUrl(4, 'flutter'),
          contains('zh.wikipedia.org/w/index.php?search='));
    });
  });

  group('Settings dual-mode engines', () {
    test('private engine index persists separately', () {
      final s = Settings()
        ..searchEngineIndex = 0
        ..privateSearchEngineIndex = 2
        ..suggestRecent = false
        ..suggestBookmarks = false
        ..suggestHistory = false
        ..suggestTabs = false;
      final restored = Settings.fromJson(s.toJson());
      expect(restored.searchEngineIndex, 0);
      expect(restored.privateSearchEngineIndex, 2);
      expect(restored.suggestRecent, isFalse);
      expect(restored.suggestBookmarks, isFalse);
      expect(restored.suggestHistory, isFalse);
      expect(restored.suggestTabs, isFalse);
    });

    test('defaults: private engine is DuckDuckGo, suggestions on', () {
      final s = Settings.fromJson(const {});
      expect(s.privateSearchEngineIndex, 3);
      expect(s.suggestRecent, isTrue);
      expect(s.suggestBookmarks, isTrue);
      expect(s.suggestHistory, isTrue);
      expect(s.suggestTabs, isTrue);
    });
  });

  group('AdBlocker', () {
    test('blocks known ad networks by domain suffix', () {
      expect(isAdUrl('https://pagead2.googlesyndication.com/pagead/x'),
          isTrue);
      expect(isAdUrl('https://www.doubleclick.net/x'), isTrue);
      expect(isAdUrl('https://tags.exoclick.com/x.js'), isTrue);
      expect(isAdUrl('https://syndication.exosrv.com/x'), isTrue);
      expect(isAdUrl('https://popads.net/x'), isTrue);
      expect(isAdUrl('https://propellerads.com/x'), isTrue);
      expect(isAdUrl('https://hilltopads.net/x'), isTrue);
    });

    test('blocks ad URLs by keyword pattern', () {
      expect(isAdUrl('https://example.com/ads/banner.js'), isTrue);
      expect(isAdUrl('https://cdn.example.com/adserver/x'), isTrue);
      expect(isAdUrl('https://site.com/pagead/abc'), isTrue);
      expect(isAdUrl('https://cdn.example.com/banners/promo.jpg'), isTrue);
      expect(isAdUrl('https://x.com/popunder/1'), isTrue);
      expect(isAdUrl('https://net/delivery/js/x.php'), isTrue);
    });

    test('trackers are classified separately from ads', () {
      expect(isTrackerUrl('https://www.google-analytics.com/analytics.js'),
          isTrue);
      expect(isTrackerUrl('https://hm.baidu.com/hm.js?abc'), isTrue);
      expect(isTrackerUrl('https://www.clarity.ms/s/x'), isTrue);
      // 追踪器不是广告
      expect(isAdUrl('https://www.google-analytics.com/analytics.js'),
          isFalse);
      // 两者都算 bad
      expect(isBadUrl('https://tags.exoclick.com/x.js'), isTrue);
      expect(isBadUrl('https://hm.baidu.com/hm.js?abc'), isTrue);
    });

    test('does not block normal hosts or subdomain lookalikes', () {
      expect(isAdUrl('https://www.google.com/search?q=x'), isFalse);
      expect(isAdUrl('https://example.com/notadsuffix.com'), isFalse);
      // 后缀必须是完整注册域：evil-googlesyndication.com 不等于子域
      expect(isAdUrl('https://evil-googlesyndication.com/x'), isFalse);
      expect(isAdUrl('https://baidu.com/s?wd=x'), isFalse);
      // 关键词带边界：/adventure、/adobe 不应命中 /ads/、/advert
      expect(isAdUrl('https://example.com/adventure/time'), isFalse);
      expect(isAdUrl('https://example.com/adobe/download'), isFalse);
      expect(isAdUrl(''), isFalse);
    });

    test('script is idempotent and carries rules', () {
      final js = adBlockerScript();
      expect(js, contains('__yilanAdBlock'));
      expect(js, contains('googlesyndication.com'));
      expect(js, contains('exoclick.com'));
      expect(js, contains('MutationObserver'));
      expect(js, contains('window.open'));
      expect(js, contains('sendBeacon'));
      expect(js, contains('yilanAdBlock'));
    });
  });

  group('recent searches store', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('dedupes case-insensitively and caps at 12', () async {
      final store = BrowserDataStore();
      await store.addRecentSearch('flutter');
      await store.addRecentSearch('Flutter ');
      await store.addRecentSearch('dart');
      // 大小写不敏感去重：保留首次输入的大小写
      expect(await store.loadRecentSearches(), ['dart', 'Flutter']);

      for (var i = 0; i < 20; i++) {
        await store.addRecentSearch('q$i');
      }
      final all = await store.loadRecentSearches();
      expect(all.length, 12);
      expect(all.first, 'q19'); // 最新在前
    });

    test('remove and clear work', () async {
      final store = BrowserDataStore();
      await store.addRecentSearch('a');
      await store.addRecentSearch('b');
      await store.removeRecentSearch('A');
      expect(await store.loadRecentSearches(), ['b']);
      await store.clearRecentSearches();
      expect(await store.loadRecentSearches(), isEmpty);
    });
  });
}
