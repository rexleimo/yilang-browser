import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
import 'package:yilan_browser/core/widgets/app_shell.dart';
import 'package:yilan_browser/features/browser/browser_page.dart';
import 'package:yilan_browser/features/settings/settings_page.dart';
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

BoardModel _model() => BoardModel(store: _MemoryStore(), seed: const [[]]);

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(YilanApp(model: _model()));
  await tester.pump();
}

void main() {
  group('product UI regression gate', () {
    for (final size in const [Size(1280, 800), Size(390, 844)]) {
      testWidgets(
          'unified shell and navigation fit ${size.width}x${size.height}',
          (tester) async {
        await _pumpAt(tester, size);

        expect(find.byType(AppShell), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.text('书签'), findsWidgets);
        expect(find.byTooltip('标签页'), findsWidgets);
        expect(find.byTooltip('面板'), findsOneWidget);
        expect(find.byType(OverflowBar), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('标签页').first);
        await tester.pump();
        await tester.pump();
        expect(find.byType(BrowserPage), findsOneWidget);
        // Home's tab button must land in the live tab overview, not a new tab.
        expect(find.byTooltip('返回'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        await tester.tap(find.byTooltip('返回'));
        await tester.pump();
        if (size.width < 840) {
          // fromHome overview returns to the Home/dial surface, and search is
          // the dedicated header entry there.
          expect(find.text('书签'), findsWidgets);
          await tester.tap(find.byKey(const ValueKey('home-omnibox')));
          await tester.pump();
          expect(find.byTooltip('关闭搜索'), findsOneWidget);
        } else {
          // 800px-height test surfaces count as compact; just be back at Home.
          expect(find.text('书签'), findsWidgets);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('browser toolbar keeps a stable 72px height', (tester) async {
      await _pumpAt(tester, const Size(390, 844));
      final toolbar = tester.getRect(
        find.byKey(const ValueKey('bookmark-browser-toolbar')),
      );
      expect(toolbar.height, AppShell.bottomBarHeight);
      expect(toolbar.bottom, 844);
    });

    testWidgets('privacy entry opens a readable dialog', (tester) async {
      await tester.pumpWidget(MaterialApp(home: SettingsPage(model: _model())));
      await tester.pump();
      await tester.tap(find.text('隐私说明').last);
      await tester.pumpAndSettle();
      expect(find.text('隐私说明'), findsWidgets);
      expect(find.textContaining('无痕标签页关闭后不写入历史或书签'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
