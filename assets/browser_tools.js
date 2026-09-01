(function (global) {
  'use strict';

  var HIGHLIGHT_NAME = 'yilan-find';

  function textNodes(root) {
    var walker = root.ownerDocument.createTreeWalker(
      root,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode: function (node) {
          var parent = node.parentElement;
          if (!parent || /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE)$/.test(parent.tagName)) {
            return NodeFilter.FILTER_REJECT;
          }
          return node.data ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
        }
      }
    );
    var nodes = [];
    var node;
    while ((node = walker.nextNode())) nodes.push(node);
    return nodes;
  }

  function clearHighlights() {
    if (global.CSS && CSS.highlights) CSS.highlights.delete(HIGHLIGHT_NAME);
    return true;
  }

  function findAndHighlight(root, query) {
    root = root || global.document.body;
    query = String(query || '').trim();
    clearHighlights();
    if (!root || !query) return 0;

    var needle = query.toLocaleLowerCase();
    var ranges = [];
    textNodes(root).forEach(function (node) {
      var text = node.data.toLocaleLowerCase();
      var offset = 0;
      var index;
      while ((index = text.indexOf(needle, offset)) !== -1) {
        var range = node.ownerDocument.createRange();
        range.setStart(node, index);
        range.setEnd(node, index + needle.length);
        ranges.push(range);
        offset = index + needle.length;
      }
    });

    if (global.CSS && CSS.highlights && global.Highlight) {
      CSS.highlights.set(HIGHLIGHT_NAME, new Highlight(...ranges));
    }
    if (ranges.length) {
      var element = ranges[0].startContainer.parentElement;
      if (element && element.scrollIntoView) element.scrollIntoView({ block: 'center' });
    }
    return ranges.length;
  }

  function extractText(root, maxLength) {
    root = root || global.document.body;
    if (!root) return '';
    var text = (root.innerText || root.textContent || '')
      .replace(/[ \t\f\v]+/g, ' ')
      .replace(/[\r\n ]+/g, '\n')
      .trim();
    return maxLength && maxLength > 0 ? text.slice(0, maxLength) : text;
  }

  var api = {
    clearHighlights: clearHighlights,
    findAndHighlight: findAndHighlight,
    extractText: extractText
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.YilanBrowserTools = api;
})(typeof window !== 'undefined' ? window : globalThis);
