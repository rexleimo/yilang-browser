/// 文件夹拖出交接（handoff）回归：拖出面板 → 松手落位，全程不得报错。
///
/// 复现用户反馈：把条目从文件夹拖出到首页板跟手后，
/// 在松手（释放文件夹状态）那一刻出现异常。

library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
import 'package:yilan_browser/core/storage/sqlite_bookmark_store.dart';
import 'package:yilan_browser/features/bookmark_desktop/widgets/bookmark_tile.dart';
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

BoardModel _model() {
  final folder = BookmarkFolder(id: 'f1', name: '开发工具', children: [
    BookmarkItem(id: 'c1', name: 'Alpha', url: 'alpha.com'),
    BookmarkItem(id: 'c2', name: 'Beta', url: 'beta.com'),
    BookmarkItem(id: 'c3', name: 'Gamma', url: 'gamma.com'),
  ]);
  return BoardModel(store: _MemoryStore(), seed: [
    [
      folder,
      BookmarkItem(id: 'p1', name: '首页项', url: 'home.com'),
    ],
  ]);
}

Future<void> _pump(WidgetTester tester, BoardModel model) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(YilanApp(model: model));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('drag folder child out and release: no exception, child lands',
      (tester) async {
    final model = _model();
    await _pump(tester, model);

    // 1. 打开文件夹（点击磁贴；'开发工具' 文本在 header tab 也出现，
    //    用板面 tile key 精确定位）
    await tester.tap(find.byKey(const ValueKey('tile-f1')));
    await tester.pump();
    await tester.pump();
    expect(find.text('3 个项目'), findsOneWidget);

    // 2. 长按面板内条目起拖（LongPressDraggable delay 160ms，
    //    LongPressGestureRecognizer 默认 500ms）
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Alpha')),
    );
    await tester.pump(const Duration(milliseconds: 700));

    // 3. 拖出面板边界（背景 DragTarget.onMove → handoff）
    await gesture.moveBy(const Offset(-260, -160));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveBy(const Offset(-120, -80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // 4. 松手：Draggable onDragEnd → onDragFinished 落位
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);

    // 条目应已落到首页顶层
    final page = model.pages.first;
    expect(page.any((e) => e.id == 'c1'), isTrue,
        reason: '拖出的条目应落回首页板');
    final folder = page.firstWhere((e) => e.id == 'f1',
        orElse: () => page.first);
    if (folder is BookmarkFolder) {
      expect(folder.children.any((c) => c.id == 'c1'), isFalse,
          reason: '拖出的条目应已移出文件夹');
    }
  });

  testWidgets('drag folder child out and cancel (no target): no exception',
      (tester) async {
    final model = _model();
    await _pump(tester, model);

    await tester.tap(find.byKey(const ValueKey('tile-f1')));
    await tester.pump();
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Beta')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(-300, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // 直接取消（模拟手势被系统打断）
    await gesture.cancel();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });

  testWidgets('drag out from 2-child folder (auto dissolve) then release',
      (tester) async {
    final model = _model();
    // 文件夹仅剩两项：拖出一项即触发自动解散
    final folder = model.pages.first
        .firstWhere((e) => e.id == 'f1') as BookmarkFolder;
    folder.children.removeWhere((c) => c.id == 'c3');
    await _pump(tester, model);

    await tester.tap(find.byKey(const ValueKey('tile-f1')));
    await tester.pump();
    await tester.pump();
    expect(find.text('2 个项目'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Alpha')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(-260, -160));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveBy(const Offset(-120, -80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    final page = model.pages.first;
    expect(page.any((e) => e.id == 'c1'), isTrue, reason: '拖出条目应落回首页');
    // 2 项夹拖走一项 → 自动解散，夹不应再存在
    expect(page.whereType<BookmarkFolder>().map((f) => f.id),
        isNot(contains('f1')), reason: '不足两项的文件夹应自动解散');
  });

  testWidgets('drag out and release onto a home tile (merge on release)',
      (tester) async {
    final model = _model();
    await _pump(tester, model);

    await tester.tap(find.byKey(const ValueKey('tile-f1')));
    await tester.pump();
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Alpha')),
    );
    await tester.pump(const Duration(milliseconds: 700));

    // 拖出面板，压到首页「首页项」磁贴上并停住（handoff + 候选）
    final tileCenter = tester.getCenter(find.byKey(const ValueKey('tile-p1')));
    await gesture.moveBy(tileCenter - tester.getCenter(find.text('Alpha')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 700));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });

  testWidgets('handoff shows exactly one drag ghost (no double overlay)',
      (tester) async {
    final model = _model();
    await _pump(tester, model);

    await tester.tap(find.byKey(const ValueKey('tile-f1')));
    await tester.pump();
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Alpha')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(-260, -160));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveBy(const Offset(-120, -80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // 交接期：板面 _DragGhost 必须退场，拖影只剩文件夹 feedback 一个，
    // 否则出现「目标小一圈」的双重拖影。
    final boardGhosts = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_DragGhost',
    );
    expect(boardGhosts, findsNothing,
        reason: '交接期板面不应再叠加 _DragGhost');

    // 被拖子项不得以真实磁贴渲染在板面上（拖拽成员应被 display 跳过），
    // 否则板面会同时出现 feedback + 原位磁贴两个「D」。
    final realTiles = tester.widgetList<BookmarkTile>(
      find.byType(BookmarkTile),
    ).where((t) => !t.compact && t.entity.id == 'c1').length;
    expect(realTiles, 0, reason: '交接期被拖子项不应渲染为板面真实磁贴');

    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reorder inside folder panel works (onReorder wired)',
      (tester) async {
    final model = _model();
    await _pump(tester, model);

    await tester.tap(find.byKey(const ValueKey('tile-f1')));
    await tester.pump();
    await tester.pump();

    // 夹内把 Alpha 拖到 Gamma 格（不越出面板，走 onReorder 而非 handoff）
    final from = tester.getCenter(find.text('Alpha'));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 700));

    final to = tester.getCenter(find.text('Gamma'));
    // 分步移动，避免一帧跨面板边界误触发背景 DragTarget 交接
    final delta = to - from;
    for (var i = 1; i <= 5; i++) {
      await gesture.moveBy(delta / 5);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    final folder =
        model.pages.first.firstWhere((e) => e.id == 'f1') as BookmarkFolder;
    expect(
      folder.children.map((c) => c.id).toList(),
      containsAllInOrder(['c2', 'c1', 'c3']),
      reason: 'Alpha 应让位插入到 Gamma 之前（iOS 让位语义）',
    );
  });

  // 纯 test()：testWidgets 的 FakeAsync zone 会把 sqlite 的 Future(() …)
  // 闭包排队成 timer，无 pump 推进 → await 死锁（sqlite_store_test 同理用纯 test）。
  test('handoff release persists through sqlite store (prod parity)', () async {
    final store = SqliteBookmarkStore.inMemory();
    final folder = BookmarkFolder(id: 'f1', name: '开发工具', children: [
      BookmarkItem(id: 'c1', name: 'Alpha', url: 'alpha.com'),
      BookmarkItem(id: 'c2', name: 'Beta', url: 'beta.com'),
      BookmarkItem(id: 'c3', name: 'Gamma', url: 'gamma.com'),
    ]);
    final model = BoardModel(store: store, seed: [
      [folder, BookmarkItem(id: 'p1', name: '首页项', url: 'home.com')]
    ]);

    // 模拟拖出交接落位后的模型状态：条目回到首页顶层、移出文件夹
    mDragOut(model);
    await model.save();

    final loaded = await store.loadPages();
    expect(loaded.first.any((e) => e.id == 'c1'), isTrue,
        reason: '落位结果应已持久化');
    final loadedFolder =
        loaded.first.whereType<BookmarkFolder>().firstOrNull;
    if (loadedFolder != null) {
      expect(loadedFolder.children.any((c) => c.id == 'c1'), isFalse,
          reason: '拖出条目不应残留在文件夹里');
    }
  });
}

/// 直接走模型复现拖出交接的落位（dragOutFromFolder + startDrag + endDrag）。
void mDragOut(BoardModel model) {
  model.dragOutFromFolder('f1', model.findById('c1')!);
  model.startDrag('c1');
  model.endDrag();
}
