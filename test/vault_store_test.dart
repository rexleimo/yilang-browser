import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yilan_browser/features/browser/services/browser_data_store.dart';
import 'package:yilan_browser/features/browser/services/vault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('VaultStore password', () {
    test('setPassword unlocks and verifies', () async {
      final store = VaultStore();
      await store.load();
      expect(store.hasPassword, isFalse);

      await store.setPassword('7355608');
      expect(store.hasPassword, isTrue);
      expect(store.unlocked, isTrue);

      final second = VaultStore();
      await second.load();
      expect(second.hasPassword, isTrue);
      expect(second.unlocked, isFalse);
      expect(await second.verify('wrong-pass'), isFalse);
      expect(second.unlocked, isFalse);
      expect(await second.verify('7355608'), isTrue);
      expect(second.unlocked, isTrue);
    });

    test('password hash does not leak the plaintext', () async {
      final store = VaultStore();
      await store.load();
      await store.setPassword('super-secret-1');
      final raw = await SharedPreferences.getInstance()
          .then((prefs) => prefs.getString('yilan_vault_password_v1'));
      expect(raw, isNotNull);
      expect(raw, isNot(contains('super-secret-1')));
    });
  });

  group('VaultStore records', () {
    test('addRecord dedupes to newest and caps at 500', () async {
      final store = VaultStore();
      await store.setPassword('1234');
      for (var i = 0; i < 510; i++) {
        store.addRecord(BrowserRecord(
          title: 'page $i',
          url: 'https://v$i.example',
          visitedAt: DateTime.now(),
        ));
      }
      expect(store.records.length, 500);
      store.addRecord(BrowserRecord(
        title: 'dup',
        url: 'https://v0.example',
        visitedAt: DateTime.now(),
      ));
      expect(store.records.length, 500);
      expect(store.records.first.url, 'https://v0.example');
    });

    test('locked store ignores records', () {
      final store = VaultStore(); // 未解锁
      store.addRecord(BrowserRecord(
        title: 'x',
        url: 'https://x.example',
        visitedAt: DateTime.now(),
      ));
      expect(store.records, isEmpty);
    });

    test('records are encrypted at rest and decrypt after unlock',
        () async {
      final store = VaultStore();
      await store.load();
      await store.setPassword('1234');
      store.addRecord(BrowserRecord(
        title: '隐私页面的标题',
        url: 'https://secret-space.example/article',
        visitedAt: DateTime(2026, 9, 6),
      ));
      await store.persist();

      final blob = await SharedPreferences.getInstance()
          .then((prefs) => prefs.getString('yilan_vault_data_v1'));
      expect(blob, isNotNull);
      expect(blob, isNot(contains('secret-space')));
      expect(blob, isNot(contains('隐私页面')));

      // 模拟重启：新实例先 load（锁定）→ 输对密码 → 记录恢复。
      final restored = VaultStore();
      await restored.load();
      expect(restored.records, isEmpty);
      expect(await restored.verify('1234'), isTrue);
      expect(restored.records.length, 1);
      expect(restored.records.first.url, 'https://secret-space.example/article');
      expect(restored.records.first.title, '隐私页面的标题');
    });

    test('wrong password cannot decrypt (keeps records empty)', () async {
      final store = VaultStore();
      await store.load();
      await store.setPassword('1234');
      store.addRecord(BrowserRecord(
        title: 't',
        url: 'https://a.example',
        visitedAt: DateTime.now(),
      ));
      await store.persist();

      // 用错误密码（未经过 verify，模拟会话密钥缺失）不应解出任何记录。
      final other = VaultStore();
      await other.load();
      await other.setPassword('9999');
      other.lock();
      expect(other.records, isEmpty);
    });

    test('lock discards plaintext records; unlock restores from disk',
        () async {
      final store = VaultStore();
      await store.load();
      await store.setPassword('1234');
      store.addRecord(BrowserRecord(
        title: 't',
        url: 'https://a.example',
        visitedAt: DateTime.now(),
      ));
      await store.persist();
      store.lock();
      expect(store.records, isEmpty);
      expect(store.unlocked, isFalse);
      expect(await store.verify('1234'), isTrue);
      expect(store.records.length, 1);
    });

    test('resetRecords keeps password; resetAll wipes everything', () async {
      final store = VaultStore();
      await store.load();
      await store.setPassword('1234');
      store.addRecord(BrowserRecord(
        title: 't',
        url: 'https://a.example',
        visitedAt: DateTime.now(),
      ));

      await store.resetRecords();
      expect(store.records, isEmpty);
      expect(store.hasPassword, isTrue);

      await store.resetAll();
      expect(store.hasPassword, isFalse);
      expect(store.unlocked, isFalse);
      final second = VaultStore();
      await second.load();
      expect(second.hasPassword, isFalse);
    });
  });
}
