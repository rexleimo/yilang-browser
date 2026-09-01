import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BrowserRecord {
  const BrowserRecord({
    required this.title,
    required this.url,
    required this.visitedAt,
  });

  final String title;
  final String url;
  final DateTime visitedAt;

  Map<String, Object?> toJson() => {
        'title': title,
        'url': url,
        'visitedAt': visitedAt.toIso8601String(),
      };

  factory BrowserRecord.fromJson(Map<String, Object?> json) => BrowserRecord(
        title: _stringValue(json['title']),
        url: _stringValue(json['url']),
        visitedAt: _dateValue(
          json['visitedAt'] ?? json['visited_at'] ?? json['timestamp'],
        ),
      );
}

class ReadingItem {
  const ReadingItem({
    required this.title,
    required this.url,
    required this.savedAt,
    this.excerpt = '',
    this.offlineContentId,
    this.offlineHtmlPath,
    this.offlineResourcesPath,
  });

  final String title;
  final String url;
  final DateTime savedAt;
  final String excerpt;

  /// Optional fields reserved for a later HTML/resource download implementation.
  final String? offlineContentId;
  final String? offlineHtmlPath;
  final String? offlineResourcesPath;

  Map<String, Object?> toJson() => {
        'title': title,
        'url': url,
        'savedAt': savedAt.toIso8601String(),
        'excerpt': excerpt,
        if (offlineContentId != null) 'offlineContentId': offlineContentId,
        if (offlineHtmlPath != null) 'offlineHtmlPath': offlineHtmlPath,
        if (offlineResourcesPath != null)
          'offlineResourcesPath': offlineResourcesPath,
      };

  factory ReadingItem.fromJson(Map<String, Object?> json) => ReadingItem(
        title: _stringValue(json['title']),
        url: _stringValue(json['url']),
        savedAt: _dateValue(
          json['savedAt'] ?? json['saved_at'] ?? json['createdAt'],
        ),
        excerpt: _stringValue(json['excerpt'] ?? json['description']),
        offlineContentId: _nullableString(json['offlineContentId']),
        offlineHtmlPath: _nullableString(
          json['offlineHtmlPath'] ?? json['localHtmlPath'],
        ),
        offlineResourcesPath: _nullableString(
          json['offlineResourcesPath'] ?? json['resourceDirectoryPath'],
        ),
      );
}

class OfflineContentMetadata {
  const OfflineContentMetadata({
    required this.url,
    required this.downloadedAt,
    this.id = '',
    this.htmlPath = '',
    this.resourcesPath = '',
    this.mimeType = 'text/html',
    this.byteLength,
    this.etag,
    this.lastModified,
    this.checksum,
  });

  final String id;
  final String url;
  final DateTime downloadedAt;
  final String htmlPath;
  final String resourcesPath;
  final String mimeType;
  final int? byteLength;
  final String? etag;
  final DateTime? lastModified;
  final String? checksum;

  Map<String, Object?> toJson() => {
        'id': id,
        'url': url,
        'downloadedAt': downloadedAt.toIso8601String(),
        'htmlPath': htmlPath,
        'resourcesPath': resourcesPath,
        'mimeType': mimeType,
        if (byteLength != null) 'byteLength': byteLength,
        if (etag != null) 'etag': etag,
        if (lastModified != null)
          'lastModified': lastModified!.toIso8601String(),
        if (checksum != null) 'checksum': checksum,
      };

  factory OfflineContentMetadata.fromJson(Map<String, Object?> json) =>
      OfflineContentMetadata(
        id: _stringValue(json['id']),
        url: _stringValue(json['url']),
        downloadedAt: _dateValue(
          json['downloadedAt'] ?? json['savedAt'] ?? json['createdAt'],
        ),
        htmlPath: _stringValue(json['htmlPath'] ?? json['localHtmlPath']),
        resourcesPath: _stringValue(
          json['resourcesPath'] ?? json['resourceDirectoryPath'],
        ),
        mimeType: _stringValue(json['mimeType'], fallback: 'text/html'),
        byteLength: _intValue(json['byteLength'] ?? json['contentLength']),
        etag: _nullableString(json['etag']),
        lastModified: _nullableDate(json['lastModified']),
        checksum: _nullableString(json['checksum']),
      );
}

