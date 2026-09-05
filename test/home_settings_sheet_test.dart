import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
import 'package:yilan_browser/features/bookmark_desktop/widgets/home_settings_sheet.dart';
import 'package:yilan_browser/theme/home_backgrounds.dart';

class _FakeStore implements BookmarkStore {
  String? pagesRaw;
  Map<String, Object?> settings = {};

  @override
  Future<List<BookmarkPage>> loadPages() async =>
      pagesRaw == null ? [] : decodeBoard(pagesRaw!);

  @override
  Future<void> savePages(List<BookmarkPage> pages) async {
    pagesRaw = encodeBoard(pages);
  }

  @override
  Future<Map<String, Object?>> loadSettings() async => settings;

  @override
  Future<void> saveSettings(Map<String, Object?> s) async => settings = s;
}

void main() {
  testWidgets('背景预设：点色板 → settings 更新并立即持久化', (tester) async {
    final store = _FakeStore();
    final m = BoardModel(store: store, seed: [
      [],
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showHomeSettingsSheet(context, m),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('首页背景'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home_bg_preset_2')));
    await tester.pumpAndSettle();

    expect(m.settings.homeBackground, 2);
    expect(store.settings['hbg'], 2);
  });

  testWidgets('背景预设列表不包含「自定义图片」（它走独立的选图入口）', (tester) async {
    final store = _FakeStore();
    final m = BoardModel(store: store, seed: [
      [],
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showHomeSettingsSheet(context, m),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final swatches = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('home_bg_preset_'));
    final swatchCount = tester.widgetList(swatches).length;
    // 预设 7 个，其中 1 个是「自定义图片」→ 色板应为 6 个
    expect(swatchCount, homeBackgroundPresets.length - 1);
    expect(find.text('自定义图片'), findsOneWidget);
  });
}
