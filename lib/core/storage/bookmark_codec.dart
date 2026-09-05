import 'dart:convert';

import '../models/bookmark.dart';

/// Netscape 书签文件（所有浏览器通用的 bookmarks.html）编解码。
///
/// 解析器是"够用就好"的容错式实现：只关心 `<h3>`（文件夹）、`<a>`（书签）、
/// `<dl>`/`</dl>`（层级进出）三种标记，任何无法识别的内容都被跳过——
/// 现实里的书签文件来自各家浏览器，标记大小写和属性顺序五花八门。
class BookmarkCodec {
  BookmarkCodec._();

  /// 把书签页序列编码成 Netscape HTML。返回的字符串可直接写盘分享。
  static String exportHtml(List<BookmarkPage> pages) {
    final buffer = StringBuffer()
      ..writeln('<!DOCTYPE NETSCAPE-Bookmark-file-1>')
      ..writeln('<!-- This is an automatically generated file. -->')
      ..writeln(
          '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">')
      ..writeln('<TITLE>Bookmarks</TITLE>')
      ..writeln('<H1>Bookmarks</H1>')
      ..writeln('<DL><p>');
    for (final page in pages) {
      for (final entity in page) {
        _writeEntity(buffer, entity, depth: 1);
      }
    }
    buffer
      ..writeln('</DL><p>')
      ..writeln();
    return buffer.toString();
  }

  static void _writeEntity(StringBuffer buffer, BookmarkEntity entity,
      {required int depth}) {
    final indent = '    ' * depth;
    final folder = entity.asFolder;
    if (folder != null) {
      final label = _escapeHtml(folder.name);
      buffer.writeln('$indent<DT><H3>$label</H3>');
      buffer.writeln('$indent<DL><p>');
      for (final child in folder.children) {
        _writeEntity(buffer, child, depth: depth + 1);
      }
      buffer.writeln('$indent</DL><p>');
      return;
    }
    final item = entity.asItem;
    if (item == null) return;
    buffer.writeln('$indent<DT><A HREF="${_escapeHtml(item.url)}">'
        '${_escapeHtml(item.name)}</A>');
  }

  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// 解析书签 HTML，返回扁平的 (文件夹路径, 名称, URL) 列表。
  ///
  /// [raw] 可以是导出的 bookmarks.html，也可以是任意包含 <a href> 的 HTML。
  static List<ImportedBookmark> parse(String raw) {
    final root = _ImportedFolder('');
    var current = root;
    final tokenizer = RegExp(
      r'<DL[^>]*>|</DL\s*>|<H3[^>]*>(.*?)</H3\s*>|<A[^>]*HREF\s*=\s*"([^"]*)"[^>]*>(.*?)</A\s*>',
      multiLine: true,
      dotAll: true,
      caseSensitive: false,
    );
    final folderStack = <_ImportedFolder>[root];
    for (final match in tokenizer.allMatches(raw)) {
      final text = match.group(0)!.toLowerCase();
      if (text.startsWith('<dl')) {
        folderStack.add(current);
      } else if (text.startsWith('</dl')) {
        if (folderStack.length > 1) folderStack.removeLast();
        current = folderStack.last;
      } else if (text.startsWith('<h3')) {
        final name = _unescapeHtml((match.group(1) ?? '').trim());
        final folder = _ImportedFolder(name);
        current.children.add(folder);
        // <h3> 后面紧跟的 <dl> 才是它的子级：先挂到当前层，遇到 <dl> 时
        // 该文件夹成为新的"当前容器"由 <dl>/<dl> 配对维护。
        folderStack[folderStack.length - 1] = folder;
        current = folder;
      } else if (text.startsWith('<a')) {
        final url = (match.group(2) ?? '').trim();
        final name =
            _stripTags(_unescapeHtml(match.group(3) ?? '')).trim();
        if (url.isEmpty || !url.contains('://')) continue;
        current.children.add(_ImportedLeaf(name.isEmpty ? url : name, url));
      }
    }
    final result = <ImportedBookmark>[];
    void walk(_ImportedFolder folder, List<String> path) {
      final nextPath =
          folder.name.isEmpty ? path : [...path, folder.name];
      for (final child in folder.children) {
        if (child is _ImportedFolder) {
          walk(child, nextPath);
        } else if (child is _ImportedLeaf) {
          result.add(ImportedBookmark(
            name: child.name,
            url: child.url,
            folderPath: nextPath,
          ));
        }
      }
    }

    walk(root, const []);
    return result;
  }

  static String _unescapeHtml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  static String _stripTags(String value) =>
      value.replaceAll(RegExp(r'<[^>]*>'), '');
}

/// 一条解析出来的书签。[folderPath] 是它在原文件里的文件夹层级，
/// 便于上层决定要不要按文件夹分组收纳。
class ImportedBookmark {
  const ImportedBookmark({
    required this.name,
    required this.url,
    this.folderPath = const [],
  });

  final String name;
  final String url;
  final List<String> folderPath;

  @override
  String toString() => jsonEncode({'name': name, 'url': url});
}

class _ImportedFolder {
  _ImportedFolder(this.name);

  final String name;
  final List<Object> children = [];
}

class _ImportedLeaf {
  _ImportedLeaf(this.name, this.url);

  final String name;
  final String url;
}
