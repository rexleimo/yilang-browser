import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/features/bookmark_desktop/widgets/bookmark_tile.dart';

/// 回归背景：书签 url 不带 scheme（老数据迁移，如 `zhihu.com`）时，
/// isWebBookmark 用原始 Uri.tryParse 判定 host 为空 → 磁贴回退成
/// 全幅渐变底，而图标层用 _uriOf（补 scheme）照常加载 favicon，
/// 渐变色从磁贴边角露出来（用户看到的「圆角缺一块/彩色残角」）。
/// 修复后统一走 _uriOf：带 host 的条目一律白底磁贴。
void main() {
  Future<Container> pumpTileBase(WidgetTester tester, BookmarkEntity entity,
      {double iconSize = 64}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: Center(
            child: BookmarkTile(entity: entity, iconSize: iconSize),
          ),
        ),
      ),
    );
    await tester.pump();
    final base = tester.widget<Container>(
      find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == iconSize,
      ),
    );
    return base;
  }

  testWidgets('scheme-less url still renders a white web tile',
      (tester) async {
    final base = await pumpTileBase(
      tester,
      BookmarkItem(id: 'a', name: '知乎', url: 'zhihu.com', category: '社区'),
    );
    final decoration = base.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.gradient, isNull);
  });

  testWidgets('full url renders a white web tile too', (tester) async {
    final base = await pumpTileBase(
      tester,
      BookmarkItem(
          id: 'b',
          name: '知乎',
          url: 'https://www.zhihu.com/',
          category: '社区'),
    );
    final decoration = base.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.gradient, isNull);
  });

  testWidgets('url-less item keeps the letter gradient tile', (tester) async {
    final base = await pumpTileBase(
      tester,
      BookmarkItem(id: 'c', name: '工具', url: '', category: '本地'),
    );
    final decoration = base.decoration! as BoxDecoration;
    expect(decoration.gradient, isNotNull);
  });

  testWidgets('合并悬停：目标格后退缩小，不做合成预览、无徽章', (tester) async {
    // 回归背景：曾做成悬停时弹出"京+3"合成预览卡，iOS 实际是
    // 悬停时目标轻微后退、幽灵压在上面，松手才生成文件夹。
    final target = BookmarkItem(id: 't', name: '京东', url: 'https://jd.com');
    BookmarkTile? tile;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: Center(
            child: BookmarkTile(
              entity: target,
              jiggling: true,
              merged: true,
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    tile = tester.widgetList<BookmarkTile>(find.byType(BookmarkTile)).first;
    expect(tile.merged, isTrue);
    // 没有合成预览卡（不再渲染并排小图标结构）
    expect(find.text('京'), findsOneWidget); // 目标自身图标仍在
  });
}
