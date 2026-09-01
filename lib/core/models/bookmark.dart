/// 书签实体模型（平台无关，供 UI / 存储 / 未来同步协议复用）
library;

import 'dart:convert';

/// 实体联合：书签条目 或 文件夹
sealed class BookmarkEntity {
  const BookmarkEntity();
  String get id;
  String get name;
  Map<String, Object?> toJson();

  factory BookmarkEntity.fromJson(Map<String, Object?> j) =>
      j['t'] == 'f' ? BookmarkFolder.fromJson(j) : BookmarkItem.fromJson(j);
}

/// 书签条目
class BookmarkItem extends BookmarkEntity {
  BookmarkItem({
    required this.id,
    required this.name,
    required this.url,
    this.category = '',
    this.unread = false,
    this.progress,
  });

  @override
  final String id;
  @override
  final String name;
  final String url;
  final String category;
  final bool unread;
  final double? progress; // 0-100，稍后读进度

  @override
  Map<String, Object?> toJson() => {
        't': 'b',
        'id': id,
        'name': name,
        'url': url,
        'cat': category,
        'unread': unread,
        if (progress != null) 'p': progress,
      };

  factory BookmarkItem.fromJson(Map<String, Object?> j) => BookmarkItem(
        id: j['id'] as String,
        name: j['name'] as String,
        url: j['url'] as String,
        category: (j['cat'] as String?) ?? '',
        unread: (j['unread'] as bool?) ?? false,
        progress: (j['p'] as num?)?.toDouble(),
      );
}

/// 书签文件夹
class BookmarkFolder extends BookmarkEntity {
  BookmarkFolder(
      {required this.id, required this.name, List<BookmarkEntity>? children})
      : children = children ?? [];

  @override
  final String id;
  @override
  final String name;
  final List<BookmarkEntity> children;

  @override
  Map<String, Object?> toJson() => {
        't': 'f',
        'id': id,
        'name': name,
        'children': children.map((c) => c.toJson()).toList(),
      };

  factory BookmarkFolder.fromJson(Map<String, Object?> j) => BookmarkFolder(
        id: j['id'] as String,
        name: j['name'] as String,
        children: (j['children'] as List)
            .map((c) =>
                BookmarkEntity.fromJson((c as Map).cast<String, Object?>()))
            .toList(),
      );
}

extension BookmarkEntityExt on BookmarkEntity {
  BookmarkItem? get asItem =>
      this is BookmarkItem ? this as BookmarkItem : null;
  BookmarkFolder? get asFolder =>
      this is BookmarkFolder ? this as BookmarkFolder : null;
  bool get isFolder => this is BookmarkFolder;
}

/// 一张页 = 实体列表
typedef BookmarkPage = List<BookmarkEntity>;

/// 整盘序列化（带版本号，为将来同步预留）
class BoardSnapshot {
  static const int version = 1;

  static Map<String, Object?> encode(List<BookmarkPage> pages) => {
        'v': version,
        'pages': pages.map((p) => p.map((e) => e.toJson()).toList()).toList(),
      };

  static List<BookmarkPage> decode(Map<String, Object?> json) {
    final raw = (json['pages'] as List?) ?? const [];
    return raw
        .map((p) => (p as List)
            .map((e) =>
                BookmarkEntity.fromJson((e as Map).cast<String, Object?>()))
            .toList())
        .toList();
  }
}

String encodeBoard(List<BookmarkPage> pages) =>
    jsonEncode(BoardSnapshot.encode(pages));

List<BookmarkPage> decodeBoard(String raw) =>
    BoardSnapshot.decode((jsonDecode(raw) as Map).cast<String, Object?>());
