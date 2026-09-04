/// 搜索引擎目录：常规模式与无痕模式各存一个首选序号。
/// 序号与 [EngineLogo] 的品牌标一一对应（0 Google / 1 百度 / 2 必应 /
/// 3 DuckDuckGo / 4 维基百科）。
class SearchEngines {
  SearchEngines._();

  static const names = <String>[
    'Google',
    '百度',
    '必应',
    'DuckDuckGo',
    '维基百科',
  ];

  static int clamp(int index) => index.clamp(0, names.length - 1);

  static String name(int index) => names[clamp(index)];

  /// 用 [index] 号引擎构造一次搜索的 URL。
  static String searchUrl(int index, String query) {
    final encoded = Uri.encodeQueryComponent(query);
    switch (clamp(index)) {
      case 0:
        return 'https://www.google.com/search?q=$encoded';
      case 1:
        return 'https://www.baidu.com/s?wd=$encoded';
      case 2:
        return 'https://www.bing.com/search?q=$encoded';
      case 3:
        return 'https://duckduckgo.com/?q=$encoded';
      default:
        return 'https://zh.wikipedia.org/w/index.php?search=$encoded';
    }
  }
}
