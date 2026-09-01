import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bookmark.dart';

/// 书签盘持久化
abstract class BookmarkStore {
  Future<List<BookmarkPage>> loadPages();
  Future<void> savePages(List<BookmarkPage> pages);
  Future<Map<String, Object?>> loadSettings();
  Future<void> saveSettings(Map<String, Object?> settings);
}

/// MVP 实现：shared_preferences（JSON 整盘存储，模型带 version 字段）
class SharedPrefsBookmarkStore implements BookmarkStore {
  SharedPrefsBookmarkStore(this._prefs);

  static const _pagesKey = 'yilan_board_v1';
  static const _settingsKey = 'yilan_settings_v1';

  final SharedPreferences _prefs;

  static Future<SharedPrefsBookmarkStore> create() async =>
      SharedPrefsBookmarkStore(await SharedPreferences.getInstance());

  @override
  Future<List<BookmarkPage>> loadPages() async {
    final raw = _prefs.getString(_pagesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return decodeBoard(raw);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> savePages(List<BookmarkPage> pages) async {
    await _prefs.setString(_pagesKey, encodeBoard(pages));
  }

  @override
  Future<Map<String, Object?>> loadSettings() async {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveSettings(Map<String, Object?> settings) async {
    await _prefs.setString(_settingsKey, jsonEncode(settings));
  }
}
