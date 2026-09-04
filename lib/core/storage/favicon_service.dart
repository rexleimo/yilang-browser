import 'dart:async';
import 'dart:io' show HttpClient;
import 'dart:typed_data';
import 'dart:ui' show instantiateImageCodec;

import 'sqlite_bookmark_store.dart';

/// 站点图标缓存服务：
/// 1. DB 命中（ok=1）→ 直接返回字节（重启/更新后不闪，不重新联网）；
/// 2. 24 小时内的失败负缓存 → 直接放弃，避免每次重建反复重试；
/// 3. 未命中 → 依次尝试 apple-touch-icon.png、favicon.ico，成功即入库，
///    之后的重建全部走本地。
class FaviconService {
  FaviconService(this._store);

  static const _retryAfter = Duration(hours: 24);
  static const _maxBytes = 512 * 1024;

  final SqliteBookmarkStore _store;
  final _mem = <String, Uint8List?>{}; // host → bytes（null=已知失败）
  final _inflight = <String, Future<Uint8List?>>{};

  static FaviconService? _instance;
  static FaviconService get I => _instance!;
  static FaviconService? get maybe => _instance;
  static void init(FaviconService s) => _instance = s;

  /// 供测试注入内存库。
  static void initForTest(SqliteBookmarkStore store) {
    init(FaviconService(store));
  }

  Future<Uint8List?> get(String host) {
    final h = host.trim().toLowerCase();
    if (h.isEmpty) return Future.value(null);
    if (_mem.containsKey(h)) return Future.value(_mem[h]);
    return _inflight.putIfAbsent(h, () => _resolve(h));
  }

  Future<Uint8List?> _resolve(String host) async {
    try {
      final row = _store.loadFavicon(host);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (row != null) {
        if (row.ok && row.data != null) {
          return _mem[host] = row.data;
        }
        if (now - row.updatedAt < _retryAfter.inMilliseconds) {
          return _mem[host] = null; // 负缓存期内
        }
      }
      final bytes = await _fetch(host);
      // 入库：成功存字节，失败写负缓存
      await _store.saveFavicon(host, bytes);
      return _mem[host] = bytes;
    } catch (_) {
      _mem[host] = null;
      return null;
    } finally {
      _inflight.remove(host);
    }
  }

  /// apple-touch-icon 优先（精修方图），失败退 favicon.ico。
  /// 字节必须能解码成图才算成功，防止把 HTML 错误页当图标缓存。
  Future<Uint8List?> _fetch(String host) async {
    for (final path in const ['/apple-touch-icon.png', '/favicon.ico']) {
      try {
        final bytes = await _download('https://$host$path');
        if (bytes == null) continue;
        if (await _decodable(bytes)) return bytes;
      } catch (_) {
        // 换下一个候选
      }
    }
    return null;
  }

  Future<Uint8List?> _download(String url) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final len = resp.contentLength;
      if (len > _maxBytes) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        builder.add(chunk);
        if (builder.length > _maxBytes) return null;
      }
      final out = builder.takeBytes();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _decodable(Uint8List bytes) async {
    try {
      final codec = await instantiateImageCodec(bytes);
      codec.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }
}
