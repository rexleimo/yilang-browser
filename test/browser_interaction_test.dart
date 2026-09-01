import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
import 'package:yilan_browser/features/browser/browser_data_store.dart';
import 'package:yilan_browser/features/browser/browser_history.dart';
import 'package:yilan_browser/features/browser/browser_navigation.dart';
import 'package:yilan_browser/features/browser/browser_page.dart';
import 'package:webview_flutter/webview_flutter.dart';

class _MemoryStore implements BookmarkStore {
  @override
  Future<List<BookmarkPage>> loadPages() async => const [];
  @override
  Future<void> savePages(List<BookmarkPage> pages) async {}
  @override
  Future<Map<String, Object?>> loadSettings() async => {};
  @override
  Future<void> saveSettings(Map<String, Object?> settings) async {}
}

BoardModel _model() => BoardModel(store: _MemoryStore(), seed: const [[]]);

Future<void> _pumpBrowser(WidgetTester tester, BoardModel model) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: BrowserPage(model: model))),
  );
  await tester.pump();
}

Future<void> _pumpMobileBrowser(WidgetTester tester, BoardModel model) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: BrowserPage(model: model))),
  );
  await tester.pump();
}

Future<void> _openBrowserMenu(WidgetTester tester) async {
  final pageMenu = find.byTooltip('页面菜单');
  final trigger =
      pageMenu.evaluate().isNotEmpty ? pageMenu : find.byTooltip('面板');
  await tester.tap(trigger);
  await tester.pumpAndSettle();
}

