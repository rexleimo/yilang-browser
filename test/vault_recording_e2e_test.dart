import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:yilan_browser/core/logic/board_model.dart';
import 'package:yilan_browser/core/models/bookmark.dart';
import 'package:yilan_browser/core/storage/bookmark_store.dart';
import 'package:yilan_browser/features/browser/browser.dart';

/// 假 WebView 平台：让 widget 测试能跑通「真实加载 → 记录写入」链路。
///
/// loadRequest 会依次触发 onPageStarted → onNavigationRequest(放行) →
/// onPageFinished，与真实内核的时序一致。
class _MemoryStore implements BookmarkStore {
  @override
  Future<List<BookmarkPage>> loadPages() async => const [];
  @override
  Future<void> savePages(List<BookmarkPage> pages) async {}
  @override
  Future<Map<String, Object?>> loadSettings() async => {};
  @override
  Future<void> saveSettings(Map<String, Object?> settings) async {}
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  void Function(String url)? onPageStartedCb;
  void Function(String url)? onPageFinishedCb;
  FutureOr<NavigationDecision> Function(NavigationRequest request)?
      onNavigationRequestCb;

  @override
  Future<void> setOnPageStarted(void Function(String url) cb) async {
    onPageStartedCb = cb;
  }

  @override
  Future<void> setOnPageFinished(void Function(String url) cb) async {
    onPageFinishedCb = cb;
  }

  @override
  Future<void> setOnNavigationRequest(
      FutureOr<NavigationDecision> Function(NavigationRequest request) cb) async {
    onNavigationRequestCb = cb;
  }

  @override
  Future<void> setOnWebResourceError(cb) async {}

  @override
  Future<void> setOnUrlChange(cb) async {}

  @override
  Future<void> setOnProgress(cb) async {}

  @override
  Future<void> setOnHttpError(cb) async {}

  @override
  Future<void> setOnHttpAuthRequest(cb) async {}

  Future<void> emitLoad(String url) async {
    onPageStartedCb?.call(url);
    if (onNavigationRequestCb != null) {
      final decision = await onNavigationRequestCb!(
          NavigationRequest(url: url, isMainFrame: true));
      if (decision == NavigationDecision.prevent) return;
    }
    onPageFinishedCb?.call(url);
  }
}

class _FakeController extends PlatformWebViewController {
  _FakeController(PlatformWebViewControllerCreationParams params)
      : super.implementation(params);

  final List<String> loadedUrls = [];
  final Map<String, JavaScriptChannelParams> channels = {};
  _FakeNavigationDelegate? navDelegate;
  String? userAgent;

  Future<void> emitLoad(String url) => navDelegate?.emitLoad(url) ?? Future.value();

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setUserAgent(String? value) async {
    userAgent = value;
  }

  @override
  Future<String?> getUserAgent() async => userAgent;

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channels[params.name] = params;
  }

  @override
  Future<void> removeJavaScriptChannel(String name) async {
    channels.remove(name);
  }

  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate delegate) async {
    navDelegate = delegate as _FakeNavigationDelegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    final url = params.uri.toString();
    loadedUrls.add(url);
    await navDelegate?.emitLoad(url);
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}

  @override
  Future<void> loadFlutterAsset(String key) async {}

  @override
  Future<void> loadFile(String absoluteFilePath) async {}

  @override
  Future<String?> currentUrl() async =>
      loadedUrls.isEmpty ? null : loadedUrls.last;

  @override
  Future<String?> getTitle() async {
    final url = await currentUrl();
    return Uri.parse(url ?? '').host;
  }

  @override
  Future<bool> canGoBack() async => false;

  @override
  Future<bool> canGoForward() async => false;

  @override
  Future<void> goBack() async {}

  @override
  Future<void> goForward() async {}

  @override
  Future<void> reload() async {}

  @override
  Future<void> clearCache() async {}

  @override
  Future<void> clearLocalStorage() async {}

  @override
  Future<void> runJavaScript(String javaScript) async {}

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async => '';

  @override
  Future<void> scrollTo(int x, int y) async {}

  @override
  Future<void> scrollBy(int x, int y) async {}

  @override
  Future<void> setVerticalScrollBarEnabled(bool enabled) async {}

  @override
  Future<void> setHorizontalScrollBarEnabled(bool enabled) async {}

  @override
  bool supportsSetScrollBarsEnabled() => false;

  @override
  Future<Offset> getScrollPosition() async => Offset.zero;

  @override
  Future<void> enableZoom(bool enabled) async {}

  @override
  Future<void> setOnPlatformPermissionRequest(cb) async {}

  @override
  Future<void> setOnConsoleMessage(cb) async {}

  @override
  Future<void> setOnScrollPositionChange(cb) async {}

  @override
  Future<void> setOnJavaScriptAlertDialog(cb) async {}

  @override
  Future<void> setOnJavaScriptConfirmDialog(cb) async {}

  @override
  Future<void> setOnJavaScriptTextInputDialog(cb) async {}
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(PlatformWebViewWidgetCreationParams params)
      : super.implementation(params);

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
          PlatformWebViewControllerCreationParams params) =>
      _FakeController(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      _FakeWebViewWidget(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      _FakeNavigationDelegate(params);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<BrowserPageState> pumpBrowser(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    // 注入假平台（此版本 setter 不接受 null，无需还原）。
    WebViewPlatform.instance = _FakeWebViewPlatform();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final model =
        BoardModel(store: _MemoryStore(), seed: const [[]]);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: BrowserPage(model: model))));
    await tester.pump();
    return tester.state<BrowserPageState>(find.byType(BrowserPage));
  }

  testWidgets(
      'browsing inside a vault tab records into the vault store, not normal history',
      (tester) async {
    final state = await pumpBrowser(tester);
    await state.vaultStore.setPassword('1234');
    state.openVaultTab();
    await tester.pump();

    state.openAddress('https://vault-news.example/secret');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(state.tabUrls.last, 'https://vault-news.example/secret');
    expect(state.tabVaultFlags.last, isTrue);
    expect(
        state.vaultStore.records.map((r) => r.url),
        contains('https://vault-news.example/secret'));
    expect(state.vaultStore.records.first.title, 'vault-news.example');

    // 冲掉截屏延迟与会话保存防抖定时器。
    await tester.pump(const Duration(seconds: 2));

    // 普通历史一次都没写过。
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('yilan_browser_history_v1'), isNull);
  });

  testWidgets(
      'regular tab browsing still records into normal history (control)',
      (tester) async {
    final state = await pumpBrowser(tester);

    state.openAddress('https://regular-site.example/page');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(state.tabUrls.first, 'https://regular-site.example/page');
    expect(state.vaultStore.records, isEmpty);

    // 冲掉截屏延迟与会话保存防抖定时器。
    await tester.pump(const Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getString('yilan_browser_history_v1');
    expect(history, isNotNull);
    expect(history, contains('https://regular-site.example/page'));
  });
}
