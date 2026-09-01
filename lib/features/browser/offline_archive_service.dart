import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Saves a readable, self-contained, best-effort copy of a web document.
class OfflineArchiveService {
  OfflineArchiveService({HttpClient? client})
      : _client = client ?? HttpClient();

  final HttpClient _client;
  static final _resourcePattern = RegExp(
    r'''(?:(?:src|href)\s*=\s*|url\(\s*)(["']?)([^"'\s)]+)\1''',
    caseSensitive: false,
  );
  static final _srcsetPattern = RegExp(
    r'''(\bsrcset\s*=\s*["'])([^"']+)(["'])''',
    caseSensitive: false,
  );
  static final _charsetPattern = RegExp(
    r'''charset\s*=\s*["']?\s*([\w-]+)''',
    caseSensitive: false,
  );
  static final _metaCharsetPattern = RegExp(
    r'''<meta[^>]+charset\s*=\s*["']?\s*([\w-]+)''',
    caseSensitive: false,
  );
  static final _random = Random();

  Future<OfflineArchive> archive(Uri pageUrl, Directory destination) async {
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}';
    final temporary = Directory('${destination.path}/.archive_$id.tmp');
    final root = Directory('${destination.path}/archive_$id');
    await temporary.create(recursive: true);
    final resources = <String, _ResourceRecord>{};
    final names = <String, String>{};

    try {
      final page = await _fetch(pageUrl);
      if (page.statusCode < 200 || page.statusCode >= 300) {
        throw HttpException('Page returned HTTP ${page.statusCode}',
            uri: pageUrl);
      }
      var html = _decode(page.bytes, page.headers, allowMalformed: true);
      final context = _ArchiveContext(
        service: this,
        pageUrl: pageUrl,
        root: temporary,
        names: names,
        resources: resources,
      );
      html = await context.rewrite(html, pageUrl, isHtml: true);
      final index = File('${temporary.path}/index.html');
      await index.writeAsString(html, encoding: utf8);
      final manifest = File('${temporary.path}/manifest.json');
      await manifest.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'url': pageUrl.toString(),
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'index': 'index.html',
          'resources': resources.values.map((item) => item.toJson()).toList(),
        }),
        encoding: utf8,
      );
      if (await root.exists()) await root.delete(recursive: true);
      await temporary.rename(root.path);
      await cleanup(destination, keep: 5, except: root);
      return OfflineArchive(
        pageUrl: pageUrl,
        directory: root,
        index: File('${root.path}/index.html'),
        manifest: File('${root.path}/manifest.json'),
        assets: {
          for (final item in resources.values)
            if (item.localPath != null) item.originalUrl: item.localPath!,
        },
      );
    } catch (_) {
      if (await temporary.exists()) await temporary.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> cleanup(
    Directory destination, {
    int keep = 5,
    Directory? except,
  }) async {
    if (!await destination.exists()) return;
    final archives = await destination
        .list()
        .where(
          (entity) =>
              entity is Directory &&
              RegExp(r'^archive_').hasMatch(
                entity.uri.pathSegments
                    .where((segment) => segment.isNotEmpty)
                    .last,
              ),
        )
        .toList();
    archives
        .sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    var retained = 0;
    for (final entity in archives) {
      if (except != null && entity.path == except.path) continue;
      if (retained++ < max(0, keep)) continue;
      await entity.delete(recursive: true);
    }
  }

  Future<FetchedResource> fetch(Uri uri) => _fetch(uri);

  Future<FetchedResource> _fetch(Uri uri) async {
    final request = await _client.getUrl(uri);
    request.followRedirects = true;
    final response = await request.close();
    final bytes = await response
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
    return FetchedResource(response.statusCode, response.headers, bytes);
  }

  String decode(List<int> bytes, HttpHeaders headers) =>
      _decode(bytes, headers, allowMalformed: true);

  static String _decode(List<int> bytes, HttpHeaders headers,
      {required bool allowMalformed}) {
    final contentType = headers.contentType?.charset;
    final text = String.fromCharCodes(bytes);
    final charset = contentType ??
        _charsetPattern
            .firstMatch(headers.value('content-type') ?? '')
            ?.group(1) ??
        _metaCharsetPattern.firstMatch(text)?.group(1);
    switch (charset?.toLowerCase()) {
      case 'iso-8859-1':
      case 'latin1':
      case 'windows-1252':
        return latin1.decode(bytes, allowInvalid: allowMalformed);
      default:
        return utf8.decode(bytes, allowMalformed: allowMalformed);
    }
  }
}

