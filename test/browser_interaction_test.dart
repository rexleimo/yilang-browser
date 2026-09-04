import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/features/browser/browser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
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

/// 面板已改为网格菜单：所有条目直接平铺（越界条目先滚动到可见）。
Future<void> _tapMenuEntry(WidgetTester tester, String label) async {
  await _openBrowserMenu(tester);
  final f = find.text(label);
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      150,
      scrollable: find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      ),
    );
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
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
      final state = tester.state<BrowserPageState>(find.byType(BrowserPage));

      // 两个真实标签：普通 + 无痕（占位页不出现在角标里）
      state.openAddress('https://a.example');
      await tester.pump();
      state.openInNewTab('https://b.example', private: true);
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byTooltip('标签页'));
      await tester.pump();
      expect(find.byTooltip('只看无痕'), findsOneWidget);
      await tester.tap(find.byTooltip('只看无痕'));
      await tester.pump();
      expect(find.text('无痕标签页'), findsOneWidget);
      // 无痕过滤下只剩 b.example 一张卡片，关掉它
      await tester.tap(find.byTooltip('关闭标签页').last);
      await tester.pump();
      await tester.tap(find.byTooltip('完成'));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('new-tab goes Home without spawning a blank page',
        (tester) async {
      await _pumpMobileBrowser(tester, _model());
      final state = tester.state<BrowserPageState>(find.byType(BrowserPage));

      state.openAddress('https://www.bilibili.com');
      await tester.pump();
      expect(state.tabCount, 1);
      expect(state.tabUrls, contains('https://www.bilibili.com'));

      // "新建标签页" 现在直接回「一览」主页，不产生空白标签页
      state.openNewTab();
      await tester.pump();
      expect(state.tabCount, 1);
      expect(state.activeTabUrl, 'https://www.bilibili.com');

      // 从主页再开一个新地址 → 各自一个标签
      state.openInNewTab('https://example.com');
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
      // 网格菜单：条目直接平铺（首屏可见项）
      for (final label in [
        '在页面中查找',
        '保存页面截图',
        '分享页面',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // 网格惰性构建：滚动后再断言后方条目
      await tester.scrollUntilVisible(
        find.text('历史记录'),
        150,
        scrollable: find.descendant(
          of: find.byType(GridView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('历史记录'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('浏览器设置'),
        150,
        scrollable: find.descendant(
          of: find.byType(GridView),
          matching: find.byType(Scrollable),
        ),
      );
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
      expect(find.text('1'), findsNothing); // 占位页不计入角标
      expect(find.byType(NavigationBar), findsNothing);

      await tester.tap(find.byTooltip('面板'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搜索或输入网址').last);
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
      expect(find.byTooltip('完成'), findsOneWidget);
      await tester.tap(find.byTooltip('完成'));
      await tester.pump();
      expect(find.byTooltip('完成'), findsNothing);
      expect(find.byTooltip('回到 Home'), findsOneWidget);
    });

    testWidgets('panel uses a flat icon grid', (tester) async {
      await _pumpMobileBrowser(tester, _model());

      await tester.tap(find.byTooltip('面板'));
      await tester.pumpAndSettle();
      // 网格菜单：条目平铺，无二级分类
      expect(find.text('在页面中查找'), findsOneWidget);
      expect(find.text('浏览器设置'), findsOneWidget);
    });

    testWidgets('incognito entry opens a private tab without a WebView',
        (tester) async {
      await _pumpMobileBrowser(tester, _model());

      await _tapMenuEntry(tester, '新建无痕标签页');
      await tester.pump();

      expect(find.text('无痕浏览'), findsOneWidget);
      expect(find.text('关闭此标签页后，不保留本次浏览数据'), findsOneWidget);
      expect(find.byType(WebViewWidget), findsNothing);
      expect(find.byIcon(Icons.visibility_off_outlined), findsWidgets);
    });

    testWidgets('tab overview hides blank placeholders and can filter private',
        (tester) async {
      await _pumpMobileBrowser(tester, _model());

      // Add two empty private tabs; blank tabs never appear in tab UI.
      for (var i = 0; i < 2; i++) {
        await _tapMenuEntry(tester, '新建无痕标签页');
        await tester.pump();
      }

      await tester.tap(find.byTooltip('标签页'));
      await tester.pump();
      // 占位「新标签页」不计入概览：全部视图为空态。
      expect(find.text('暂无打开的标签页'), findsOneWidget);

      await tester.tap(find.byTooltip('只看无痕'));
      await tester.pump();
      expect(find.text('无痕标签页'), findsOneWidget);
      expect(find.text('还没有无痕标签页'), findsOneWidget);
    });

    testWidgets('closing the last real tab hides the count badge and asks Home',
        (tester) async {
      var wentHome = false;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrowserPage(
              model: _model(),
              onOpenBookmarks: () => wentHome = true,
            ),
          ),
        ),
      );
      final state = tester.state<BrowserPageState>(find.byType(BrowserPage));
      state.openAddress('https://a.example');
      await tester.pump();

      await tester.tap(find.byTooltip('标签页'));
      await tester.pump();
      await tester.tap(find.byTooltip('关闭标签页'));
      await tester.pump();
      // 占位空白页保留（地址栏可用），但角标清零并通知外壳回「一览」。
      expect(find.text('使用上方地址栏开始浏览'), findsOneWidget);
      expect(find.text('1'), findsNothing);
      expect(wentHome, isTrue);
      expect(find.byType(WebViewWidget), findsNothing);
    });
  });

  group('dialog controller lifecycle', () {
    // 回归背景：曾在此 dialog 关闭后立即 dispose TextEditingController，
    // 而弹窗仍在播放退出动画/收起键盘，下一帧重建触发
    // "A TextEditingController was used after being disposed"，
    // 继而引发 framework.dart `_dependents.isEmpty` 红屏崩溃。
    Future<void> pumpDialogHost(
      WidgetTester tester,
      Future<Object?> Function(BuildContext) show,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: TextButton(
                  onPressed: () => show(ctx),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('find dialog gains focus after route transition', (tester) async {
      // 回归背景：autofocus 在弹窗过渡期间发起的 IME 请求可能被系统丢弃，
      // 键盘不弹出。KeyboardFocusKickoff 在过渡结束后补一次焦点引导。
      await pumpDialogHost(tester, (ctx) => showFindInPageDialog(ctx));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.focusNode, isNotNull);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('find dialog survives pop animation and IME hide',
        (tester) async {
      await pumpDialogHost(tester, (ctx) => showFindInPageDialog(ctx));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zhihu');

      await tester.tap(find.text('查找'));
      // 退出动画进行中模拟键盘收起（真实设备上 insets 变化触发弹窗重建）。
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('bookmark name dialog survives pop animation and IME hide',
        (tester) async {
      await pumpDialogHost(
        tester,
        (ctx) => showBookmarkNameDialog(ctx, initialName: '知乎'),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), ' renamed ');

      await tester.tap(find.text('保存'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
