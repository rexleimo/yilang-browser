import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/bookmark.dart';
import 'bookmark_store.dart';

/// favicon 缓存行：ok=true 时 data 为站点图标字节；ok=false 为负缓存。
class FaviconRow {
  const FaviconRow({required this.ok, this.data, required this.updatedAt});

  final bool ok;
  final Uint8List? data;
  final int updatedAt; // epoch ms
}

/// SQLite3 持久化实现：
/// - board_nodes  书签树（顶层带页码，文件夹嵌套 parent_id）
/// - app_settings 设置键值
/// - favicons     站点图标二进制缓存（含负缓存，重启后不重闪）
///
/// 首次启动自动迁移 shared_preferences 里的旧 JSON 数据。
class SqliteBookmarkStore implements BookmarkStore {
  SqliteBookmarkStore._(this._db);

  final Database _db;

  static const _legacyPagesKey = 'yilan_board_v1';
  static const _legacySettingsKey = 'yilan_settings_v1';

  static Future<SqliteBookmarkStore> create() async {
    final dir = await getApplicationSupportDirectory();
    final dbPath = '${dir.path}/yilan.db';
    final db = sqlite3.open(dbPath);
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA foreign_keys=ON');
    final store = SqliteBookmarkStore._(db);
    store._ensureTables();
    await store._migrateFromPrefs();
    return store;
  }

  /// 测试用：内存库。
  factory SqliteBookmarkStore.inMemory() {
    final db = sqlite3.openInMemory();
    final store = SqliteBookmarkStore._(db);
    store._ensureTables();
    return store;
  }

  void _ensureTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS board_nodes(
        id TEXT PRIMARY KEY,
        kind INTEGER NOT NULL,
        name TEXT NOT NULL,
        url TEXT NOT NULL DEFAULT '',
        parent_id TEXT,
        page INTEGER,
        sort INTEGER NOT NULL
      )
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS favicons(
        host TEXT PRIMARY KEY,
        data BLOB,
        ok INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _migrateFromPrefs() async {
    final count =
        _db.select('SELECT COUNT(*) AS c FROM board_nodes').first['c'] as int;
    if (count > 0) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyPagesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final pages = decodeBoard(raw);
        await savePages(pages);
      } catch (_) {
        // 旧数据损坏则放弃迁移，保持空板
      }
    }
    final settingsRaw = prefs.getString(_legacySettingsKey);
    if (settingsRaw != null && settingsRaw.isNotEmpty) {
      try {
        await saveSettings(
            (jsonDecode(settingsRaw) as Map).cast<String, Object?>());
      } catch (_) {}
    }
    await prefs.remove(_legacyPagesKey);
    await prefs.remove(_legacySettingsKey);
  }

  // ---------------- 书签树 ----------------

  @override
  Future<List<BookmarkPage>> loadPages() async {
    return Future(() {
      final rows = _db.select('''
        SELECT id, kind, name, url, parent_id, page, sort
        FROM board_nodes
        ORDER BY (page IS NULL) ASC, page ASC, sort ASC
      ''');
      final entities = <String, BookmarkEntity>{};
      final folders = <String, BookmarkFolder>{};
      for (final r in rows) {
        final id = r['id'] as String;
        if (r['kind'] as int == 1) {
          final f = BookmarkFolder(id: id, name: r['name'] as String);
          entities[id] = f;
          folders[id] = f;
        } else {
          entities[id] = BookmarkItem(
            id: id,
            name: r['name'] as String,
            url: r['url'] as String,
          );
        }
      }
      final pages = <List<BookmarkEntity>>[];
      for (final r in rows) {
        final id = r['id'] as String;
        final parent = r['parent_id'] as String?;
        final e = entities[id];
        if (e == null) continue;
        final parentFolder = parent == null ? null : folders[parent];
        if (parentFolder != null) {
          parentFolder.children.add(e);
        } else {
          final pi = (r['page'] as int? ?? 0).clamp(0, 1 << 20);
          while (pages.length <= pi) {
            pages.add([]);
          }
          pages[pi].add(e);
        }
      }
      return pages;
    });
  }

  @override
  Future<void> savePages(List<BookmarkPage> pages) {
    return Future(() {
      final stmt = _db.prepare(
        'INSERT OR REPLACE INTO board_nodes(id, kind, name, url, parent_id, page, sort)'
        ' VALUES(?, ?, ?, ?, ?, ?, ?)',
      );
      _db.execute('BEGIN');
      try {
        _db.execute('DELETE FROM board_nodes');
        for (var p = 0; p < pages.length; p++) {
          for (var i = 0; i < pages[p].length; i++) {
            _insertNode(stmt, pages[p][i], null, p, i);
          }
        }
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      } finally {
        stmt.dispose();
      }
    });
  }

  void _insertNode(
      PreparedStatement stmt, BookmarkEntity e, String? parentId, int page, int sort) {
    if (e.isFolder) {
      final f = e.asFolder!;
      stmt.execute([f.id, 1, f.name, '', parentId, page, sort]);
      for (var i = 0; i < f.children.length; i++) {
        _insertNode(stmt, f.children[i], f.id, page, i);
      }
    } else {
      final it = e.asItem!;
      stmt.execute([it.id, 0, it.name, it.url, parentId, page, sort]);
    }
  }

  // ---------------- 设置 ----------------

  @override
  Future<Map<String, Object?>> loadSettings() {
    return Future(() {
      final rows = _db.select('SELECT key, value FROM app_settings');
      return <String, Object?>{
        for (final r in rows) r['key'] as String: jsonDecode(r['value'] as String),
      };
    });
  }

  @override
  Future<void> saveSettings(Map<String, Object?> settings) {
    return Future(() {
      final stmt =
          _db.prepare('INSERT OR REPLACE INTO app_settings(key, value) VALUES(?, ?)');
      _db.execute('BEGIN');
      try {
        _db.execute('DELETE FROM app_settings');
        settings.forEach((k, v) {
          stmt.execute([k, jsonEncode(v)]);
        });
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      } finally {
        stmt.dispose();
      }
    });
  }

  // ---------------- favicon 缓存 ----------------

  FaviconRow? loadFavicon(String host) {
    final rows = _db.select(
      'SELECT data, ok, updated_at FROM favicons WHERE host = ?',
      [host],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final data = r['data'];
    return FaviconRow(
      ok: (r['ok'] as int) == 1,
      data: data is Uint8List ? data : null,
      updatedAt: r['updated_at'] as int,
    );
  }

  Future<void> saveFavicon(String host, Uint8List? data) {
    return Future(() {
      _db.execute(
        'INSERT OR REPLACE INTO favicons(host, data, ok, updated_at) VALUES(?, ?, ?, ?)',
        [host, data, data == null ? 0 : 1, DateTime.now().millisecondsSinceEpoch],
      );
    });
  }

  void close() => _db.dispose();
}

/// favicon 网络抓取用的临时目录句柄（预留），当前全部走内存与 DB。
Future<Directory?> faviconTmpDir() => getTemporaryDirectory();
