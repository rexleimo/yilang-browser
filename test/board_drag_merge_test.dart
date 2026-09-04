import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
import 'package:yilan_browser/features/bookmark_desktop/bookmark_desktop_page.dart';
import 'package:yilan_browser/features/bookmark_desktop/widgets/folder_page.dart';

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
        BookmarkItem(id: 'a', name: 'A', url: 'https://a.example.com'),
        BookmarkItem(id: 'b', name: 'B', url: 'https://b.example.com'),
        BookmarkItem(id: 'c', name: 'C', url: 'https://c.example.com'),
        BookmarkItem(id: 'd', name: 'D', url: 'https://d.example.com'),
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

void main() {
  testWidgets('合并：正压停留650ms → 冻结成夹（无缝无白块，目标不让位）',
      (tester) async {
    final m = _seeded();
    await _pump(tester, m);

    final from = tester.getCenter(find.text('A').first);
    final to = tester.getCenter(find.text('C').first);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 600)); // 长按 → 上下文菜单
    // iOS 参考：非编辑态长按先弹菜单，不直接起拖
    expect(m.drag, isNull);
    expect(find.text('编辑主屏幕'), findsOneWidget);

    // 按住拖动 → 菜单收起、进入编辑态、顺势起拖（iOS 式）
    // 分步移动到 C：板面必须完全静止（列表顺序不变，无任何后退/挖孔）
    for (var i = 1; i <= 5; i++) {
      await g.moveBy(Offset((to.dx - from.dx) / 5, (to.dy - from.dy) / 5));
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(m.drag, isNotNull);
    expect(m.editing, isTrue);
    expect(m.pages[0].map((e) => e.id).toList(), ['a', 'b', 'c', 'd'],
        reason: '拖动过程不得重排');
    expect(m.drag!.candidate?.id, 'c');
    expect(
      find.byKey(const ValueKey('drag-hole')),
      findsNothing,
      reason: '正压合并无缝，C 不得让位移动',
    );
    expect(
      find.byKey(const ValueKey('origin-gap-a')),
      findsOneWidget,
      reason: '合并预览原位留透明缝，其余按原位不动',
    );
    expect(
      find.byWidgetPredicate((w) => w is AnimatedScale && w.scale == .9),
      findsNothing,
      reason: '未停住时目标格不得后退',
    );

    // 停住 650ms → 冻结合并：目标图标原样（scale 1），托盘从原位外扩（1.25S）
    await tester.pump(const Duration(milliseconds: 700));
    // 冻结时合并态才挂载，托盘动画（200ms）需再推进到终态
    await tester.pump(const Duration(milliseconds: 250));
    expect(m.drag!.frozen, isTrue);
    expect(m.drag!.mergeTarget?.id, 'c');
    expect(
      find.byWidgetPredicate(
        (w) => w is Transform && (w.transform.storage[0] - 0.76).abs() < 0.02,
      ),
      findsNothing,
      reason: '合并悬停目标图标不得缩小（原样不动）',
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Transform && (w.transform.storage[0] - 1.25).abs() < 0.01,
      ),
      findsOneWidget,
      reason: '托盘从目标原位向外扩到 1.25S',
    );

    // 松手 → 合并成文件夹，以磁贴形态留在板面（最终形态，不弹开）
    await g.up();
    await tester.pump();
    final folder = m.pages[0].whereType<BookmarkFolder>().single;
    expect(folder.children.map((e) => e.id).toList(), ['c', 'a']);
    expect(m.pages[0].length, 3);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FolderPage), findsNothing,
        reason: '松手不弹开面板：文件夹就是板面上的磁贴');
    expect(find.text('新文件夹'), findsWidgets,
        reason: '板面新夹磁贴 + 页头 tab');
  });

  testWidgets('占格：偏边快放 → 松手时目标让位、被拖项占格', (tester) async {
    final m = _seeded();
    await _pump(tester, m);

    final from = tester.getCenter(find.text('A').first);
    // C 左半偏边：落在 C 之前但重叠 <0.6，不触发合并意图
    final to =
        tester.getCenter(find.text('C').first) + const Offset(-35, 0);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 600)); // 长按 → 上下文菜单
    for (var i = 1; i <= 5; i++) {
      await g.moveBy(Offset((to.dx - from.dx) / 5, (to.dy - from.dy) / 5));
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(m.drag, isNotNull, reason: '菜单开着拖动 → 顺势起拖');
    // 偏边插入留透明缝（露底无白块），图标滑动让位
    expect(
      find.byKey(const ValueKey('drag-hole')),
      findsOneWidget,
      reason: '偏边插入应留透明缝',
    );
    // 不停住（总停留 < 650ms）直接松手
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250)); // 落位滑入动画结束
    expect(m.drag, isNull);
    // 松手落在 C 的格位（slot 2）= 插到 C 之前：C 右移让位
    expect(m.pages[0].map((e) => e.id).toList(), ['b', 'a', 'c', 'd']);
  });

  testWidgets('落夹成夹：压在合并位即便不停留 → 松手就地成夹并弹开',
      (tester) async {
    final m = _seeded();
    await _pump(tester, m);

    final from = tester.getCenter(find.text('A').first);
    final to = tester.getCenter(find.text('C').first);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 600)); // 长按 → 上下文菜单
    for (var i = 1; i <= 5; i++) {
      await g.moveBy(Offset((to.dx - from.dx) / 5, (to.dy - from.dy) / 5));
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(m.drag!.candidate?.id, 'c');
    // 不停留直接松手：iOS 习惯——压在图标上就成夹，不取消
    await g.up();
    await tester.pump();
    final folder = m.pages[0].whereType<BookmarkFolder>().single;
    expect(folder.children.map((e) => e.id).toList(), ['c', 'a']);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FolderPage), findsNothing,
        reason: '松手不弹开面板：文件夹就是板面上的磁贴');
  });
}
