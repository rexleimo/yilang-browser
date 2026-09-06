import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 应用内更新检查的数据模型与服务。
///
/// 版本源头是 GitHub Releases（与分发渠道同源）：`releases/latest` 永远指向
/// 最新发布，无需随发版维护额外清单文件。检测逻辑全部为纯函数，网络层
/// 单独注入，方便测试。

/// PackageInfo 不可用时（异常环境/测试）的兜底版本号。
/// 发版时随 pubspec.yaml 的 version 一起更新。
const String kAppVersionFallback = '0.3.0';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.tagName,
    required this.version,
    this.notes = '',
    this.apkUrl,
    this.releasePageUrl,
  });

  /// Release 标签，如 `v0.3.0`。
  final String tagName;

  /// 去掉 v 前缀后的语义版本，如 `0.3.0`。
  final String version;

  /// 发布说明（Release body，Markdown 纯文本展示）。
  final String notes;

  /// Android 安装包直链（Release 附件）；null 表示本次发布未挂 APK。
  final String? apkUrl;

  /// Release 网页（查看完整更新日志 / 手动下载）。
  final String? releasePageUrl;
}

class AppUpdateService {
  AppUpdateService({HttpClient? client}) : _client = client ?? HttpClient();

  static const repoOwner = 'rexleimo';
  static const repoName = 'yilang-browser';
  static const latestReleaseApi =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  /// 固定文件名的最新 APK 直链（release 工作流每次都挂这个副本）。
  /// Release 附件解析失败时的兜底下载地址。
  static const latestApkUrl =
      'https://github.com/$repoOwner/$repoName/releases/latest/download/yilan-browser-latest.apk';

  /// 官网（iOS 侧没有应用内安装路径，引导到官网取自签/分发方式）。
  static const websiteUrl = 'https://rexleimo.github.io/yilang-browser/';

  final HttpClient _client;

  /// 查询最新发布；任何网络/解析失败都返回 null（调用方提示稍后再试）。
  Future<AppUpdateInfo?> fetchLatest() async {
    try {
      final request =
          await _client.getUrl(Uri.parse(latestReleaseApi));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final body = await utf8.decoder.bind(response).join();
      return parseReleaseJson(jsonDecode(body));
    } catch (_) {
      return null;
    } finally {
      _client.close(force: true);
    }
  }

  /// 从 GitHub Release JSON 里提取更新信息；结构不符合预期返回 null。
  static AppUpdateInfo? parseReleaseJson(Object? json) {
    if (json is! Map) return null;
    final tagName = json['tag_name'];
    if (tagName is! String || tagName.trim().isEmpty) return null;
    final version = normalizeVersion(tagName);
    if (version == null) return null;
    return AppUpdateInfo(
      tagName: tagName.trim(),
      version: version,
      notes: json['body'] is String ? json['body'] as String : '',
      apkUrl: _pickApkUrl(json['assets']),
      releasePageUrl: json['html_url'] is String ? json['html_url'] as String : null,
    );
  }

  /// 优先取版本化命名的 APK（yilan-browser-v0.3.0.apk），
  /// 其次固定名副本（yilan-browser-latest.apk），找不到返回 null。
  static String? _pickApkUrl(Object? assets) {
    if (assets is! List) return null;
    String? fallback;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is! String || url is! String) continue;
      if (!name.toLowerCase().endsWith('.apk')) continue;
      if (!name.contains('latest')) return url;
      fallback ??= url;
    }
    return fallback;
  }

  /// `v0.3.0` / `0.3.0+5` / ` v0.3 ` → `0.3.0` 语义版本字符串；
  /// 缺失的段补 0，解析不出数字返回 null。
  static String? normalizeVersion(Object? raw) {
    if (raw is! String) return null;
    var value = raw.trim().toLowerCase();
    if (value.startsWith('v')) value = value.substring(1);
    value = value.split('+').first;
    final parts = value.split('.');
    if (parts.isEmpty || parts.length > 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part.trim());
      if (n == null || n < 0) return null;
      numbers.add(n);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return numbers.join('.');
  }

  /// 语义版本比较：-1 = a 更旧，0 = 相同，1 = a 更新。
  /// 任一版本无法解析时返回 0（按「不提示更新」处理，宁可漏提醒不误报）。
  static int compareVersions(String? a, String? b) {
    final pa = _parseTriple(a);
    final pb = _parseTriple(b);
    if (pa == null || pb == null) return 0;
    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i] > pb[i] ? 1 : -1;
    }
    return 0;
  }

  static List<int>? _parseTriple(String? raw) {
    final normalized = normalizeVersion(raw);
    if (normalized == null) return null;
    return normalized.split('.').map(int.parse).toList();
  }
}
