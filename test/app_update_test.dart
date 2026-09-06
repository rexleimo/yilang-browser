import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/core/logic/app_update.dart';

void main() {
  group('normalizeVersion', () {
    test('strips v prefix, build number, and whitespace', () {
      expect(AppUpdateService.normalizeVersion('v0.3.0'), '0.3.0');
      expect(AppUpdateService.normalizeVersion('  V1.2.3 '), '1.2.3');
      expect(AppUpdateService.normalizeVersion('0.3.0+5'), '0.3.0');
      expect(AppUpdateService.normalizeVersion('v0.3'), '0.3.0');
    });

    test('rejects non-numeric and malformed input', () {
      expect(AppUpdateService.normalizeVersion('abc'), isNull);
      expect(AppUpdateService.normalizeVersion(''), isNull);
      expect(AppUpdateService.normalizeVersion('1.2.3.4'), isNull);
      expect(AppUpdateService.normalizeVersion(null), isNull);
      expect(AppUpdateService.normalizeVersion(42), isNull);
    });
  });

  group('compareVersions', () {
    test('orders by major.minor.patch', () {
      expect(AppUpdateService.compareVersions('0.3.0', '0.2.2'), 1);
      expect(AppUpdateService.compareVersions('0.2.2', '0.3.0'), -1);
      expect(AppUpdateService.compareVersions('1.0.0', '0.9.9'), 1);
      expect(AppUpdateService.compareVersions('0.2.2', '0.2.2'), 0);
    });

    test('ignores v prefix and build number', () {
      expect(AppUpdateService.compareVersions('v0.3.0', '0.3.0+5'), 0);
      expect(AppUpdateService.compareVersions('0.3.0+7', '0.3.0+5'), 0,
          reason: '构建号不参与比较：同一版本的重复打包不提示更新');
    });

    test('unparseable versions compare as equal (no nag)', () {
      expect(AppUpdateService.compareVersions(null, '0.3.0'), 0);
      expect(AppUpdateService.compareVersions('garbage', '0.3.0'), 0);
      expect(AppUpdateService.compareVersions('0.3.0', ''), 0);
    });
  });

  group('parseReleaseJson', () {
    test('extracts tag, notes, release page, and versioned apk asset', () {
      const payload = {
        'tag_name': 'v0.3.0',
        'body': '## 更新内容\n- 应用内检查更新',
        'html_url': 'https://github.com/rexleimo/yilang-browser/releases/tag/v0.3.0',
        'assets': [
          {
            'name': 'yilan-browser-v0.3.0.apk',
            'browser_download_url':
                'https://github.com/rexleimo/yilang-browser/releases/download/v0.3.0/yilan-browser-v0.3.0.apk',
          },
          {
            'name': 'yilan-browser-v0.3.0.ipa',
            'browser_download_url':
                'https://github.com/rexleimo/yilang-browser/releases/download/v0.3.0/yilan-browser-v0.3.0.ipa',
          },
        ],
      };

      final info = AppUpdateService.parseReleaseJson(payload);
      expect(info, isNotNull);
      expect(info!.tagName, 'v0.3.0');
      expect(info.version, '0.3.0');
      expect(info.notes, contains('应用内检查更新'));
      expect(info.releasePageUrl, contains('/releases/tag/v0.3.0'));
      expect(info.apkUrl, isNotNull);
      expect(info.apkUrl, endsWith('yilan-browser-v0.3.0.apk'),
          reason: 'ipa 附件要被跳过，选中 apk');
    });

    test('falls back to the fixed-name apk copy', () {
      const payload = {
        'tag_name': 'v0.3.0',
        'assets': [
          {
            'name': 'yilan-browser-latest.apk',
            'browser_download_url':
                'https://github.com/rexleimo/yilang-browser/releases/latest/download/yilan-browser-latest.apk',
          },
        ],
      };
      final info = AppUpdateService.parseReleaseJson(payload);
      expect(info!.apkUrl, endsWith('yilan-browser-latest.apk'));
    });

    test('malformed payloads return null', () {
      expect(AppUpdateService.parseReleaseJson(null), isNull);
      expect(AppUpdateService.parseReleaseJson(<String, Object>{}), isNull);
      expect(
        AppUpdateService.parseReleaseJson(<String, Object?>{
          'tag_name': 'not-a-version',
          'assets': <Object>[],
        }),
        isNull,
      );
    });
  });
}
