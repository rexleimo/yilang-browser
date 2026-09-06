import 'dart:convert';

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

/// 面板为 4×2 分页网格：条目不在首页时横向翻页查找。
Future<void> _swipeToMenuEntry(WidgetTester tester, String label) async {
  for (var i = 0; i < 6 && find.text(label).evaluate().isEmpty; i++) {
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
  }
  expect(find.text(label), findsOneWidget, reason: label);
}

/// 面板条目点击：需要时先翻页到目标。
Future<void> _tapMenuEntry(WidgetTester tester, String label) async {
  await _openBrowserMenu(tester);
  if (find.text(label).evaluate().isEmpty) {
    await _swipeToMenuEntry(tester, label);
    await tester.pumpAndSettle();
  }
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

    testWidgets('incognito entry lands on a private start page in-browser',
        (tester) async {
      await _pumpMobileBrowser(tester, _model());
      final state = tester.state<BrowserPageState>(find.byType(BrowserPage));

      // 无痕入口：不再退化成回主页，而是创建（或复用）无痕占位标签页。
      // initState 留下的普通占位页仍在：[''(普通), ''(无痕)]。
      state.openNewTab(private: true);
      await tester.pump();
      expect(state.tabUrls, ['', '']);
      expect(state.tabPrivateFlags, [false, true]);
      // 占位页不出角标；无痕起始页文案可见。
      expect(find.text('无痕浏览'), findsOneWidget);

      // 在无痕占位页上输入地址 → 原地转正，仍是 private。
      state.openAddress('https://secret.example');
      await tester.pump();
      expect(state.tabUrls, ['', 'https://secret.example']);
      expect(state.tabPrivateFlags, [false, true]);

      // 再次进入无痕入口：已有无痕页非空白，新建一个无痕占位。
      state.openNewTab(private: true);
      await tester.pump();
      expect(state.tabUrls, ['', 'https://secret.example', '']);
      expect(state.tabPrivateFlags, [false, true, true]);
    });

    testWidgets('private opens never hijack a regular blank placeholder',
        (tester) async {
      await _pumpBrowser(tester, _model());
      final state = tester.state<BrowserPageState>(find.byType(BrowserPage));

      // initState 留下的普通空白占位标签页存在。
      expect(state.tabPrivateFlags.first, isFalse);

      // 无痕打开网址：必须新开无痕标签页，不能借用普通占位页（否则记历史）。
      state.openInNewTab('https://private.example', private: true);
      await tester.pump();
      expect(state.tabUrls, ['', 'https://private.example']);
      expect(state.tabPrivateFlags, [false, true]);
    });

    testWidgets('vault tab opens a privacy-space start page', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpBrowser(tester, _model());
      final state = tester.state<BrowserPageState>(find.byType(BrowserPage));

      state.openVaultTab();
      await tester.pump();
      // 普通占位页 + 隐私空间占位页：vault 同时具备 private 语义。
      expect(state.tabUrls, ['', '']);
      expect(state.tabPrivateFlags, [false, true]);
      expect(state.tabVaultFlags, [false, true]);
      expect(find.text('隐私空间'), findsOneWidget);
      expect(find.text('这里的浏览记录加密保存，输入密码才能查看'), findsOneWidget);
    });

    testWidgets('vault page: first run sets password, lock, then unlock',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpBrowser(tester, _model());
      final state = tester.state<BrowserPageState>(find.byType(BrowserPage));

      // 面板入口 → 隐私空间（设置流程）
      await _tapMenuEntry(tester, '进入隐私空间');
      expect(find.text('设置隐私空间密码'), findsOneWidget);

      // 两次输入不一致 → 报错
      await tester.enterText(
          find.byType(TextField).at(0), '4321');
      await tester.enterText(
          find.byType(TextField).at(1), '0000');
      await tester.tap(find.text('开启隐私空间'));
      await tester.pump();
      expect(find.text('两次输入不一致'), findsOneWidget);

      // 正确设置 → 进入记录列表（空态）
      await tester.enterText(
          find.byType(TextField).at(1), '4321');
      await tester.tap(find.text('开启隐私空间'));
      await tester.pumpAndSettle();
      expect(find.text('这里还没有浏览记录'), findsOneWidget);
      expect(state.vaultStore.unlocked, isTrue);

      // 锁定 → 解锁界面 → 输错密码报错 → 输对解锁
      await tester.tap(find.byTooltip('锁定'));
      await tester.pumpAndSettle();
      expect(state.vaultStore.unlocked, isFalse);
      expect(find.text('隐私空间已锁定'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '0000');
      await tester.tap(find.text('解锁'));
      await tester.pump();
      expect(find.text('密码不正确'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '4321');
      await tester.tap(find.text('解锁'));
      await tester.pumpAndSettle();
      expect(find.text('这里还没有浏览记录'), findsOneWidget);
    });

    testWidgets('menu exposes browser feature entry points', (tester) async {
      await _pumpBrowser(tester, _model());
      await _openBrowserMenu(tester);
      // 网格菜单：条目直接平铺（首屏可见项）
      for (final label in [
        '在页面中查找',
        '保存页面截图',
        '分享页面',
        '阅读模式',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // 网格分页：翻页后再断言后方条目
      await _swipeToMenuEntry(tester, '历史记录');
      await _swipeToMenuEntry(tester, '浏览器设置');
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
      // 网格菜单：条目平铺，无二级分类；超出一页的条目翻页可见
      expect(find.text('在页面中查找'), findsOneWidget);
      await _swipeToMenuEntry(tester, '浏览器设置');
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

  group('tab strip sync', () {
    testWidgets('external tab selection skips blank placeholders',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpBrowser(tester, _model());
      final state = tester.state<BrowserPageState>(find.byType(BrowserPage));

      state.openAddress('https://a.example');
      await tester.pump();
      // 无痕/隐私空间占位标签真实存在但不在任何条上显示。
      state.openVaultTab();
      await tester.pump();
      state.openInNewTab('https://b.example');
      await tester.pump();
      expect(state.tabUrls,
          ['https://a.example', '', 'https://b.example']);

      // 主页条的可视下标（过滤占位后）：1 → b.example，0 → a.example。
      // 旧实现直接拿可视下标索引 _tabs，会错选到不可见的占位页。
      state.selectExternalTab(1);
      await tester.pump();
      expect(state.activeTabUrl, 'https://b.example');

      state.selectExternalTab(0);
      await tester.pump();
      expect(state.activeTabUrl, 'https://a.example');

      state.selectExternalTab(99);
      await tester.pump();
      expect(state.activeTabUrl, 'https://a.example');
    });

    testWidgets('promoting a placeholder notifies Home immediately',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var summaries = <BrowserTabSummary>[];
      var notifyCount = 0;
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BrowserPage(
            model: _model(),
            onTabsChanged: (list) {
              notifyCount++;
              summaries = list;
            },
          ),
        ),
      ));
      await tester.pump();
      // 启动占位标签不出现：0 个摘要。
      expect(summaries, isEmpty);

      // 测试环境没有 WebView 平台实现，onPageStarted 永远不会触发 ——
      // 与线上「导航被广告拦截/下载接管」的情形一致：_go 必须自己补推送，
      // 否则主页条永远少一个标签。
      tester
          .state<BrowserPageState>(find.byType(BrowserPage))
          .openAddress('https://a.example');
      await tester.pump();
      expect(notifyCount, greaterThan(0));
      expect(summaries.length, 1);
    });

    testWidgets('incognito menu reuses the private placeholder',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpMobileBrowser(tester, _model());
      final state = tester.state<BrowserPageState>(find.byType(BrowserPage));

      await _tapMenuEntry(tester, '新建无痕标签页');
      await tester.pump();
      expect(state.tabCount, 2); // 启动占位 + 无痕占位

      // 再开一次必须复用：追加会让占位越积越多，主页条下标整体错位。
      await _tapMenuEntry(tester, '新建无痕标签页');
      await tester.pump();
      expect(state.tabCount, 2);
      expect(state.tabPrivateFlags, [false, true]);
    });

    testWidgets('session snapshot maps active index onto saved tabs',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpBrowser(tester, _model());
      final state = tester.state<BrowserPageState>(find.byType(BrowserPage));

      state.openAddress('https://a.example');
      await tester.pump();
      state.openInNewTab('https://private.example', private: true);
      await tester.pump(); // 当前激活：无痕标签（不落盘）
      state.selectExternalTab(0);
      await tester.pump();

      // 触发会话保存：映射修正前存的是含占位的原始下标，恢复后会错位。
      state.selectExternalTab(1); // 回到无痕标签（激活位被过滤）
      await tester.pump();
      // 手动推进防抖窗口。
      await tester.pump(const Duration(milliseconds: 900));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('yilan_browser_session_v1');
      expect(raw, isNotNull);
      final saved = jsonDecode(raw!) as Map<String, Object?>;
      expect((saved['tabs'] as List).length, 1);
      expect((saved['tabs'] as List).first['url'], 'https://a.example');
      expect(saved['active'], 0);
    });

    testWidgets('lifecycle pause flushes the session save immediately',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpBrowser(tester, _model());
      final state = tester.state<BrowserPageState>(find.byType(BrowserPage));

      state.openAddress('https://flush.example');
      await tester.pump();

      // 不推进 800ms 防抖：退后台那一刻必须已经落盘。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('yilan_browser_session_v1');
      expect(raw, isNotNull);
      expect(raw, contains('https://flush.example'));
    });

    testWidgets('cold start restores the saved session', (tester) async {
      SharedPreferences.setMockInitialValues({
        'yilan_browser_session_v1':
            '{"active":0,"savedAt":"2026-01-01T00:00:00.000Z","tabs":[{"url":"https://r1.example","title":"R1"},{"url":"https://r2.example","title":"R2"}]}',
      });
      await _pumpBrowser(tester, _model());
      await tester.pump();
      await tester.pump();
      final state = tester.state<BrowserPageState>(find.byType(BrowserPage));

      expect(state.tabUrls, ['https://r1.example', 'https://r2.example']);

      // 恢复完成后防抖保存不能把会话清掉：推进防抖窗口后仍是两个标签。
      await tester.pump(const Duration(milliseconds: 900));
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('yilan_browser_session_v1');
      expect(raw, isNotNull);
      expect(((jsonDecode(raw!) as Map)['tabs'] as List).length, 2);
    });
  });
}
