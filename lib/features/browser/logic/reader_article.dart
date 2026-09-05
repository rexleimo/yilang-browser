import 'dart:convert';

/// 阅读模式文章：由页面内提取脚本产出（见 BrowserJavaScript.extractArticle），
/// 再由 [readerHtmlDocument] 包装成可直接 `loadHtmlString` 的自包含文档。
class ReaderArticle {
  const ReaderArticle({required this.title, required this.html});

  final String title;
  final String html;

  /// 解析提取脚本返回值。
  ///
  /// 宽容处理三种内核行为：直接 JSON、被再包一层引号的 JSON、以及
  /// 非字符串/非法输入（→ null，调用方回落到普通浏览）。
  /// html 上限 500k 字符，防御异常大页面撑爆 WebView。
  static ReaderArticle? fromJsResult(Object? raw) {
    if (raw is! String) return null;
    var text = raw.trim();
    if (text.isEmpty) return null;
    // 部分内核把字符串结果再 JSON 编码一次：'"..."' → 先解一层
    if (text.startsWith('"') && text.endsWith('"')) {
      try {
        final inner = jsonDecode(text);
        if (inner is String) text = inner.trim();
      } catch (_) {}
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final title = (decoded['title'] as String?)?.trim() ?? '';
    final html = ((decoded['html'] as String?) ?? '').trim();
    if (html.isEmpty) return null;
    return ReaderArticle(
      title: title.isEmpty ? '阅读模式' : title,
      html: html.length > _maxHtmlLength
          ? html.substring(0, _maxHtmlLength)
          : html,
    );
  }

  static const int _maxHtmlLength = 500000;
}

/// 包装成排版友好的自包含 HTML（系统字体、限宽、行高、图片自适应）。
String readerHtmlDocument(ReaderArticle article) {
  final title = _escapeHtml(article.title);
  return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
<title>$title</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 24px 18px 48px;
    background: #fbfbf8;
    color: #1f2430;
    font-family: -apple-system, 'PingFang SC', 'Noto Sans CJK SC', 'Microsoft YaHei', sans-serif;
    font-size: 17px;
    line-height: 1.8;
  }
  main { max-width: 42em; margin: 0 auto; }
  h1 { font-size: 24px; line-height: 1.4; margin: 0 0 20px; }
  h2, h3, h4 { line-height: 1.4; margin: 28px 0 10px; }
  p { margin: 0 0 16px; }
  img, video { max-width: 100%; height: auto; border-radius: 8px; display: block; margin: 18px auto; }
  blockquote {
    margin: 16px 0; padding: 4px 16px;
    border-left: 3px solid #d8dbe2; color: #565d6b;
  }
  ul, ol { padding-left: 24px; margin: 0 0 16px; }
  li { margin-bottom: 6px; }
  hr { border: none; border-top: 1px solid #e3e5ea; margin: 28px 0; }
</style>
</head>
<body>
<main>
<h1>$title</h1>
${article.html}
</main>
</body>
</html>''';
}

String _escapeHtml(String raw) => raw
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
