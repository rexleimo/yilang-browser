import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
import 'package:yilan_browser/features/bookmark_desktop/bookmark_desktop_page.dart';
import 'package:yilan_browser/features/bookmark_desktop/widgets/folder_page.dart';

/// 回归：iOS 主屏参考（视频）两个签名交互——
/// 1. 长按磁贴先弹上下文菜单；按住拖动 → 菜单收起、进编辑态顺势拖拽；
/// 2. 拖到文件夹上停留 650ms → 出环确认（不提前开夹），松手才吸入
///    文件夹并当场弹开（文件夹最终形态）；出环后拖走即撤环；
///    快速掠过文件夹直接松手 → 当场吸入文件夹末尾。
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
        BookmarkFolder(id: 'f', name: '工具箱', children: [
          BookmarkItem(id: 'x', name: 'Xray', url: 'https://x.example.com'),
          BookmarkItem(id: 'y', name: 'Yankee', url: 'https://y.example.com'),
        ]),
        BookmarkItem(id: 'c', name: 'Ccc', url: 'https://c.example.com'),
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

/// 分步把手指从 [from] 拖到 [to]（5 步，每步 30ms）。
Future<void> _dragTo(
    WidgetTester tester, TestGesture g, Offset from, Offset to) async {
  for (var i = 1; i <= 5; i++) {
    await g.moveBy(Offset((to.dx - from.dx) / 5, (to.dy - from.dy) / 5));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  testWidgets('长按磁贴先弹上下文菜单，不直接进编辑', (tester) async {
    final m = _seeded();
    await _pump(tester, m);

    final g = await tester.startGesture(tester.getCenter(find.text('Aaa').first));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('编辑主屏幕'), findsOneWidget);
    expect(find.text('打开'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(m.editing, isFalse, reason: '菜单阶段不进编辑态');
    expect(m.drag, isNull, reason: '菜单阶段不起拖');

    // 菜单开着松手：菜单保持（iOS 习惯），不触发磁贴点击
    await g.up();
    await tester.pump();
    expect(find.text('编辑主屏幕'), findsOneWidget);
  });

  testWidgets('菜单开着按住拖动 → 收菜单、进编辑态、顺势起拖', (tester) async {
    final m = _seeded();
    await _pump(tester, m);

    final g =
        await tester.startGesture(tester.getCenter(find.text('Aaa').first));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('编辑主屏幕'), findsOneWidget);

    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(find.text('编辑主屏幕'), findsNothing, reason: '拖动即收菜单');
    expect(m.editing, isTrue, reason: '顺势进入编辑态');
    expect(m.drag?.id, 'a', reason: '本事件转为拖拽跟手');
    await g.up();
    await tester.pump(const Duration(milliseconds: 300)); // 落位动画计时器走完
  });

  testWidgets('菜单「编辑主屏幕」进编辑态；「删除」弹确认框', (tester) async {
    final m = _seeded();
    await _pump(tester, m);

    final g =
        await tester.startGesture(tester.getCenter(find.text('Aaa').first));
    await tester.pump(const Duration(milliseconds: 600));
    await g.up();
    await tester.pump();

    await tester.tap(find.text('编辑主屏幕'));
    await tester.pump();
    expect(m.editing, isTrue);
    expect(m.drag, isNull);
  });

  testWidgets('拖到文件夹停留650ms → 出环确认不开夹，松手吸入并弹开', (tester) async {
    final m = _seeded();
    await _pump(tester, m);
    m.enterEdit();
    await tester.pump();

    // 页头有同名文件夹 tab（_buildHeader），磁贴标签要取 .last
    final from = tester.getCenter(find.text('Aaa').first);
    final folderCenter = tester.getCenter(find.text('工具箱').last);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 400)); // 编辑态长按 350ms 起拖
    expect(m.drag, isNotNull);

    await _dragTo(tester, g, from, folderCenter);
    expect(m.drag!.candidate?.id, 'f');
    // 停住 650ms → 出环确认：冻结、hoverFolder 就位，但不弹预览面板
    await tester.pump(const Duration(milliseconds: 700));
    expect(m.drag!.frozen, isTrue);
    expect(m.drag!.hoverFolder?.id, 'f');
    expect(find.text('工具箱'), findsNWidgets(2),
        reason: '只出环不开夹：页头 tab + 原磁贴，无预览标题');
    expect(find.byType(FolderPage), findsNothing, reason: '按住不提前开夹');

    // 松手 → 吸入文件夹末尾，夹以磁贴形态留在板面（不弹开）
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    final folder = m.pages[0].whereType<BookmarkFolder>().single;
    expect(folder.children.map((e) => e.id).last, 'a', reason: '吸入文件夹末尾');
    expect(m.pages[0].length, 2);
    expect(m.drag, isNull);
    expect(find.byType(FolderPage), findsNothing,
        reason: '松手不弹开面板：文件夹磁贴留在板面');
  });

  testWidgets('出环后拖走 → 撤环回板面拖拽，松手按孔位落格不吸入', (tester) async {
    final m = _seeded();
    await _pump(tester, m);
    m.enterEdit();
    await tester.pump();

    final from = tester.getCenter(find.text('Aaa').first);
    final folderCenter = tester.getCenter(find.text('工具箱').last);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 400));
    await _dragTo(tester, g, from, folderCenter);
    await tester.pump(const Duration(milliseconds: 700));
    expect(m.drag!.frozen, isTrue);

    // 拖离文件夹 → 撤环解冻，板面顺序不动
    await g.moveBy(const Offset(0, -280));
    await tester.pump();
    expect(m.drag!.frozen, isFalse);
    expect(m.drag!.hoverFolder, isNull);
    expect(m.pages[0].map((e) => e.id).toList(), ['a', 'f', 'c'],
        reason: '出环只是预览，拖走不落夹');

    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(m.drag, isNull);
    expect(m.pages[0].length, 3, reason: '条目按孔位落回顶层');
    expect(m.pages[0].whereType<BookmarkFolder>().single.children,
        everyElement(isA<BookmarkEntity>().having(
            (e) => e.id, 'id', isNot('a'))),
        reason: '未吸入：文件夹内容不变');
    expect(find.byType(FolderPage), findsNothing, reason: '不弹开文件夹');
  });

  testWidgets('快速掠过文件夹直接松手 → 当场吸入文件夹末尾并弹开', (tester) async {
    final m = _seeded();
    await _pump(tester, m);
    m.enterEdit();
    await tester.pump();

    final from = tester.getCenter(find.text('Aaa').first);
    final folderCenter = tester.getCenter(find.text('工具箱').last);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 400));
    await _dragTo(tester, g, from, folderCenter);
    // 总停留 < 650ms：未出环就松手
    expect(m.drag!.frozen, isFalse);

    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    final folder = m.pages[0].whereType<BookmarkFolder>().single;
    expect(folder.children.map((e) => e.id).last, 'a', reason: '吸入文件夹末尾');
    expect(m.pages[0].length, 2);
    expect(find.byType(FolderPage), findsNothing,
        reason: '快掠吸入不弹开：文件夹磁贴留在板面');
  });
}
