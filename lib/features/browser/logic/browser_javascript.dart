import 'dart:convert';

/// JavaScript snippets shared by browser actions.
///
/// Each snippet is a complete expression so it can be passed directly to
/// WebViewController.runJavaScriptReturningResult.
class BrowserJavaScript {
  const BrowserJavaScript._();

  static String findAndHighlight(String query) => '''
(() => {
  const root = document.body;
  const query = ${jsonEncode(query.trim())};
  if (window.YilanBrowserTools) {
    return YilanBrowserTools.findAndHighlight(root, query);
  }
  if (window.CSS && CSS.highlights) CSS.highlights.delete('yilan-find');
  if (!root || !query) return 0;
  const needle = query.toLocaleLowerCase();
  const ranges = [];
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let node;
  while ((node = walker.nextNode())) {
    if (/^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE)\$/.test(node.parentElement?.tagName ?? '')) continue;
    const text = node.data.toLocaleLowerCase();
    let offset = 0;
    let index;
    while ((index = text.indexOf(needle, offset)) !== -1) {
      const range = new Range();
      range.setStart(node, index);
      range.setEnd(node, index + needle.length);
      ranges.push(range);
      offset = index + needle.length;
    }
  }
  if (window.CSS && CSS.highlights && window.Highlight) {
    CSS.highlights.set('yilan-find', new Highlight(...ranges));
  }
  ranges[0]?.startContainer.parentElement?.scrollIntoView({block: 'center'});
  return ranges.length;
})()
''';

  static const clearHighlights = '''
(() => {
  if (window.YilanBrowserTools) return window.YilanBrowserTools.clearHighlights();
  if (window.CSS && CSS.highlights) CSS.highlights.delete('yilan-find');
  return true;
})()
''';

  static String extractText({int maxLength = 500}) => '''
(() => {
  if (window.YilanBrowserTools) {
    return window.YilanBrowserTools.extractText(document.body, $maxLength);
  }
  return (document.body?.innerText || document.body?.textContent || '')
    .replace(/[ \\t\\f\\v]+/g, ' ')
    .replace(/[\\r\\n ]+/g, '\\n')
    .trim()
    .slice(0, $maxLength);
})()
''';
}
