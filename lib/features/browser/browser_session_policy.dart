/// Session-level data policy independent from any WebView implementation.
///
/// This is an application model only. It does not create a separate browser
/// profile, cookie jar, cache directory, or OS sandbox.
enum BrowserSessionKind { regular, private }

enum BrowserSessionData {
  history,
  bookmarks,
  readingList,
  downloads,
  cookies,
  cache,
}

/// The cleanup requested when a session is closed.
class SessionClosePlan {
  const SessionClosePlan({
    required this.clearCookies,
    required this.clearCache,
    required this.discardHistory,
    required this.discardBookmarks,
    required this.discardReadingList,
    required this.discardDownloads,
  });

  final bool clearCookies;
  final bool clearCache;
  final bool discardHistory;
  final bool discardBookmarks;
  final bool discardReadingList;
  final bool discardDownloads;

  bool get hasCleanup =>
      clearCookies ||
      clearCache ||
      discardHistory ||
      discardBookmarks ||
      discardReadingList ||
      discardDownloads;
}

/// Defines what application data a regular or private session may retain.
///
/// Downloads here means download *records*. Closing a private session never
/// deletes files already handed to the operating system's download manager.
class BrowserSessionPolicy {
  const BrowserSessionPolicy._({required this.kind});

  factory BrowserSessionPolicy.forKind(BrowserSessionKind kind) =>
      BrowserSessionPolicy._(kind: kind);

  const BrowserSessionPolicy.regular()
      : this._(kind: BrowserSessionKind.regular);

  const BrowserSessionPolicy.privateSession()
      : this._(kind: BrowserSessionKind.private);

  final BrowserSessionKind kind;

  bool get isPrivate => kind == BrowserSessionKind.private;

  /// Deliberately false: this policy does not provide native data isolation.
  bool get providesNativeDataIsolation => false;

  bool persists(BrowserSessionData data) {
    switch (data) {
      case BrowserSessionData.history:
      case BrowserSessionData.bookmarks:
      case BrowserSessionData.readingList:
        return !isPrivate;
      case BrowserSessionData.downloads:
        return !isPrivate;
      case BrowserSessionData.cookies:
      case BrowserSessionData.cache:
        return true;
    }
  }

  bool clearsOnClose(BrowserSessionData data) {
    if (!isPrivate) return false;
    switch (data) {
      case BrowserSessionData.cookies:
      case BrowserSessionData.cache:
        return true;
      case BrowserSessionData.history:
      case BrowserSessionData.bookmarks:
      case BrowserSessionData.readingList:
      case BrowserSessionData.downloads:
        return false;
    }
  }

  SessionClosePlan get closePlan => SessionClosePlan(
        clearCookies: clearsOnClose(BrowserSessionData.cookies),
        clearCache: clearsOnClose(BrowserSessionData.cache),
        discardHistory: isPrivate,
        discardBookmarks: isPrivate,
        discardReadingList: isPrivate,
        discardDownloads: isPrivate,
      );
}

/// Small lifecycle state machine useful to callers that own a session.
///
/// Calling [close] more than once is safe and returns the same plan. No
/// platform objects are created or touched by this class.
class BrowserSessionLifecycle {
  BrowserSessionLifecycle(this.policy);

  final BrowserSessionPolicy policy;
  bool _closed = false;

  bool get isClosed => _closed;

  SessionClosePlan close() {
    _closed = true;
    return policy.closePlan;
  }
}
