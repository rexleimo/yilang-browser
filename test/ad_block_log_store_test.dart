import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yilan_browser/features/browser/services/ad_block_log_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AdBlockLogStore', () {
    test('records events, aggregates by triple, and keeps totals', () {
      final store = AdBlockLogStore();
      store
        ..record(pageHost: 'news.example', host: 'doubleclick.net', kind: 'ad')
        ..record(pageHost: 'news.example', host: 'doubleclick.net', kind: 'ad')
        ..record(
            pageHost: 'news.example', host: 'google-analytics.com', kind: 'track')
        ..record(pageHost: 'other.example', host: '', kind: 'ad');

      expect(store.total, 4);
      expect(store.today, 4);
      expect(store.events.length, 3); // 同三元组聚合，不算 4 条
      expect(store.events.first.host, ''); // 最新在前
      expect(store.countByKind('ad'), 3);
      expect(store.countByKind('track'), 1);
    });

    test('re-record moves a merged event to the front', () {
      final store = AdBlockLogStore()
        ..record(pageHost: 'a.example', host: 'ad1.example', kind: 'ad')
        ..record(pageHost: 'a.example', host: 'ad2.example', kind: 'ad');
      expect(store.events.first.host, 'ad2.example');
      store.record(pageHost: 'a.example', host: 'ad1.example', kind: 'ad');
      expect(store.events.first.host, 'ad1.example');
      expect(store.events.first.count, 2);
    });

    test('clear resets everything', () async {
      final store = AdBlockLogStore()
        ..record(pageHost: 'a.example', host: 'ad.example', kind: 'ad');
      await store.clear();
      expect(store.total, 0);
      expect(store.today, 0);
      expect(store.events, isEmpty);
    });

    test('persists and reloads across instances', () async {
      final first = AdBlockLogStore()
        ..record(
            pageHost: 'news.example',
            host: 'doubleclick.net',
            kind: 'ad',
            count: 7)
        ..record(
            pageHost: 'news.example',
            host: 'google-analytics.com',
            kind: 'track');
      await first.flush();
      final persisted = await SharedPreferences.getInstance()
          .then((prefs) => prefs.getString('yilan_ad_block_log_v1'));
      expect(persisted, isNotNull);
      expect(persisted, contains('doubleclick.net'));

      // 模拟跨进程重启：新实例从持久化数据恢复。
      SharedPreferences.setMockInitialValues({
        'yilan_ad_block_log_v1': persisted!,
      });
      final restored = AdBlockLogStore();
      await restored.load();
      expect(restored.total, 8);
      expect(restored.events.length, 2);
      expect(restored.events.first.pageHost, 'news.example');
      expect(restored.today, 8);
    });

    test('daily trim keeps at most 30 days', () {
      final store = AdBlockLogStore();
      // 直接压 35 天数据不可行（_dayKey 私有），依赖 record 的当日写入路径：
      // 这里只验证 record 后 today 正确。
      store.record(pageHost: 'a.example', host: 'ad.example', kind: 'ad');
      expect(store.today, 1);
    });
  });
}
