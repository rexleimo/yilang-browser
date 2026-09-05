import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
import 'package:yilan_browser/features/settings/settings_page.dart';

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
  testWidgets('设置页·外观子页提供首页背景选择并持久化', (tester) async {
    final store = _FakeStore();
    final model = BoardModel(store: store, seed: [
      [],
    ]);
    await tester.pumpWidget(MaterialApp(home: SettingsPage(model: model)));
    await tester.pumpAndSettle();

    // 主列表 → 外观子页
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    expect(find.text('首页背景'), findsOneWidget);

    // 点第 2 个色板 → settings 更新且落库
    await tester.tap(find.byKey(const ValueKey('home_bg_preset_2')));
    await tester.pumpAndSettle();
    expect(model.settings.homeBackground, 2);
    expect(store.settings['hbg'], 2);
  });

  testWidgets('外观 tile 摘要展示当前背景名', (tester) async {
    final store = _FakeStore();
    final model = BoardModel(store: store, seed: [
      [],
    ]);
    model.settings.homeBackground = 5;
    await tester.pumpWidget(MaterialApp(home: SettingsPage(model: model)));
    await tester.pumpAndSettle();

    expect(find.textContaining('星空夜'), findsOneWidget);
  });
}
