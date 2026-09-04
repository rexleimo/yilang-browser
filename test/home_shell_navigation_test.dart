import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
import 'package:yilan_browser/features/browser/browser_page.dart';
import 'package:yilan_browser/main.dart';

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

void main() {
  setUp(() {
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDown(() {
    WidgetController.hitTestWarningShouldBeFatal = false;
  });

  testWidgets(
      'Home shortcut, new tab, and return to Home preserve one BrowserPage state',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final model = BoardModel(
      store: _MemoryStore(),
      seed: [
        [
          BookmarkItem(
            id: 'bilibili',
            name: '哔哩哔哩',
            url: 'https://www.bilibili.com',
          ),
        ],
      ],
    );

    await tester.pumpWidget(MaterialApp(home: HomeShell(model: model)));
    await tester.pump();

    final browserFinder = find.byType(BrowserPage, skipOffstage: false);
    final browserState = tester.state<BrowserPageState>(browserFinder);
    expect(browserState.tabCount, 1);

    await tester.tap(find.byKey(const ValueKey('tile-bilibili')));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('回到 Home'), findsOneWidget);
    expect(browserState.tabCount, 1);
    expect(browserState.activeTabUrl, 'https://www.bilibili.com');

    // 「新建标签页」回到一览主页，不产生空白标签页
    await tester.tap(find.byTooltip('新建标签页'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('home-toolbar-button')), findsOneWidget);
    expect(browserState.tabCount, 1);
    expect(browserState.tabUrls, contains('https://www.bilibili.com'));

    // 再点同一个书签 → 复用现有标签，不堆叠
    await tester.tap(find.byKey(const ValueKey('tile-bilibili')));
    await tester.pump();
    await tester.pump();

    expect(browserState.tabCount, 1);
    expect(browserState.activeTabUrl, 'https://www.bilibili.com');
  });

  testWidgets('Home tile tap opens a live page in a new tab, not over it',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final model = BoardModel(
      store: _MemoryStore(),
      seed: [
        [
          BookmarkItem(
            id: 'bilibili',
            name: '哔哩哔哩',
            url: 'https://www.bilibili.com',
          ),
          BookmarkItem(
            id: 'github',
            name: 'GitHub',
            url: 'https://github.com',
          ),
        ],
      ],
    );

    await tester.pumpWidget(MaterialApp(home: HomeShell(model: model)));
    await tester.pump();

    final browserState =
        tester.state<BrowserPageState>(find.byType(BrowserPage, skipOffstage: false));

    // First tap fills the initial blank new-tab page.
    await tester.tap(find.byKey(const ValueKey('tile-bilibili')));
    await tester.pump();
    await tester.pump();
    expect(browserState.tabCount, 1);
    expect(browserState.activeTabUrl, 'https://www.bilibili.com');

    // Returning to Home and tapping another bookmark must NOT overwrite the
    // live bilibili page; it opens in a new tab instead.
    await tester.tap(find.byTooltip('回到 Home'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tile-github')));
    await tester.pump();
    await tester.pump();

    expect(browserState.tabCount, 2);
    expect(browserState.tabUrls, containsAll(<String>[
      'https://www.bilibili.com',
      'https://github.com',
    ]));
    expect(browserState.activeTabUrl, 'https://github.com');
  });
}