Future<void> _tapMenuEntry(WidgetTester tester, String label) async {
  await _openBrowserMenu(tester);
  await tester.scrollUntilVisible(
    find.text(label),
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.drag(find.byType(ListView).last, const Offset(0, -180));
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDown(() {
    WidgetController.hitTestWarningShouldBeFatal = false;
  });

  group('address navigation', () {
    test('normalizes hosts, explicit schemes, whitespace, and searches', () {
      expect(
          const BrowserNavigation(searchEngineIndex: 1)
              .normalize(' example.com/path '),
          'https://example.com/path');
      expect(
          const BrowserNavigation(searchEngineIndex: 1)
              .normalize('http://localhost:8080'),
          'http://localhost:8080');
      expect(
          const BrowserNavigation(searchEngineIndex: 1)
              .normalize('flutter test'),
          'https://www.baidu.com/s?wd=flutter+test');
      expect(const BrowserNavigation(searchEngineIndex: 1).normalize(''),
          'https://www.baidu.com');
    });

    test('uses each configured search engine', () {
      expect(const BrowserNavigation(searchEngineIndex: 0).searchUrl('a b'),
          'https://www.google.com/search?q=a+b');
      expect(const BrowserNavigation(searchEngineIndex: 1).searchUrl('a b'),
          'https://www.baidu.com/s?wd=a+b');
      expect(const BrowserNavigation(searchEngineIndex: 2).searchUrl('a b'),
          'https://www.bing.com/search?q=a+b');
      expect(const BrowserNavigation(searchEngineIndex: 3).searchUrl('a b'),
          'https://duckduckgo.com/?q=a+b');
    });

    test('private tabs never enter history', () {
      final existing = [
        BrowserRecord(
          title: 'old',
          url: 'https://old.example',
          visitedAt: DateTime.utc(2025),
        ),
      ];
      final result = BrowserHistory.record(existing,
          title: 'secret', url: 'https://secret.example', private: true);
      expect(result, equals(existing));
      expect(result.where((item) => item.url.contains('secret')), isEmpty);
    });
  });

  group('browser widget baseline', () {
    testWidgets('can add, switch, filter, and close tabs', (tester) async {
      final model = _model();
      await _pumpBrowser(tester, model);

      await _tapMenuEntry(tester, '新建无痕标签页');
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byTooltip('标签页'));
      await tester.pump();
      expect(find.text('标签页'), findsOneWidget);
      expect(find.text('2 个打开的标签'), findsOneWidget);
      await tester.tap(find.byType(FilterChip).last);
      await tester.pump();
      expect(find.text('无痕标签页'), findsOneWidget);
      expect(find.text('1 个打开的标签'), findsOneWidget);
      await tester.tap(find.byType(FilterChip).first);
      await tester.tap(find.byTooltip('关闭标签页').last);
      await tester.pump();
      await tester.tap(find.byTooltip('返回'));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('opening a shortcut and creating a tab preserves old tabs',
        (tester) async {
      await _pumpMobileBrowser(tester, _model());
      final state = tester.state<BrowserPageState>(find.byType(BrowserPage));

      state.openAddress('https://www.bilibili.com');
      await tester.pump();
      expect(state.tabCount, 1);
      expect(state.tabUrls, contains('https://www.bilibili.com'));

      state.openNewTab();
      await tester.pump();
      expect(state.tabCount, 2);
      expect(state.tabUrls, contains('https://www.bilibili.com'));
      expect(state.activeTabUrl, isEmpty);

      state.openAddress('https://example.com');
      await tester.pump();
      expect(state.tabCount, 2);
      expect(
          state.tabUrls,
          containsAll(<String>[
            'https://www.bilibili.com',
            'https://example.com',
          ]));
    });

    testWidgets('menu exposes browser feature entry points', (tester) async {
      await _pumpBrowser(tester, _model());
      await _openBrowserMenu(tester);
      for (final label in [
        '在页面中查找',
        '保存页面截图',
        '分享页面',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('新建无痕标签页'), findsOneWidget);
      expect(find.text('浏览器设置'), findsOneWidget);
    });

    testWidgets('history and reading list open as full pages with search',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'yilan_browser_history_v1':
            '[{"title":"Flutter docs","url":"https://docs.flutter.dev","visitedAt":"2025-01-01T00:00:00.000Z"},{"title":"Other","url":"https://other.example","visitedAt":"2025-01-02T00:00:00.000Z"}]',
        'yilan_reading_list_v1':
            '[{"title":"Read Flutter","url":"https://read.example/flutter","savedAt":"2025-01-03T00:00:00.000Z","excerpt":"text"}]',
      });
      await _pumpBrowser(tester, _model());
      await tester.pumpAndSettle();

      await _tapMenuEntry(tester, '历史记录');
      expect(find.text('Flutter docs'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'other.example');
      await tester.pump();
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Flutter docs'), findsNothing);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();

      await _tapMenuEntry(tester, '阅读清单');
      expect(find.text('Read Flutter'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'read.example');
      await tester.pump();
      expect(find.text('Read Flutter'), findsOneWidget);
      // Saved items can be removed again from the reading-list page.
      await tester.tap(find.byTooltip('移除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      expect(find.text('还没有保存的文章'), findsOneWidget);
    });
  });

  group('narrow mobile browser chrome', () {
    testWidgets('shows five bottom actions and an on-demand address editor',
        (tester) async {
      await _pumpMobileBrowser(tester, _model());

      expect(find.byType(TextField), findsNothing);
      for (final tooltip in [
        '后退',
        '前进',
        '回到 Home',
        '面板',
        '标签页',
      ]) {
        expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
      }
      // Without real page history both arrows must stay disabled.
      IconButton buttonAt(String key) => tester.widget<IconButton>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(IconButton),
            ),
          );
      expect(buttonAt('nav-back-button').onPressed, isNull,
          reason: '后退应在无历史时禁用');
      expect(buttonAt('nav-forward-button').onPressed, isNull,
          reason: '前进应在无前进历史时禁用');
      expect(find.text('1'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      await tester.tap(find.byTooltip('面板'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('搜索或输入网址'));
      await tester.pump();
      final field = find.byKey(const ValueKey('browser-omnibox-input'));
      expect(field, findsOneWidget);
      expect(find.byTooltip('关闭搜索'), findsOneWidget);
    });

    testWidgets('tab overview opens reliably and closes back to the page',
        (tester) async {
      await _pumpMobileBrowser(tester, _model());
      await tester.tap(find.byTooltip('标签页'));
      await tester.pump();
      expect(find.byTooltip('返回'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pump();
      expect(find.byTooltip('返回'), findsNothing);
      expect(find.byTooltip('回到 Home'), findsOneWidget);
    });

    testWidgets('panel can scroll to its lower entries', (tester) async {
      await _pumpMobileBrowser(tester, _model());

      await tester.tap(find.byTooltip('面板'));
      await tester.pumpAndSettle();
      expect(find.text('在页面中查找'), findsOneWidget);

      final menu = find.byType(ListView).last;
      await tester.drag(menu, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('新建无痕标签页'), findsOneWidget);
      expect(find.text('浏览器设置'), findsOneWidget);
    });

    testWidgets('incognito entry opens a private tab without a WebView',
        (tester) async {
      await _pumpMobileBrowser(tester, _model());

      await tester.tap(find.byTooltip('面板'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建无痕标签页'));
      await tester.pump();

      expect(find.text('无痕浏览'), findsOneWidget);
      expect(find.text('关闭此标签页后，不保留本次浏览数据'), findsOneWidget);
      expect(find.byType(WebViewWidget), findsNothing);
      expect(find.byIcon(Icons.visibility_off_outlined), findsWidgets);
    });

    testWidgets('tab cards use two columns and can filter private tabs',
        (tester) async {
      await _pumpMobileBrowser(tester, _model());

      // Add two empty private tabs; empty tabs never create a WebView.
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('面板'));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).last, const Offset(0, -600));
        await tester.pumpAndSettle();
        await tester.tap(find.text('新建无痕标签页'));
        await tester.pump();
      }

      await tester.tap(find.byTooltip('标签页'));
      await tester.pump();
      expect(find.byType(ListView), findsWidgets);

      await tester.tap(find.byType(FilterChip).last);
      await tester.pump();
      expect(find.text('无痕标签页'), findsOneWidget);
      expect(find.text('2 个打开的标签'), findsOneWidget);
    });

    testWidgets('closing the last tab returns to a blank new-tab view',
        (tester) async {
      await _pumpMobileBrowser(tester, _model());

      await tester.tap(find.byTooltip('标签页'));
      await tester.pump();
      await tester.tap(find.byTooltip('关闭标签页'));
      await tester.pump();
      expect(find.text('新标签页'), findsWidgets);
      expect(find.text('使用上方地址栏开始浏览'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.byType(WebViewWidget), findsNothing);
    });
  });
}
