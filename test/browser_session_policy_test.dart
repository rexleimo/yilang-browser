import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/features/browser/browser_session_policy.dart';

void main() {
  group('regular session policy', () {
    const policy = BrowserSessionPolicy.regular();

    test('retains user collections and download records', () {
      for (final data in [
        BrowserSessionData.history,
        BrowserSessionData.bookmarks,
        BrowserSessionData.readingList,
        BrowserSessionData.downloads,
      ]) {
        expect(policy.persists(data), isTrue);
        expect(policy.clearsOnClose(data), isFalse);
      }
    });

    test('does not clear cookies or cache on close', () {
      expect(policy.persists(BrowserSessionData.cookies), isTrue);
      expect(policy.persists(BrowserSessionData.cache), isTrue);
      expect(policy.closePlan.hasCleanup, isFalse);
    });

    test('is explicitly not native data isolation', () {
      expect(policy.providesNativeDataIsolation, isFalse);
    });
  });

  group('private session policy', () {
    const policy = BrowserSessionPolicy.privateSession();

    test('does not persist history, bookmarks, reading list, or downloads', () {
      for (final data in [
        BrowserSessionData.history,
        BrowserSessionData.bookmarks,
        BrowserSessionData.readingList,
        BrowserSessionData.downloads,
      ]) {
        expect(policy.persists(data), isFalse);
      }
    });

    test('clears cookies and cache when closed', () {
      expect(policy.persists(BrowserSessionData.cookies), isTrue);
      expect(policy.persists(BrowserSessionData.cache), isTrue);
      expect(policy.clearsOnClose(BrowserSessionData.cookies), isTrue);
      expect(policy.clearsOnClose(BrowserSessionData.cache), isTrue);

      final plan = policy.closePlan;
      expect(plan.clearCookies, isTrue);
      expect(plan.clearCache, isTrue);
      expect(plan.discardHistory, isTrue);
      expect(plan.discardBookmarks, isTrue);
      expect(plan.discardReadingList, isTrue);
      expect(plan.discardDownloads, isTrue);
    });

    test('does not imply native data isolation', () {
      expect(policy.providesNativeDataIsolation, isFalse);
    });
  });

  test('lifecycle closes once and is idempotent', () {
    final lifecycle = BrowserSessionLifecycle(
      const BrowserSessionPolicy.privateSession(),
    );
    expect(lifecycle.isClosed, isFalse);

    final first = lifecycle.close();
    final second = lifecycle.close();

    expect(lifecycle.isClosed, isTrue);
    expect(second.clearCookies, first.clearCookies);
    expect(second.clearCache, first.clearCache);
    expect(second.discardHistory, first.discardHistory);
  });
}