class BrowserDataStore {
  static const storageVersion = 2;
  static const _versionKey = 'yilan_browser_data_version';
  static const _historyKey = 'yilan_browser_history_v1';
  static const _readingKey = 'yilan_reading_list_v1';
  static const _offlineKey = 'yilan_offline_content_v1';
  static const _maxHistoryItems = 500;

  Future<List<BrowserRecord>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return _deduplicate(
      _decode(prefs.getString(_historyKey), BrowserRecord.fromJson)
          .where((item) => item.url.trim().isNotEmpty),
      (item) => _urlKey(item.url),
    ).take(_maxHistoryItems).toList();
  }

  Future<List<ReadingItem>> loadReadingList() async {
    final prefs = await SharedPreferences.getInstance();
    return _deduplicate(
      _decode(prefs.getString(_readingKey), ReadingItem.fromJson)
          .where((item) => item.url.trim().isNotEmpty),
      (item) => _urlKey(item.url),
    );
  }

  Future<List<OfflineContentMetadata>> loadOfflineContent() async {
    final prefs = await SharedPreferences.getInstance();
    return _deduplicate(
      _decode(
        prefs.getString(_offlineKey),
        OfflineContentMetadata.fromJson,
      ).where((item) => item.url.trim().isNotEmpty),
      _offlineKeyFor,
    );
  }

  Future<void> saveHistory(List<BrowserRecord> records) async {
    final items = _deduplicate(
      records.where((item) => item.url.trim().isNotEmpty),
      (item) => _urlKey(item.url),
    ).take(_maxHistoryItems);
    await _write(_historyKey, items.map((item) => item.toJson()));
  }

  Future<void> saveReadingList(List<ReadingItem> items) async {
    final unique = _deduplicate(
      items.where((item) => item.url.trim().isNotEmpty),
      (item) => _urlKey(item.url),
    );
    await _write(_readingKey, unique.map((item) => item.toJson()));
  }

  Future<void> saveOfflineContent(List<OfflineContentMetadata> items) async {
    final unique = _deduplicate(
      items.where((item) => item.url.trim().isNotEmpty),
      _offlineKeyFor,
    );
    await _write(_offlineKey, unique.map((item) => item.toJson()));
  }

  Future<void> addHistory(BrowserRecord record) async {
    final records = await loadHistory();
    await saveHistory([record, ...records]);
  }

  Future<void> addReadingItem(ReadingItem item) async {
    final items = await loadReadingList();
    await saveReadingList([item, ...items]);
  }

  Future<void> upsertOfflineContent(OfflineContentMetadata metadata) async {
    final items = await loadOfflineContent();
    await saveOfflineContent([metadata, ...items]);
  }

  Future<List<BrowserRecord>> queryHistory({
    DateTime? onDate,
    DateTime? start,
    DateTime? end,
    String query = '',
  }) async {
    final items = await loadHistory();
    return _query(
      items,
      dateOf: (item) => item.visitedAt,
      searchableText: (item) => '${item.title}\n${item.url}',
      onDate: onDate,
      start: start,
      end: end,
      query: query,
    );
  }

  Future<List<ReadingItem>> queryReadingList({
    DateTime? onDate,
    DateTime? start,
    DateTime? end,
    String query = '',
  }) async {
    final items = await loadReadingList();
    return _query(
      items,
      dateOf: (item) => item.savedAt,
      searchableText: (item) => '${item.title}\n${item.url}\n${item.excerpt}',
      onDate: onDate,
      start: start,
      end: end,
      query: query,
    );
  }

  Future<List<OfflineContentMetadata>> queryOfflineContent({
    DateTime? onDate,
    DateTime? start,
    DateTime? end,
    String query = '',
  }) async {
    final items = await loadOfflineContent();
    return _query(
      items,
      dateOf: (item) => item.downloadedAt,
      searchableText: (item) => [
        item.id,
        item.url,
        item.htmlPath,
        item.resourcesPath,
        item.mimeType,
        item.checksum ?? '',
      ].join('\n'),
      onDate: onDate,
      start: start,
      end: end,
      query: query,
    );
  }

  Future<List<BrowserRecord>> historyForDate(DateTime date) =>
      queryHistory(onDate: date);

  Future<List<ReadingItem>> readingListForDate(DateTime date) =>
      queryReadingList(onDate: date);

  Future<List<OfflineContentMetadata>> offlineContentForDate(DateTime date) =>
      queryOfflineContent(onDate: date);

  Future<List<BrowserRecord>> searchHistory(String query) =>
      queryHistory(query: query);

  Future<List<ReadingItem>> searchReadingList(String query) =>
      queryReadingList(query: query);

  Future<List<OfflineContentMetadata>> searchOfflineContent(String query) =>
      queryOfflineContent(query: query);

  Future<bool> deleteHistory(String url) async {
    final items = await loadHistory();
    final key = _urlKey(url);
    final remaining = items.where((item) => _urlKey(item.url) != key).toList();
    if (remaining.length == items.length) return false;
    await saveHistory(remaining);
    return true;
  }

  Future<bool> deleteReadingItem(String url) async {
    final items = await loadReadingList();
    final key = _urlKey(url);
    final remaining = items.where((item) => _urlKey(item.url) != key).toList();
    if (remaining.length == items.length) return false;
    await saveReadingList(remaining);
    return true;
  }

  Future<bool> deleteOfflineContent(String idOrUrl) async {
    final items = await loadOfflineContent();
    final urlKey = _urlKey(idOrUrl);
    final remaining = items.where((item) {
      return item.id != idOrUrl && _urlKey(item.url) != urlKey;
    }).toList();
    if (remaining.length == items.length) return false;
    await saveOfflineContent(remaining);
    return true;
  }

  Future<void> clearHistory() => _clear(_historyKey);

  Future<void> clearReadingList() => _clear(_readingKey);

  Future<void> clearOfflineContent() => _clear(_offlineKey);

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_historyKey),
      prefs.remove(_readingKey),
      prefs.remove(_offlineKey),
    ]);
  }

  Future<void> _write(
    String key,
    Iterable<Map<String, Object?>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    // Keep the top-level array understood by v1 while recording the new schema.
    await prefs.setString(key, jsonEncode(items.toList()));
    await prefs.setInt(_versionKey, storageVersion);
  }

  Future<void> _clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  List<T> _decode<T>(
    String? raw,
    T Function(Map<String, Object?>) decode,
  ) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final value = jsonDecode(raw);
      // Accept both the v1 array and a versioned envelope used by prereleases.
      final Object? encodedItems = value is Map ? value['items'] : value;
      if (encodedItems is! List) return [];
      final result = <T>[];
      for (final item in encodedItems.whereType<Map>()) {
        try {
          result.add(decode(item.cast<String, Object?>()));
        } catch (_) {
          // One malformed item should not make the complete collection unusable.
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  List<T> _deduplicate<T>(Iterable<T> items, String Function(T) keyOf) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (seen.add(keyOf(item))) item,
    ];
  }

  List<T> _query<T>(
    List<T> items, {
    required DateTime Function(T) dateOf,
    required String Function(T) searchableText,
    DateTime? onDate,
    DateTime? start,
    DateTime? end,
    String query = '',
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    return items.where((item) {
      final date = dateOf(item);
      if (onDate != null && !_sameCalendarDate(date, onDate)) return false;
      if (start != null && date.isBefore(start)) return false;
      if (end != null && date.isAfter(end)) return false;
      return normalizedQuery.isEmpty ||
          searchableText(item).toLowerCase().contains(normalizedQuery);
    }).toList();
  }

  static bool _sameCalendarDate(DateTime left, DateTime right) {
    final comparableRight = left.isUtc ? right.toUtc() : right.toLocal();
    return left.year == comparableRight.year &&
        left.month == comparableRight.month &&
        left.day == comparableRight.day;
  }

  static String _offlineKeyFor(OfflineContentMetadata item) =>
      item.id.trim().isNotEmpty ? 'id:${item.id}' : 'url:${_urlKey(item.url)}';

  static String _urlKey(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return trimmed.toLowerCase();
    }
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final isDefaultPort = (scheme == 'http' && uri.port == 80) ||
        (scheme == 'https' && uri.port == 443);
    final authority =
        isDefaultPort || !uri.hasPort ? host : '$host:${uri.port}';
    final path = uri.path.isEmpty ? '/' : uri.path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '$scheme://$authority$path$query';
  }
}

String _stringValue(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

String? _nullableString(Object? value) => value is String ? value : null;

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime _dateValue(Object? value) =>
    _nullableDate(value) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _nullableDate(Object? value) {
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}
