import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
import 'package:yilan_browser/features/bookmark_desktop/bookmark_desktop_page.dart';
import 'package:yilan_browser/features/bookmark_desktop/widgets/folder_page.dart';

/// iOS 式停留成环（参考视频）：条目上按住约 650ms 出环即确认（预览态），
/// 按住期间不提前建夹；松手落定成夹——文件夹的最终形态。
/// 出环后拖走即撤环，回板面继续拖拽。
class _MemoryStore implements BookmarkStore {
  _MemoryStore(this.pages);
  final List<BookmarkPage> pages;
  @override
  Future<List<BookmarkPage>> loadPages() async => pages;
  @override
  Future<void> savePages(List<BookmarkPage> pages) async {}
  @override
  Future<Map<String, Object?>> loadSettings() async => {};
  @override
  Future<void> saveSettings(Map<String, Object?> settings) async {}
}

List<BookmarkPage> _seedPages() => [
      [
        BookmarkItem(id: 'a', name: 'Aaa', url: 'https://a.example.com'),
        BookmarkItem(id: 'b', name: 'Bbb', url: 'https://b.example.com'),
        BookmarkItem(id: 'c', name: 'Ccc', url: 'https://c.example.com'),
        BookmarkItem(id: 'd', name: 'Ddd', url: 'https://d.example.com'),
      ],
    ];

BoardModel _seeded() =>
    BoardModel(store: _MemoryStore(_seedPages()), seed: _seedPages());

Future<void> _pump(WidgetTester tester, BoardModel m) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BookmarkDesktopPage(
          model: m,
          active: true,
          onOpenUrl: (_) {},
          onOpenBrowser: () {},
          onSubmitAddress: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 从 Aaa 拖到 Ccc 并按住到出环（650ms），再继续按住 1s 证明不提前成夹。
Future<TestGesture> _dragAndHold(WidgetTester tester, BoardModel m) async {
  final from = tester.getCenter(find.text('Aaa').first);
  final to = tester.getCenter(find.text('Ccc').first);
  final g = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 1; i <= 5; i++) {
    await g.moveBy(Offset((to.dx - from.dx) / 5, (to.dy - from.dy) / 5));
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(m.drag, isNotNull);
  await tester.pump(const Duration(milliseconds: 700)); // 650ms 出环
  expect(m.drag!.frozen, isTrue);
  expect(m.drag!.mergeTarget?.id, 'c');
  await tester.pump(const Duration(milliseconds: 1000)); // 继续按住
  return g;
}

void main() {
  testWidgets('出环即确认：按住期间不建夹不弹预览，松手成夹（最终形态）',
      (tester) async {
    final m = _seeded();
    await _pump(tester, m);
    m.enterEdit();
    await tester.pump();

    final g = await _dragAndHold(tester, m);
    // 环只是确认预览：板面上没有文件夹，也没有预览面板
    expect(m.drag!.frozen, isTrue);
    expect(m.pages[0].whereType<BookmarkFolder>(), isEmpty,
        reason: '按住只出环，不提前成夹');
    expect(find.text('新文件夹'), findsNothing,
        reason: '松手前无成夹预览');

    await g.up();
    await tester.pump();
    final folder = m.pages[0].whereType<BookmarkFolder>().single;
    expect(folder.children.map((e) => e.id).toList(), ['c', 'a']);
    expect(m.drag, isNull);
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byType(FolderPage), findsNothing,
        reason: '松手不弹开：文件夹以磁贴形态留在板面（最终形态）');
    expect(find.text('新文件夹'), findsWidgets,
        reason: '板面新夹磁贴 + 页头 tab');
  });

  testWidgets('出环后拖走 → 撤环回板面拖拽，松手按孔位落格不成夹',
      (tester) async {
    final m = _seeded();
    await _pump(tester, m);
    m.enterEdit();
    await tester.pump();

    final g = await _dragAndHold(tester, m);
    expect(m.drag!.frozen, isTrue);

    await g.moveBy(const Offset(0, -280)); // 拖离目标
    await tester.pump();
    expect(m.drag!.frozen, isFalse, reason: '拖离目标即撤环解冻');
    expect(m.drag!.mergeTarget, isNull);
    expect(m.pages[0].whereType<BookmarkFolder>(), isEmpty,
        reason: '环只是预览，撤环不落夹');
    expect(m.pages[0].map((e) => e.id).toList(), ['a', 'b', 'c', 'd'],
        reason: '板面顺序未动');

    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(m.drag, isNull);
    expect(m.pages[0].map((e) => e.id).toSet(), {'a', 'b', 'c', 'd'});
    expect(m.pages[0].whereType<BookmarkFolder>(), isEmpty);
  });
}
