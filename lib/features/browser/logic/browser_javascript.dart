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

  /// 阅读模式提取：克隆当前 DOM → 去干扰节点 → 正文容器打分 →
  /// 按文档序重建成干净的标题/段落/图片 HTML，返回 JSON 字符串。
  /// Dart 侧用 ReaderArticle.fromJsResult 解析，空正文时回落普通浏览。
  static const extractArticle = '''
(() => {
  try {
    const SKIP = 'SCRIPT,STYLE,NOSCRIPT,TEMPLATE,IFRAME,SVG,NAV,HEADER,FOOTER,ASIDE,FORM,BUTTON,VIDEO,AUDIO,OBJECT,EMBED,CANVAS,SELECT,OPTION,LABEL';
    const root = document.body.cloneNode(true);
    root.querySelectorAll(SKIP).forEach(el => el.remove());
    root.querySelectorAll('[aria-hidden="true"],.ad,.ads,.advert,[class*="sidebar"],[id*="sidebar"]').forEach(el => el.remove());
    let best = null, bestScore = 0;
    root.querySelectorAll('article,main,[role="main"],div,section').forEach(el => {
      let score = 0;
      el.querySelectorAll('p').forEach(p => {
        const t = (p.textContent || '').trim();
        if (t.length > 40) score += Math.min(t.length, 400);
      });
      if (score > bestScore) { bestScore = score; best = el; }
    });
    if (!best) best = root.querySelector('article') || root;
    const esc = (raw) => raw
      .replace(/&(?!(amp|lt|gt|quot|#39|#\\d+);)/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
    const parts = [];
    const push = (tag, raw) => {
      const t = (raw || '').replace(/[ \\t\\f\\v]+/g, ' ').replace(/[ \\r\\n]+/g, ' ').trim();
      if (t.length < 2 || t.length > 4000) return;
      parts.push('<' + tag + '>' + esc(t) + '</' + tag + '>');
    };
    best.querySelectorAll('h1,h2,h3,h4,p,li,blockquote,img,figcaption').forEach(el => {
      if (parts.length >= 400) return;
      const tag = el.tagName.toLowerCase();
      if (tag === 'img') {
        if (el.closest('p') || el.closest('li')) return;
        const src = el.currentSrc || el.getAttribute('data-src') || el.src || '';
        if (!src || src.startsWith('blob:')) return;
        let abs = src;
        try { abs = new URL(src, location.href).href; } catch (_) {}
        parts.push('<img src="' + esc(abs) + '">');
        return;
      }
      if (tag === 'li' && el.parentElement && el.parentElement.tagName === 'LI') return;
      if (tag === 'p' && el.closest('li')) return;
      if (tag === 'figcaption') { push('p', el.textContent); return; }
      push(tag, el.textContent);
    });
    return JSON.stringify({ title: document.title || '', html: parts.join('') });
  } catch (e) {
    return JSON.stringify({ title: '', html: '' });
  }
})()
''';
}
