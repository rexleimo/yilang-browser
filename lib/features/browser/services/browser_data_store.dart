import 'dart:convert';
import 'dart:io';

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
    this.readAt,
    this.offlineContentId,
    this.offlineHtmlPath,
    this.offlineResourcesPath,
  });

  final String title;
  final String url;
  final DateTime savedAt;
  final String excerpt;

  /// 阅读完成时间；null 表示未读（稍后读队列的核心状态）。
  final DateTime? readAt;

  /// Optional fields reserved for a later HTML/resource download implementation.
  final String? offlineContentId;
  final String? offlineHtmlPath;
  final String? offlineResourcesPath;

  bool get isUnread => readAt == null;

  bool get hasOfflineCopy =>
      offlineHtmlPath != null && offlineHtmlPath!.isNotEmpty;

  ReadingItem markRead(DateTime when) => ReadingItem(
        title: title,
        url: url,
        savedAt: savedAt,
        excerpt: excerpt,
        readAt: when,
        offlineContentId: offlineContentId,
        offlineHtmlPath: offlineHtmlPath,
        offlineResourcesPath: offlineResourcesPath,
      );

  ReadingItem markUnread() => ReadingItem(
        title: title,
        url: url,
        savedAt: savedAt,
        excerpt: excerpt,
        offlineContentId: offlineContentId,
        offlineHtmlPath: offlineHtmlPath,
        offlineResourcesPath: offlineResourcesPath,
      );

  /// 摘掉离线副本引用（副本文件被清除后，条目退回联网打开）。
  ReadingItem stripOfflineCopy() => ReadingItem(
        title: title,
        url: url,
        savedAt: savedAt,
        excerpt: excerpt,
        readAt: readAt,
      );

  Map<String, Object?> toJson() => {
        'title': title,
        'url': url,
        'savedAt': savedAt.toIso8601String(),
        'excerpt': excerpt,
        if (readAt != null) 'readAt': readAt!.toIso8601String(),
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
        readAt: _nullableDate(json['readAt']),
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
  static const _recentSearchKey = 'yilan_recent_searches_v1';
  static const _sessionKey = 'yilan_browser_session_v1';
  static const _maxHistoryItems = 500;
  static const _maxRecentSearches = 12;
  static const _maxSessionTabs = 20;

  // ---------- 标签页会话（退出恢复 / 最近关闭） ----------

  /// 保存当前标签页集合（不含无痕标签页：无痕数据不落盘）。
  Future<void> saveSession(
      List<Map<String, Object?>> tabs, int activeIndex) async {
    final prefs = await SharedPreferences.getInstance();
    if (tabs.isEmpty) {
      await prefs.remove(_sessionKey);
      return;
    }
    await prefs.setString(_sessionKey, jsonEncode({
          'active': activeIndex.clamp(0, tabs.length - 1),
          'savedAt': DateTime.now().toIso8601String(),
          'tabs': tabs.take(_maxSessionTabs).toList(),
        }));
  }

  Future<BrowserSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return null;
      final tabs = <BrowserSessionTab>[];
      final rawTabs = value['tabs'];
      if (rawTabs is List) {
        for (final item in rawTabs.whereType<Map>()) {
          final url = _stringValue(item['url']);
          if (url.isEmpty) continue;
          tabs.add(BrowserSessionTab(
            url: url,
            title: _stringValue(item['title']),
          ));
        }
      }
      if (tabs.isEmpty) return null;
      final active = ((value['active'] as num?)?.toInt() ?? 0)
          .clamp(0, tabs.length - 1);
      return BrowserSession(tabs: tabs, activeIndex: active);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  /// 近期搜索词：地址栏下拉的快速检索入口（最新在前，去重，上限 12 条）。
  Future<List<String>> loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_recentSearchKey) ?? const [];
    return [
      for (final item in raw)
        if (item.trim().isNotEmpty) item.trim(),
    ];
  }

  Future<void> saveRecentSearches(List<String> queries) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = <String>{};
    final unique = <String>[];
    for (final q in queries) {
      final value = q.trim();
      if (value.isEmpty || !seen.add(value.toLowerCase())) continue;
      unique.add(value);
      if (unique.length >= _maxRecentSearches) break;
    }
    await prefs.setStringList(_recentSearchKey, unique);
  }

  Future<void> addRecentSearch(String query) async {
    final value = query.trim();
    if (value.isEmpty) return;
    final existing = await loadRecentSearches()
      ..removeWhere((q) => q.toLowerCase() == value.toLowerCase());
    await saveRecentSearches([value, ...existing]);
  }

  Future<void> removeRecentSearch(String query) async {
    final existing = await loadRecentSearches()
      ..removeWhere((q) => q.toLowerCase() == query.trim().toLowerCase());
    await saveRecentSearches(existing);
  }

  Future<void> clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSearchKey);
  }

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

  /// 把磁盘上已经不存在的离线副本从元数据与阅读清单里摘掉，
  /// 避免点开时才发现悬空。返回清理掉的副本数。
  Future<int> pruneMissingOfflineContent() async {
    final metas = await loadOfflineContent();
    var pruned = 0;
    final aliveMetas = <OfflineContentMetadata>[];
    for (final meta in metas) {
      final exists =
          meta.htmlPath.isNotEmpty && File(meta.htmlPath).existsSync();
      if (!exists) pruned++;
      if (exists) aliveMetas.add(meta);
    }
    if (pruned > 0) await saveOfflineContent(aliveMetas);

    final items = await loadReadingList();
    var stripped = 0;
    final cleaned = <ReadingItem>[];
    for (final item in items) {
      final exists = !item.hasOfflineCopy ||
          (item.offlineHtmlPath != null &&
              File(item.offlineHtmlPath!).existsSync());
      if (exists) {
        cleaned.add(item);
      } else {
        stripped++;
        cleaned.add(ReadingItem(
          title: item.title,
          url: item.url,
          savedAt: item.savedAt,
          excerpt: item.excerpt,
          readAt: item.readAt,
        ));
      }
    }
    if (stripped > 0) await saveReadingList(cleaned);
    return pruned;
  }

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

/// 冷启动恢复用的标签页集合快照。
class BrowserSession {
  const BrowserSession({required this.tabs, required this.activeIndex});

  final List<BrowserSessionTab> tabs;
  final int activeIndex;
}

class BrowserSessionTab {
  const BrowserSessionTab({required this.url, this.title = ''});

  final String url;
  final String title;
}

/// 「清除浏览数据」的范围（设置页与浏览器页共用）。
enum BrowserDataScope { history, cookies, cache, recentSearches, offlineCopies }
