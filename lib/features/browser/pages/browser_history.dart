import '../services/browser_data_store.dart';

/// Applies the browser history policy without requiring a WebView.
class BrowserHistory {
  const BrowserHistory._();

  static List<BrowserRecord> record(
    List<BrowserRecord> existing, {
    required String title,
    required String url,
    required bool private,
    DateTime? visitedAt,
  }) {
    if (private || url.isEmpty) return List<BrowserRecord>.from(existing);
    final result = List<BrowserRecord>.from(existing)
      ..removeWhere((item) => item.url == url)
      ..insert(
        0,
        BrowserRecord(
          title: title,
          url: url,
          visitedAt: visitedAt ?? DateTime.now(),
        ),
      );
    if (result.length > 500) result.removeRange(500, result.length);
    return result;
  }
}
