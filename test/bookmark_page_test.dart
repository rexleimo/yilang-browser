import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
import 'package:yilan_browser/features/bookmark_desktop/bookmark_desktop_page.dart';
import 'package:yilan_browser/core/widgets/browser_chrome.dart';

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
  testWidgets('首页中间按钮是搜索并能打开地址编辑器', (tester) async {
    final model = BoardModel(store: _MemoryStore(), seed: const [[]]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookmarkDesktopPage(
            model: model,
            onOpenUrl: (_) {},
            onOpenBrowser: () {},
            onSubmitAddress: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final button = tester.widget<BrowserToolbarButton>(
      find.byKey(const ValueKey('home-toolbar-button')),
    );
    expect(button.tooltip, '搜索');
    expect(button.icon, Icons.search);
    expect(button.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('home-toolbar-button')));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('首页搜索按钮不会替代首页地址入口测试', (tester) async {
    final model = BoardModel(
      store: _MemoryStore(),
      seed: [
        [BookmarkItem(id: 'a', name: '示例', url: 'https://example.com')],
      ],
    );
    String? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookmarkDesktopPage(
            model: model,
            onOpenUrl: (_) {},
            onOpenBrowser: () {},
            onSubmitAddress: (value) => submitted = value,
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-omnibox')));
    await tester.pump();
    final field = find.byType(TextField);
    await tester.enterText(field, 'example.com');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    expect(submitted, 'example.com');
  });
}
