/// Pure address-bar navigation rules, kept separate from WebView widgets.
class BrowserNavigation {
  const BrowserNavigation({required this.searchEngineIndex});

  final int searchEngineIndex;

  String searchUrl(String query) {
    final encoded = Uri.encodeQueryComponent(query);
    switch (searchEngineIndex) {
      case 1:
        return 'https://www.baidu.com/s?wd=$encoded';
      case 2:
        return 'https://www.bing.com/search?q=$encoded';
      case 3:
        return 'https://duckduckgo.com/?q=$encoded';
      default:
        return 'https://www.google.com/search?q=$encoded';
    }
  }

  String homeUrl() {
    switch (searchEngineIndex) {
      case 1:
        return 'https://www.baidu.com';
      case 2:
        return 'https://www.bing.com';
      case 3:
        return 'https://duckduckgo.com';
      default:
        return 'https://www.google.com';
    }
  }

  String normalize(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return homeUrl();
    if (value.contains('://')) return value;
    final looksLikeHost = value.contains('.') ||
        value.startsWith('localhost') ||
        value.startsWith('127.0.0.1');
    return looksLikeHost ? 'https://$value' : searchUrl(value);
  }

  static String translationUrl(String url, {String targetLanguage = 'zh-CN'}) {
    return Uri.https('translate.google.com', '/translate', {
      'sl': 'auto',
      'tl': targetLanguage,
      'u': url,
    }).toString();
  }
}
