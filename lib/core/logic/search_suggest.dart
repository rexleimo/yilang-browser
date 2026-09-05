import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 联网搜索建议：为每个内置引擎挑一个公开的 suggest 端点。
///
/// 全部是简单的 GET + JSON/JSONP 响应，超时短、失败静默——
/// 建议属于"锦上添花"，任何网络抖动都不该影响地址栏输入。
class SearchSuggestService {
  SearchSuggestService._();

  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3);

  /// 最近一次结果缓存：快速连续输入时复用，避免闪烁。
  static String _cachedQuery = '';
  static int _cachedEngine = -1;
  static List<String> _cachedResults = const [];

  /// 拉取 [query] 在 [engineIndex] 号引擎下的建议词（最多 [limit] 条）。
  ///
  /// 失败时返回空列表；结果按查询串+引擎做一层 memo。
  static Future<List<String>> fetch(
    int engineIndex,
    String query, {
    int limit = 6,
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final q = query.trim();
    if (q.isEmpty || q.length > 200) return const [];
    final engine = engineIndex.clamp(0, 4);
    if (_cachedEngine == engine &&
        _cachedQuery == q &&
        _cachedResults.isNotEmpty) {
      return _cachedResults;
    }
    try {
      final uri = _endpoint(engine, q);
      if (uri == null) return const [];
      final request = await _client
          .getUrl(uri)
          .timeout(timeout)
          .then((value) => value..headers.set('User-Agent', 'YilanBrowser/0.2'));
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return const [];
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final results = _parse(body, engine);
      _cachedEngine = engine;
      _cachedQuery = q;
      _cachedResults = results.take(limit).toList(growable: false);
      return _cachedResults;
    } catch (_) {
      return const [];
    }
  }

  /// 主动换词后使 memo 失效（不必显式调用：memo 以查询串为键）。
  static void invalidate() {
    _cachedQuery = '';
    _cachedResults = const [];
  }

  static Uri? _endpoint(int engine, String query) {
    final q = Uri.encodeQueryComponent(query);
    switch (engine) {
      case 0: // Google
        return Uri.parse(
            'https://suggestqueries.google.com/complete/search?client=chrome&q=$q');
      case 1: // 百度
        return Uri.parse(
            'https://www.baidu.com/sugrec?prod=open&from=pc_open&wd=$q');
      case 2: // 必应
        return Uri.parse('https://api.bing.com/osjson.aspx?query=$q');
      case 3: // DuckDuckGo
        return Uri.parse('https://duckduckgo.com/ac/?type=list&q=$q');
      case 4: // 维基百科
        return Uri.parse(
            'https://zh.wikipedia.org/w/api.php?action=opensearch&limit=8&format=json&search=$q');
      default:
        return null;
    }
  }

  static List<String> _parse(String body, int engine) {
    try {
      final value = jsonDecode(_stripJsonp(body));
      if (engine == 1) {
        // 百度 sugrec：{"g":[{"q":"..."}, ...]}
        if (value is Map) {
          final items = value['g'];
          if (items is List) {
            return [
              for (final item in items)
                if (item is Map && item['q'] is String) item['q'] as String,
            ];
          }
        }
        return const [];
      }
      // Chrome/osjson/opensearch 格式：[query, [s1, s2, ...]]
      if (value is List && value.length >= 2 && value[1] is List) {
        return [
          for (final item in value[1] as List)
            if (item is String) item,
        ];
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  static String _stripJsonp(String body) {
    final trimmed = body.trim();
    final open = trimmed.indexOf('(');
    final close = trimmed.lastIndexOf(')');
    if (open > 0 && close > open) return trimmed.substring(open + 1, close);
    return trimmed;
  }
}