class _ArchiveContext {
  _ArchiveContext(
      {required this.service,
      required this.pageUrl,
      required this.root,
      required this.names,
      required this.resources});
  final OfflineArchiveService service;
  final Uri pageUrl;
  final Directory root;
  final Map<String, String> names;
  final Map<String, _ResourceRecord> resources;
  final active = <String>{};

  Future<String> rewrite(String source, Uri base,
      {required bool isHtml}) async {
    final replacements = List<_Replacement>.empty(growable: true);
    for (final match
        in OfflineArchiveService._resourcePattern.allMatches(source)) {
      final raw = match.group(2)!;
      final local = await _localize(raw, base, isCss: !isHtml);
      if (local != null) {
        replacements.add(_Replacement(
            match.start, match.end, match.group(0)!.replaceFirst(raw, local)));
      }
    }
    if (isHtml) {
      for (final match
          in OfflineArchiveService._srcsetPattern.allMatches(source)) {
        final value = match.group(2)!;
        final parts = value.split(',');
        final rewritten = <String>[];
        for (final part in parts) {
          final bits = part.trim().split(RegExp(r'\s+'));
          if (bits.isEmpty) {
            continue;
          }
          final local = await _localize(bits.first, base);
          rewritten.add(
              '${local ?? bits.first}${bits.length > 1 ? ' ${bits.sublist(1).join(' ')}' : ''}');
        }
        replacements.add(_Replacement(match.start, match.end,
            '${match.group(1)}${rewritten.join(', ')}${match.group(3)}'));
      }
    }
    replacements.sort((a, b) => b.start.compareTo(a.start));
    for (final replacement in replacements) {
      source = source.replaceRange(
          replacement.start, replacement.end, replacement.value);
    }
    return source;
  }

  Future<String?> _localize(String raw, Uri base, {bool isCss = false}) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('#') ||
        trimmed.startsWith('data:') ||
        trimmed.startsWith('blob:') ||
        trimmed.startsWith('javascript:')) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    final resolved = base.resolveUri(uri);
    if (!_sameOrigin(resolved, pageUrl)) return null;
    final key = resolved.toString();
    final existing = names[key];
    if (existing != null) return existing;
    final record = resources.putIfAbsent(key, () => _ResourceRecord(key));
    try {
      if (active.contains(key)) return null;
      active.add(key);
      final response = await service.fetch(resolved);
      record.status = response.statusCode;
      record.mimeType = response.headers.contentType?.mimeType;
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final name =
          'resources/resource_${names.length}${_extension(resolved.path)}';
      names[key] = name;
      record.localPath = name;
      final file = File('${root.path}/$name');
      await file.parent.create(recursive: true);
      final mime = response.headers.contentType?.mimeType ?? '';
      if (mime == 'text/css' || resolved.path.toLowerCase().endsWith('.css')) {
        final css = await rewrite(
            service.decode(response.bytes, response.headers), resolved,
            isHtml: false);
        await file.writeAsString(css, encoding: utf8);
      } else {
        await file.writeAsBytes(response.bytes);
      }
      return name;
    } catch (error) {
      record.error = error.toString();
      return null;
    } finally {
      active.remove(key);
    }
  }

  bool _sameOrigin(Uri a, Uri b) {
    final port = (a.hasPort ? a.port : (a.scheme == 'https' ? 443 : 80));
    final otherPort = (b.hasPort ? b.port : (b.scheme == 'https' ? 443 : 80));
    return a.scheme == b.scheme &&
        a.host.toLowerCase() == b.host.toLowerCase() &&
        port == otherPort;
  }

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1 || path.length - dot > 8) {
      return '.bin';
    }
    final extension =
        path.substring(dot).replaceAll(RegExp(r'[^A-Za-z0-9.]'), '');
    return extension.isEmpty ? '.bin' : extension.toLowerCase();
  }
}

class _Replacement {
  const _Replacement(this.start, this.end, this.value);
  final int start;
  final int end;
  final String value;
}

class FetchedResource {
  const FetchedResource(this.statusCode, this.headers, this.bytes);
  final int statusCode;
  final HttpHeaders headers;
  final List<int> bytes;
}

class _ResourceRecord {
  _ResourceRecord(this.originalUrl);
  final String originalUrl;
  String? localPath;
  int? status;
  String? mimeType;
  String? error;
  Map<String, Object?> toJson() => {
        'url': originalUrl,
        'status': status,
        if (localPath != null) 'localPath': localPath,
        if (mimeType != null) 'mimeType': mimeType,
        if (error != null) 'error': error,
      };
}

class OfflineArchive {
  const OfflineArchive(
      {required this.pageUrl,
      required this.directory,
      required this.index,
      required this.manifest,
      required this.assets});
  final Uri pageUrl;
  final Directory directory;
  final File index;
  final File manifest;
  final Map<String, String> assets;
}
