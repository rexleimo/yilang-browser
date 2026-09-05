import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../core/logic/board_model.dart';
import '../../../core/logic/search_engines.dart';
import '../../../core/logic/search_suggest.dart';
import '../../../core/models/bookmark.dart';
import '../../../theme/app_theme.dart';
import '../../downloads/download_center_page.dart';
import '../../downloads/download_controller.dart';
import '../services/browser_data_store.dart';
import '../../../core/widgets/browser_chrome.dart';
import 'browser_collections_page.dart';
import '../widgets/browser_dialogs.dart';
import 'browser_history.dart';
import '../logic/browser_javascript.dart';
import '../logic/browser_navigation.dart';
import '../logic/ad_blocker.dart';
import '../logic/reader_article.dart';
import '../services/offline_archive_service.dart';
import '../services/screenshot_service.dart';
import 'reader_page.dart';

/// Browser page with a normal new-tab flow, tabs, and private tabs.
class BrowserPage extends StatefulWidget {
  const BrowserPage({
    super.key,
    required this.model,
    this.initialUrl = '',
    this.openRequest = 0,
    this.onOpenSettings,
    this.onOpenBookmarks,
    this.onTabCountChanged,
    this.onTabsChanged,
    this.downloads,
  });

  final BoardModel model;
  final String initialUrl;
  final int openRequest;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenBookmarks;
  final ValueChanged<int>? onTabCountChanged;
  final ValueChanged<List<BrowserTabSummary>>? onTabsChanged;
  final DownloadController? downloads;

  @override
  BrowserPageState createState() => BrowserPageState();
}

class _BrowserTab {
  _BrowserTab({required this.url, required this.private})
      : title = url.isEmpty ? '新标签页' : _host(url);

  final bool private;
  String url;
  String title;
  bool loading = false;
  bool canGoBack = false;
  bool canGoForward = false;
  String? error;

  /// URL of the failed main-frame load. Chromium finishes loading its built-in
  /// error page right after onWebResourceError, so onPageFinished must not
  /// clear [error] while it still matches this URL — otherwise our error card
  /// disappears and the raw English "Web page not available" page shows.
  String? errorUrl;
  int blockedCount = 0; // 本页广告/追踪拦截计数（JS 引擎上报）
  String? previewImageUrl; // og:image / apple-touch-icon，封面兜底
  String? faviconUrl; // 站点小图标，显示在标签标题旁（浏览器 tab 习惯）
  WebViewController? controller;
  final GlobalKey previewKey = GlobalKey();
  Uint8List? previewBytes;

  static String _host(String value) {
    final host = value.replaceFirst(RegExp(r'^https?://'), '').split('/').first;
    return host.isEmpty ? '新标签页' : host;
  }
}

/// Read-only snapshot of a live browser tab, published so the Home tab strip
/// can render every open tab like iOS Safari's start page does.
class BrowserTabSummary {
  const BrowserTabSummary({
    required this.title,
    required this.private,
    this.faviconUrl,
  });

  final String title;
  final bool private;
  final String? faviconUrl;
}

class BrowserPageState extends State<BrowserPage> {
  static const MethodChannel _androidBrowser =
      MethodChannel('com.yilan.yilan_browser/android_browser');
  final List<_BrowserTab> _tabs = [];
  final TextEditingController _address = TextEditingController();
  final FocusNode _addressFocus = FocusNode();
  final GlobalKey _captureKey = GlobalKey();
  final BrowserDataStore _dataStore = BrowserDataStore();
  final List<BrowserRecord> _history = [];
  final List<ReadingItem> _readingList = [];
  List<String> _recentSearches = const [];
  int _active = 0;
  bool _showingTabs = false;
  bool _privateTabsOnly = false;
  bool _showingAddressEditor = false;
  bool _returnTabsToHome = false;
  Color _chromeColor = Colors.black;
  final Set<_BrowserTab> _pendingCaptures = {};

  /// 最近关闭的标签页（后进先出，供标签概览里一键恢复）。
  final List<_BrowserTab> _recentlyClosed = [];
  static const int _maxRecentlyClosed = 20;

  /// 会话持久化的防抖计时器（标签页频繁变动时合并写盘）。
  Timer? _sessionSaveTimer;

  /// 联网搜索建议：输入防抖 + 最近一次结果。
  Timer? _suggestDebounce;
  List<String> _remoteSuggestions = const [];
  String _remoteQuery = '';

  /// 站点权限的会话内记忆（host + 资源类型 → 是否允许）。
  final Map<String, bool> _permissionGrants = {};
  bool _permissionDialogOpen = false;

  /// 已应用到全部标签页的桌面版 UA 状态（设置变化时用于增量切换）。
  bool _appliedDesktopUA = false;

  bool get hasWebPage =>
      _currentTab.controller != null && _currentTab.url.isNotEmpty;

  /// Verification hook: build with --dart-define=YILAN_DEMO_SCRIPT=
  /// "8:https://example.org;16:back;22:reading" to walk the UI on a device
  /// while capturing screenshots. Empty in normal builds.
  static const String _demoScript = String.fromEnvironment('YILAN_DEMO_SCRIPT');

  void _runDemoScript() {
    if (_demoScript.isEmpty) return;
    for (final entry in _demoScript.split(';')) {
      final sep = entry.indexOf(':');
      if (sep <= 0) continue;
      final secs = int.tryParse(entry.substring(0, sep));
      final action = entry.substring(sep + 1);
      if (secs == null || action.isEmpty) continue;
      Future<void>.delayed(Duration(seconds: secs), () {
        if (!mounted) return;
        switch (action) {
          case 'back':
            _goBackInPage();
            break;
          case 'forward':
            _goForwardInPage();
            break;
          case 'tabs':
            _showTabs();
            break;
          case 'reading':
            _showCollection(history: false);
            break;
          case 'history':
            showHistory();
            break;
          case 'settings':
            widget.onOpenSettings?.call();
            break;
          case 'address':
            _openAddressEditor();
            break;
          case 'panel':
            _showBrowserMenu();
            break;
          case 'addreading':
            _addToReadingList();
            break;
          default:
            if (action.startsWith('http')) _go(action);
        }
      });
    }
  }

  String _normalize(String raw, {bool privateTab = false}) {
    return BrowserNavigation(
      searchEngineIndex: privateTab
          ? widget.model.settings.privateSearchEngineIndex
          : widget.model.settings.searchEngineIndex,
    ).normalize(raw);
  }

  String get _userAgent => _userAgentFor(widget.model.settings.desktopUA);

  static String _userAgentFor(bool desktop) {
    if (desktop) {
      return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36'
        : 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 '
            '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  }

  _BrowserTab get _currentTab => _tabs[_active];
  WebViewController? get _currentController => _currentTab.controller;

  /// Live tab count for Home's toolbar badge.
  int get tabCount => _tabs.length;

  /// Read-only state exposed for integration checks and shell coordination.
  List<String> get tabUrls => List.unmodifiable(_tabs.map((tab) => tab.url));

  String get activeTabUrl => _currentTab.url;

  /// Navigates the current tab from an external surface such as Home.
  ///
  /// Opening a bookmark or submitting Home's address field must not create a
  /// second tab. New tabs have a separate [openNewTab] entry point.
  void openAddress(String raw) {
    if (!mounted) return;
    final value = raw.trim();
    if (value.isEmpty) {
      _openAddressEditor();
      return;
    }
    _showingTabs = false;
    _go(value);
  }

  /// "New tab" from external surfaces: no blank page is created — the user is
  /// taken back to the 一览 home to pick a bookmark or type an address. A tab
  /// is only created once a real URL is opened.
  void openNewTab({bool private = false}) {
    if (!mounted) return;
    _showingTabs = false;
    _showingAddressEditor = false;
    widget.onOpenBookmarks?.call();
  }

  /// Opens a URL reached by tapping a Home tile.
  ///
  /// A blank new-tab page can simply receive the URL in place, but a live page
  /// must not be overwritten: open a fresh tab instead, reusing an existing
  /// tab for the same address so Home taps never pile up duplicates.
  void openInNewTab(String raw, {bool private = false}) {
    if (!mounted) return;
    final url = _normalize(raw.trim(), privateTab: private);
    if (url.isEmpty) return;
    if (!_isWebScheme(Uri.tryParse(url)?.scheme)) {
      _launchExternally(url);
      return;
    }
    _showingTabs = false;
    _showingAddressEditor = false;
    final emptyIndex =
        _tabs.indexWhere((tab) => tab.url.isEmpty && tab.controller == null);
    if (emptyIndex >= 0) {
      if (emptyIndex != _active) setState(() => _active = emptyIndex);
      _go(url);
      return;
    }
    final existing = _tabs.indexWhere((tab) => tab.url == url);
    if (existing >= 0) {
      if (existing != _active) setState(() => _active = existing);
      _address.text = url;
      return;
    }
    _addTab(url, private: private);
  }

  /// 未加载过网页的占位标签页（新标签页）。它不占用任何 tab UI：
  /// 条、角标、概览、同步给主页的摘要都把它过滤掉；用户真正打开网页时它
  /// 才「转正」。新建标签的动作直接回「一览」主页。
  static bool _isBlank(_BrowserTab tab) =>
      tab.url.isEmpty && tab.controller == null;

  /// Reports the live tab count without mutating an ancestor mid-build.
  void _notifyTabCount() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onTabCountChanged?.call(_realTabCount);
      widget.onTabsChanged?.call([
        for (final tab in _tabs)
          if (!_isBlank(tab))
            BrowserTabSummary(
              title: tab.title,
              private: tab.private,
              faviconUrl: tab.faviconUrl,
            ),
      ]);
    });
  }

  int get _realTabCount => _tabs.where((t) => !_isBlank(t)).length;

  /// Switches to [index] from an external surface (the Home tab strip).
  void selectExternalTab(int index) {
    if (!mounted) return;
    _selectTab(index);
  }

  @override
  void initState() {
    super.initState();
    _appliedDesktopUA = widget.model.settings.desktopUA;
    widget.model.addListener(_onSettingsChanged);
    _addressFocus.addListener(() {
      if (_addressFocus.hasFocus && _address.text.isNotEmpty) {
        _address.selection =
            TextSelection(baseOffset: 0, extentOffset: _address.text.length);
      }
    });
    final raw = widget.initialUrl.trim();
    _addTab(raw.isEmpty ? '' : _normalize(raw, privateTab: widget.model.settings.incognito),
        private: widget.model.settings.incognito, deferController: true);
    if (raw.isEmpty) {
      unawaited(_restoreSession());
    }
    _loadBrowserData();
    _notifyTabCount();
    _runDemoScript();
  }

  /// 冷启动恢复上次退出前的标签页集合（不含无痕标签页）。
  Future<void> _restoreSession() async {
    if (!widget.model.settings.restoreSession) return;
    final session = await _dataStore.loadSession();
    if (!mounted || session == null) return;
    // 占位标签页已无用：恢复会话时直接替换掉。
    _tabs.removeWhere(_isBlank);
    for (final entry in session.tabs) {
      _addTab(entry.url, private: false);
      if (entry.title.isNotEmpty) _tabs.last.title = entry.title;
    }
    if (_tabs.isEmpty) {
      _addTab('', private: false);
      return;
    }
    setState(() {
      _active = session.activeIndex.clamp(0, _tabs.length - 1);
      _address.text = _currentTab.url;
    });
    _notifyTabCount();
  }

  /// 标签集合或当前页变化后保存会话快照（防抖合并写入）。
  void _scheduleSessionSave() {
    _sessionSaveTimer?.cancel();
    _sessionSaveTimer = Timer(const Duration(milliseconds: 800), () {
      final tabs = [
        for (final tab in _tabs)
          if (!_isBlank(tab) && !tab.private)
            {'url': tab.url, 'title': tab.title},
      ];
      _dataStore.saveSession(tabs, _active);
    });
  }

  /// 设置里的开关变化（目前关注桌面版 UA）应用到所有标签页。
  void _onSettingsChanged() {
    if (!mounted) return;
    final desktop = widget.model.settings.desktopUA;
    if (desktop == _appliedDesktopUA) return;
    _appliedDesktopUA = desktop;
    final ua = _userAgentFor(desktop);
    for (final tab in _tabs) {
      final controller = tab.controller;
      if (controller == null) continue;
      unawaited(controller.setUserAgent(ua));
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final android = controller.platform;
          if (android is AndroidWebViewController) {
            unawaited(android.setUseWideViewPort(desktop));
          }
        } catch (_) {}
      }
    }
    final current = _currentController;
    if (current != null && _currentTab.url.isNotEmpty) {
      unawaited(current.reload());
    }
  }

  Future<void> _loadBrowserData() async {
    final history = await _dataStore.loadHistory();
    final readingList = await _dataStore.loadReadingList();
    final recent = await _dataStore.loadRecentSearches();
    if (!mounted) return;
    setState(() {
      _history
        ..clear()
        ..addAll(history);
      _readingList
        ..clear()
        ..addAll(readingList);
      _recentSearches = recent;
    });
  }

  @override
  void didUpdateWidget(covariant BrowserPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openRequest != oldWidget.openRequest) {
      final raw = widget.initialUrl.trim();
      if (raw.isEmpty &&
          _currentTab.url.isEmpty &&
          _currentTab.controller == null) {
        setState(() => _address.clear());
        return;
      }
      _addTab(raw.isEmpty ? '' : _normalize(raw, privateTab: widget.model.settings.incognito),
          private: widget.model.settings.incognito);
    }
  }

  void _addTab(String url,
      {required bool private, bool deferController = false}) {
    final tab = _BrowserTab(url: url, private: private);
    _tabs.add(tab);
    _active = _tabs.length - 1;
    _address.text = url;
    if (url.isNotEmpty) {
      tab.loading = true;
      if (deferController) {
        // Theme lookups need a completed first frame; initState cannot read them.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _tabs.contains(tab) && tab.controller == null) {
            _attachController(tab);
          }
        });
      } else {
        _attachController(tab);
      }
    }
    if (mounted) setState(() {});
    _notifyTabCount();
    _scheduleSessionSave();
  }

  WebViewController _createController(_BrowserTab tab) {
    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(context.browserTokens.webViewBackground)
      // 广告拦截计数上报（Brave Shields 式反馈）
      ..addJavaScriptChannel('yilanAdBlock', onMessageReceived: (msg) {
        final n = int.tryParse(msg.message) ?? 0;
        if (!mounted || !_tabs.contains(tab)) return;
        if (n > tab.blockedCount) {
          tab.blockedCount = n;
          if (_currentTab == tab) setState(() {});
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (value) {
          if (!mounted || !_tabs.contains(tab)) return;
          final isLocalCopy = value.startsWith('file://');
          if (!isLocalCopy) tab.url = value;
          tab.loading = true;
          tab.error = null;
          tab.errorUrl = null;
          tab.blockedCount = 0;
          // 广告拦截：尽早注入规则脚本（含 MutationObserver 兜懒加载）
          if (widget.model.settings.adBlock && !isLocalCopy) {
            unawaited(controller
                .runJavaScript(adBlockerScript())
                .then((_) {}, onError: (_) {}));
          }
          // 占位标签页从此转正 → 同步给 Home 的标签条
          _notifyTabCount();
          _scheduleSessionSave();
          if (_currentTab == tab) {
            setState(() {
              _chromeColor = Colors.black;
            });
          }
          _refreshNavigationState(tab);
        },
        onPageFinished: (value) async {
          if (!mounted || !_tabs.contains(tab)) return;
          final isLocalCopy = value.startsWith('file://');
          if (!isLocalCopy) tab.url = value;
          tab.loading = false;
          // Chromium 的内置错误页也是在"加载完成"回调里结束的：错误若属于
          // 本 URL，保留 error 卡，别把我们的错误提示擦掉露出英文错误页。
          if (tab.errorUrl == null || tab.errorUrl != value) {
            tab.error = null;
            tab.errorUrl = null;
          }
          // DOM 建好后补一遍清理（脚本幂等，MutationObserver 仍在位）
          if (widget.model.settings.adBlock && !isLocalCopy) {
            unawaited(controller
                .runJavaScript(adBlockerScript())
                .then((_) {}, onError: (_) {}));
          }
          if (_currentTab == tab && !_addressFocus.hasFocus && !isLocalCopy) {
            _address.text = value;
          }
          if (!isLocalCopy) {
            try {
              await controller.runJavaScript('''
                (function(){
                  if(window.__yilanFontInjected) return;
                  window.__yilanFontInjected=true;
                  var s=document.createElement('style');
                  s.textContent='*{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","SF Pro Display","Helvetica Neue",Arial,"PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif !important}';
                  if(document.head){document.head.appendChild(s)}else{document.documentElement.appendChild(s)};
                })();
              ''');
            } catch (_) {}
          }
          // 封面：og:image → twitter:image → apple-touch-icon，供概览大图
          if (!isLocalCopy) {
            try {
              final cover = await controller.runJavaScriptReturningResult('''
                (function(){
                  var el = document.querySelector('meta[property="og:image"]') ||
                           document.querySelector('meta[name="twitter:image"]') ||
                           document.querySelector('link[rel="apple-touch-icon"]');
                  if (!el) return '';
                  var v = el.getAttribute('content') || el.getAttribute('href') || '';
                  if (!v) return '';
                  return new URL(v, document.baseURI).href;
                })()
              ''');
              final coverStr = cover
                  .toString()
                  .trim()
                  .replaceAll("'", '')
                  .replaceAll('"', '');
              if (coverStr.isNotEmpty &&
                  coverStr != 'null' &&
                  mounted &&
                  _tabs.contains(tab)) {
                setState(() => tab.previewImageUrl = coverStr);
              }
            } catch (_) {}
          }
          // 站点小图标：与浏览器标签页的 favicon 同源
          if (!isLocalCopy) {
            try {
              final icon = await controller.runJavaScriptReturningResult('''
                (function(){
                  function abs(el){
                    if (!el) return '';
                    var v = el.getAttribute('href') || '';
                    if (!v) return '';
                    return new URL(v, document.baseURI).href;
                  }
                  var sizes = document.querySelectorAll(
                    'link[rel~="icon"], link[rel="shortcut icon"]');
                  var best = null, bestSize = 0;
                  sizes.forEach(function(el){
                    var s = parseInt(el.getAttribute('sizes') || '0') || 16;
                    if (s >= bestSize) { bestSize = s; best = el; }
                  });
                  if (best) return abs(best);
                  // 很多站点（如知乎）只有 apple-touch-icon，一并兜底
                  return abs(document.querySelector('link[rel="apple-touch-icon"]'));
                })()
              ''');
              final iconStr = icon
                  .toString()
                  .trim()
                  .replaceAll("'", '')
                  .replaceAll('"', '');
              if (iconStr.isNotEmpty &&
                  iconStr != 'null' &&
                  mounted &&
                  _tabs.contains(tab)) {
                setState(() => tab.faviconUrl = iconStr);
              }
            } catch (_) {}
          }
          try {
            final colorResult = await controller.runJavaScriptReturningResult(
              "document.querySelector('meta[name=\"theme-color\"]')?.content || ''",
            );
            final colorStr = colorResult.toString().trim();
            if (colorStr.isNotEmpty && colorStr != 'null' && colorStr != "''") {
              final color = _parseHexColor(colorStr);
              if (color != null && mounted) {
                setState(() => _chromeColor = color);
                SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
                  statusBarColor: color,
                  statusBarIconBrightness: _titleBrightness(color),
                  statusBarBrightness: _titleBrightness(color) == Brightness.light
                      ? Brightness.dark
                      : Brightness.light,
                ));
              }
            } else {
              if (mounted) setState(() => _chromeColor = Colors.black);
            }
          } catch (_) {}
          if (_currentTab == tab) setState(() {});
          final title = await controller.getTitle();
          if (!mounted || !_tabs.contains(tab)) return;
          if (title != null &&
              title.trim().isNotEmpty &&
              !value.startsWith('file://')) {
            tab.title = title.trim();
          }
          await _refreshNavigationState(tab);
          if (!tab.private && !isLocalCopy) _recordHistory(tab);
          _captureTabPreview(tab);
          // 标题/转正状态可能变化 → 同步给 Home 的标签条
          _notifyTabCount();
          _scheduleSessionSave();
          if (_currentTab == tab) setState(() {});
        },
        onNavigationRequest: (request) async {
          // 页面里点到的 App 深链交给系统；file:// 是离线副本要放行。
          final scheme =
              Uri.tryParse(request.url)?.scheme.toLowerCase() ?? '';
          const localSchemes = {'http', 'https', 'file', 'about', 'data'};
          if (scheme.isNotEmpty && !localSchemes.contains(scheme)) {
            final uri = Uri.tryParse(request.url);
            if (uri != null) {
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            }
            return NavigationDecision.prevent;
          }
          // 广告/跟踪域名的主框架跳转（弹窗、中转页）直接拦掉
          if (widget.model.settings.adBlock && isAdUrl(request.url)) {
            return NavigationDecision.prevent;
          }
          if (_looksLikeDownload(request.url)) {
            // 统一走下载中心：记录任务 + Android 托管给系统下载管理器。
            // （旧实现在这里又直接 invokeMethod 入队一次，导致系统收到两个任务。）
            if (widget.downloads != null &&
                defaultTargetPlatform == TargetPlatform.android) {
              unawaited(widget.downloads!.enqueue(request.url));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('已加入下载，可在下载中心查看进度')));
              }
              return NavigationDecision.prevent;
            }
            final uri = Uri.tryParse(request.url);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
          }
          return NavigationDecision.navigate;
        },
        onWebResourceError: (error) {
          if (!mounted ||
              !_tabs.contains(tab) ||
              error.isForMainFrame == false) {
            return;
          }
          tab.loading = false;
          tab.error = error.description;
          tab.errorUrl = error.url ?? tab.url;
          if (_currentTab == tab) setState(() {});
        },
      ));
    _configureAndroidController(controller);
    return controller;
  }

  /// Android 专属配置：站点权限对话框、地理授权、媒体自动播放、桌面宽视口。
  /// iOS 侧 WKWebView 的权限决策插件未暴露，维持系统默认行为。
  void _configureAndroidController(WebViewController controller) {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final android = controller.platform;
      if (android is! AndroidWebViewController) return;
      android
        ..setOnPlatformPermissionRequest(_handlePermissionRequest)
        ..setGeolocationPermissionsPromptCallbacks(
          onShowPrompt: _handleGeolocationPrompt,
        )
        ..setGeolocationEnabled(true)
        ..setMediaPlaybackRequiresUserGesture(false);
      if (_appliedDesktopUA) {
        unawaited(android.setUseWideViewPort(true));
      }
    } catch (_) {
      // 平台实现不可用时退回默认行为。
    }
  }

  Future<void> _handlePermissionRequest(
      PlatformWebViewPermissionRequest request) async {
    final host = Uri.tryParse(_currentTab.url)?.host ?? '';
    final types = request.types;
    if (types.isEmpty) {
      await request.deny();
      return;
    }
    final key = '$host|${types.map((t) => t.name).join(',')}';
    final cached = _permissionGrants[key];
    if (cached != null) {
      if (cached) {
        await _ensureRuntimePermissions(types);
        await request.grant();
      } else {
        await request.deny();
      }
      return;
    }
    final allowed =
        await _askSitePermission(host, _describePermissionTypes(types));
    _permissionGrants[key] = allowed;
    if (allowed) {
      await _ensureRuntimePermissions(types);
      await request.grant();
    } else {
      await request.deny();
    }
  }

  Future<GeolocationPermissionsResponse> _handleGeolocationPrompt(
      GeolocationPermissionsRequestParams request) async {
    final host = Uri.tryParse(request.origin)?.host ??
        request.origin.replaceFirst(RegExp(r'^https?://'), '');
    final key = '$host|geolocation';
    final cached = _permissionGrants[key];
    if (cached == true) {
      await _ensureLocationRuntimePermission();
      return const GeolocationPermissionsResponse(allow: true, retain: true);
    }
    final allowed = await _askSitePermission(host, const ['位置信息']);
    _permissionGrants[key] = allowed;
    if (allowed) {
      await _ensureLocationRuntimePermission();
    }
    return GeolocationPermissionsResponse(allow: allowed, retain: allowed);
  }

  Future<void> _ensureLocationRuntimePermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _androidBrowser
          .invokeMapMethod<Object?, Object?>('requestAppPermissions', {
        'permissions': <String>[
          'android.permission.ACCESS_COARSE_LOCATION',
          'android.permission.ACCESS_FINE_LOCATION',
        ],
      });
    } catch (_) {}
  }

  List<String> _describePermissionTypes(
      Set<WebViewPermissionResourceType> types) {
    return [
      for (final type in types)
        switch (type.name) {
          'camera' => '相机',
          'microphone' => '麦克风',
          'protectedMediaId' => '受保护的媒体标识',
          'midiSysex' => 'MIDI 设备',
          _ => type.name,
        }
    ];
  }

  /// 网页权限落实前，确保 App 自身持有对应的系统运行时权限
  /// （WebView 的 grant 在 App 未授权时会被系统静默拒绝）。
  Future<void> _ensureRuntimePermissions(
      Set<WebViewPermissionResourceType> types) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    const manifestPermissions = {
      'camera': 'android.permission.CAMERA',
      'microphone': 'android.permission.RECORD_AUDIO',
    };
    final permissions = [
      for (final type in types)
        if (manifestPermissions[type.name] != null)
          manifestPermissions[type.name]!,
    ];
    if (permissions.isEmpty) return;
    try {
      final result = await _androidBrowser
          .invokeMapMethod<Object?, Object?>('requestAppPermissions', {
        'permissions': permissions,
      });
      // 授权失败也不回滚网页授权：系统 WebView 侧仍会兜底校验。
      if (result == null) return;
    } catch (_) {}
  }

  Future<bool> _askSitePermission(String host, List<String> resources) async {
    if (!mounted || host.isEmpty) return false;
    if (_permissionDialogOpen) return false;
    _permissionDialogOpen = true;
    final allowed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('「$host」请求权限'),
        content: Text('该网站想使用：${resources.join('、')}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('拒绝')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('允许')),
        ],
      ),
    );
    _permissionDialogOpen = false;
    return allowed == true;
  }

  void _attachController(_BrowserTab tab) {
    // Widget tests do not register a platform WebView implementation. Keep
    // the tab state testable without pretending that a WebView was created.
    if (WebViewPlatform.instance == null) return;
    final controller = _createController(tab);
    tab.controller = controller;
    controller.setUserAgent(_userAgent).then((_) {
      if (!mounted || !_tabs.contains(tab) || tab.controller != controller) {
        return;
      }
      controller.loadRequest(Uri.parse(tab.url));
    });
  }

  /// The platform WebView owns history. Query it after every completed move.
  Future<void> _refreshNavigationState(_BrowserTab tab) async {
    final controller = tab.controller;
    if (controller == null) {
      tab.canGoBack = false;
      tab.canGoForward = false;
      return;
    }
    try {
      final canGoBack = await controller.canGoBack();
      final canGoForward = await controller.canGoForward();
      if (!mounted || !_tabs.contains(tab) || tab.controller != controller) {
        return;
      }
      final changed =
          tab.canGoBack != canGoBack || tab.canGoForward != canGoForward;
      tab.canGoBack = canGoBack;
      tab.canGoForward = canGoForward;
      if (changed && _currentTab == tab) setState(() {});
    } catch (_) {
      // A tab may close while the platform controller is answering.
    }
  }

  /// Capture the active WebView for the tab switcher. A short delay lets the
  /// platform-view texture rasterize first — capturing on the frame where the
  /// page finished produces a blank white thumbnail. Re-captured on every
  /// finished load and whenever the overview opens with a missing snapshot.
  void _captureTabPreview(_BrowserTab tab) {
    if (_pendingCaptures.contains(tab)) return;
    _pendingCaptures.add(tab);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _pendingCaptures.remove(tab);
      if (!mounted || !_tabs.contains(tab)) return;
      final boundary = tab.previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null || boundary.size.isEmpty) return;
      try {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (!mounted || data == null || !_tabs.contains(tab)) return;
        tab.previewBytes = data.buffer.asUint8List();
        if (_showingTabs) setState(() {});
      } catch (_) {
        // Some platform-view implementations cannot be captured by Flutter.
      }
    });
  }

  bool _looksLikeDownload(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return const [
      '.apk',
      '.dmg',
      '.exe',
      '.zip',
      '.rar',
      '.7z',
      '.pdf',
      '.doc',
      '.docx',
      '.xls',
      '.xlsx',
      '.ppt',
      '.pptx',
    ].any(path.endsWith);
  }

  void _recordHistory(_BrowserTab tab) {
    _history
      ..clear()
      ..addAll(BrowserHistory.record(
        _history,
        title: tab.title,
        url: tab.url,
        private: tab.private,
      ));
    _dataStore.saveHistory(_history);
  }

  /// 集中清除浏览数据（设置页「清除浏览数据」入口）。
  /// 返回各范围清理的条数，供完成提示使用。
  Future<Map<BrowserDataScope, int>> clearBrowsingData(
      Set<BrowserDataScope> scopes) async {
    final cleared = <BrowserDataScope, int>{};
    if (scopes.contains(BrowserDataScope.history)) {
      cleared[BrowserDataScope.history] = _history.length;
      _history.clear();
      await _dataStore.saveHistory(_history);
    }
    if (scopes.contains(BrowserDataScope.recentSearches)) {
      cleared[BrowserDataScope.recentSearches] = _recentSearches.length;
      await _dataStore.clearRecentSearches();
      if (mounted) setState(() => _recentSearches = const []);
    }
    if (scopes.contains(BrowserDataScope.cookies)) {
      try {
        await WebViewCookieManager().clearCookies();
        cleared[BrowserDataScope.cookies] = 1;
      } catch (_) {
        cleared[BrowserDataScope.cookies] = 0;
      }
    }
    if (scopes.contains(BrowserDataScope.cache)) {
      var clearedTabs = 0;
      for (final tab in List<_BrowserTab>.from(_tabs)) {
        final controller = tab.controller;
        if (controller == null) continue;
        try {
          await controller.clearCache();
          await controller.clearLocalStorage();
          clearedTabs++;
        } catch (_) {}
      }
      cleared[BrowserDataScope.cache] = clearedTabs;
    }
    if (scopes.contains(BrowserDataScope.offlineCopies)) {
      final metas = await _dataStore.loadOfflineContent();
      for (final meta in metas) {
        try {
          final target = meta.resourcesPath.isNotEmpty
              ? meta.resourcesPath
              : meta.htmlPath;
          if (target.isEmpty) continue;
          final dir = Directory(target);
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        } catch (_) {}
      }
      await _dataStore.clearOfflineContent();
      if (mounted) {
        setState(() {
          for (var i = 0; i < _readingList.length; i++) {
            if (_readingList[i].hasOfflineCopy) {
              _readingList[i] = _readingList[i].stripOfflineCopy();
            }
          }
        });
      }
      cleared[BrowserDataScope.offlineCopies] = metas.length;
    }
    return cleared;
  }

  Future<bool> handleBack() async {
    if (_showingAddressEditor) {
      _closeAddressEditor();
      return true;
    }
    if (_showingTabs) {
      _closeTabOverview();
      return true;
    }
    final tab = _currentTab;
    final controller = tab.controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      await _refreshNavigationState(tab);
      return true;
    }
    return false;
  }

  Future<void> _backOrBookmarks() async {
    if (!await handleBack()) {
      widget.onOpenBookmarks?.call();
    }
  }

  Future<void> _goBackInPage() async {
    final tab = _currentTab;
    final controller = tab.controller;
    if (controller == null || !await controller.canGoBack()) {
      await _refreshNavigationState(tab);
      return;
    }
    await controller.goBack();
    await _refreshNavigationState(tab);
  }

  Future<void> _goForwardInPage() async {
    final tab = _currentTab;
    final controller = tab.controller;
    if (controller == null || !await controller.canGoForward()) {
      await _refreshNavigationState(tab);
      return;
    }
    await controller.goForward();
    await _refreshNavigationState(tab);
  }

  Future<void> _closeTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];
    _rememberClosedTab(tab);
    if (tab.private && tab.controller != null) {
      await tab.controller!.clearCache();
      await tab.controller!.clearLocalStorage();
    }
    if (!mounted || !_tabs.contains(tab)) return;
    var backToHome = false;
    if (_tabs.length == 1) {
      tab.controller = null;
      tab.url = '';
      tab.title = '新标签页';
      tab.loading = false;
      tab.error = null;
      tab.errorUrl = null;
      _address.clear();
      setState(() => _showingTabs = false);
      backToHome = true; // 只剩占位页 → 直接回「一览」
    } else {
      setState(() {
        _tabs.removeAt(index);
        if (_active > index) _active--;
        if (_active >= _tabs.length) _active = _tabs.length - 1;
        _address.text = _currentTab.url;
      });
      // 关掉后没有任何真实网页了 → 回「一览」
      backToHome = _tabs.every(_isBlank);
    }
    _notifyTabCount();
    _scheduleSessionSave();
    if (backToHome) widget.onOpenBookmarks?.call();
  }

  /// 关闭普通标签页时记一份快照，供「恢复关闭的标签页」使用。
  void _rememberClosedTab(_BrowserTab tab) {
    if (tab.private || tab.url.isEmpty) return;
    _recentlyClosed.removeWhere((item) => item.url == tab.url);
    final snapshot = _BrowserTab(url: tab.url, private: false)
      ..title = tab.title;
    _recentlyClosed.add(snapshot);
    while (_recentlyClosed.length > _maxRecentlyClosed) {
      _recentlyClosed.removeAt(0);
    }
  }

  /// 一键恢复最近关闭的标签页（标签概览底部的撤销按钮）。
  void _restoreRecentlyClosed() {
    while (_recentlyClosed.isNotEmpty) {
      final entry = _recentlyClosed.removeLast();
      final existing = _tabs.indexWhere((tab) => tab.url == entry.url);
      if (existing >= 0) {
        _selectTab(existing);
        return;
      }
      _addTab(entry.url, private: false);
      return;
    }
  }

  /// 只保留当前标签页，其余全部关闭（记入最近关闭，可撤销）。
  void _closeOtherTabs() {
    if (_tabs.length < 2) return;
    final activeTab = _currentTab;
    for (final tab in List<_BrowserTab>.from(_tabs)) {
      if (identical(tab, activeTab)) continue;
      _rememberClosedTab(tab);
    }
    setState(() {
      _tabs
        ..clear()
        ..add(activeTab);
      _active = 0;
    });
    _notifyTabCount();
    _scheduleSessionSave();
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    setState(() {
      _active = index;
      _address.text = _currentTab.url;
      _showingAddressEditor = false;
      _showingTabs = false;
    });
    _scheduleSessionSave();
  }

  /// Called by Home so its tab button opens the existing tab overview.
  /// When [fromHome] is true, leaving the overview returns to Home instead of
  /// stranding the user on a blank browser tab.
  void showTabs({bool fromHome = false}) {
    if (!mounted) return;
    _addressFocus.unfocus();
    setState(() {
      _returnTabsToHome = fromHome;
      _showingAddressEditor = false;
      _showingTabs = true;
    });
    // 概览作为覆盖层显示（内容树保持挂载），打开时给缺快照的标签页补拍。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final tab in _tabs) {
        if (tab.controller != null && tab.previewBytes == null) {
          _captureTabPreview(tab);
        }
      }
    });
  }

  /// Leaves the tab overview, honouring where it was opened from.
  void _closeTabOverview({bool returnToOrigin = true}) {
    final goHome = returnToOrigin && _returnTabsToHome;
    setState(() {
      _showingTabs = false;
      _returnTabsToHome = false;
    });
    if (goHome) widget.onOpenBookmarks?.call();
  }

  /// Opens the same reading-list surface used by the browser menu.
  void showReadingList({bool fromHome = false}) {
    if (!mounted) return;
    _showingAddressEditor = false;
    setState(() => _showingTabs = false);
    _showCollection(history: false, fromHome: fromHome);
  }

  /// Opens the history surface from Home's panel.
  void showHistory({bool fromHome = false}) {
    if (!mounted) return;
    _showingAddressEditor = false;
    setState(() => _showingTabs = false);
    _showCollection(history: true, fromHome: fromHome);
  }

  /// 非 http(s) 链接（App 深链、mailto、tel 等）不进 WebView，交给系统。
  Future<void> _launchExternally(String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        ok = false;
      }
    }
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('该链接需要在安装对应 App 后才能打开')));
    }
    // 深链没有网页内容：空白占位标签页直接回「一览」主页。
    if (_isBlank(_currentTab)) {
      widget.onOpenBookmarks?.call();
    } else {
      setState(() {});
    }
  }

  static bool _isWebScheme(String? scheme) {
    final s = scheme?.toLowerCase() ?? '';
    return s.isEmpty || s == 'http' || s == 'https';
  }

  void _go(String raw) {
    final url = _normalize(raw, privateTab: _currentTab.private);
    if (!_isWebScheme(Uri.tryParse(url)?.scheme)) {
      _launchExternally(url);
      return;
    }
    // 搜索词（非网址）记入近期搜索；无痕标签页不留痕。
    final looksLikeUrl = raw.contains('://') ||
        raw.contains('.') ||
        raw.startsWith('localhost');
    if (!looksLikeUrl) unawaited(_recordRecent(raw.trim()));
    final tab = _currentTab;
    tab.url = url;
    tab.title = _BrowserTab._host(url);
    tab.error = null;
    tab.errorUrl = null;
    tab.loading = true;
    tab.canGoForward = false;
    _address.text = url;
    _addressFocus.unfocus();
    _showingAddressEditor = false;
    if (tab.controller == null) {
      _attachController(tab);
    } else {
      tab.controller!.loadRequest(Uri.parse(url));
    }
    setState(() {});
  }

  /// 用指定引擎执行"本次搜索"（地址栏下拉的引擎快切）。
  void _searchWith(int engineIndex, String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    final url = SearchEngines.searchUrl(engineIndex, q);
    _address.text = url;
    unawaited(_recordRecent(q));
    _go(url);
  }

  /// 地址栏输入变化：刷新本地建议并防抖拉取联网建议词。
  void _onAddressChanged(String value) {
    setState(() {});
    final s = widget.model.settings;
    final q = value.trim();
    if (!s.suggestRemote || _currentTab.private || q.isEmpty) {
      _suggestDebounce?.cancel();
      _remoteSuggestions = const [];
      _remoteQuery = '';
      return;
    }
    // 看起来像网址的输入不拉建议词。
    final looksLikeUrl = q.contains('://') ||
        q.contains('.') ||
        q.startsWith('localhost');
    if (looksLikeUrl) {
      _suggestDebounce?.cancel();
      _remoteSuggestions = const [];
      _remoteQuery = '';
      return;
    }
    _remoteQuery = q;
    _suggestDebounce?.cancel();
    _suggestDebounce = Timer(const Duration(milliseconds: 180), () async {
      final engine = _defaultEngineIndex;
      final list = await SearchSuggestService.fetch(engine, q);
      if (!mounted || _remoteQuery != q) return;
      setState(() => _remoteSuggestions = list);
    });
  }

  Future<void> _recordRecent(String query) async {
    if (query.isEmpty ||
        _currentTab.private ||
        !widget.model.settings.suggestRecent) {
      return;
    }
    await _dataStore.addRecentSearch(query);
    final list = await _dataStore.loadRecentSearches();
    if (mounted) setState(() => _recentSearches = list);
  }

  List<BookmarkItem> _allBookmarkItems() {
    final out = <BookmarkItem>[];
    void walk(List<BookmarkEntity> list) {
      for (final e in list) {
        final item = e.asItem;
        if (item != null) {
          out.add(item);
        } else {
          walk(e.asFolder?.children ?? const []);
        }
      }
    }

    for (final page in widget.model.pages) {
      walk(page);
    }
    return out;
  }

  /// 当前生效的默认引擎序号（无痕标签页用无痕引擎）。
  int get _defaultEngineIndex {
    final s = widget.model.settings;
    return SearchEngines.clamp(
        _currentTab.private ? s.privateSearchEngineIndex : s.searchEngineIndex);
  }

  /// "此次搜索"来源菜单（Firefox 式）：锚在地址栏 Logo 下方。
  final GlobalKey _engineButtonKey = GlobalKey();

  void _showEnginePicker() {
    showSearchSourceMenu(
      context,
      anchorKey: _engineButtonKey,
      onEngine: (i) => _searchWith(i, _address.text),
      onBookmarks: () => widget.onOpenBookmarks?.call(),
      onTabs: () => showTabs(),
      onHistory: () => showHistory(),
      onSettings: () => widget.onOpenSettings?.call(),
    );
  }

  /// 地址栏下拉建议：近期搜索 / 书签 / 历史 / 标签页。
  Widget _buildAddressSuggestions() {
    final s = widget.model.settings;
    final q = _address.text.trim().toLowerCase();
    final scheme = Theme.of(context).colorScheme;

    final rows = <Widget>[];

    Widget row({
      required Widget leading,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
      Widget? trailing,
    }) {
      return InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Row(
            children: [
              const SizedBox(width: 14),
              SizedBox(width: 24, child: Center(child: leading)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    if (subtitle != null)
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: .8))),
                  ],
                ),
              ),
              if (trailing != null) trailing,
              const SizedBox(width: 10),
            ],
          ),
        ),
      );
    }

    final recent = _recentSearches
        .where((item) => q.isEmpty || item.toLowerCase().contains(q))
        .take(q.isEmpty ? 8 : 4);
    if (s.suggestRecent && recent.isNotEmpty) {
      for (final item in recent) {
        rows.add(row(
          leading: Icon(Icons.history,
              size: 19, color: scheme.onSurfaceVariant),
          title: item,
          onTap: () => _go(item),
          trailing: IconButton(
            tooltip: '删除该记录',
            icon: Icon(Icons.close,
                size: 15, color: scheme.onSurfaceVariant.withValues(alpha: .6)),
            onPressed: () async {
              await _dataStore.removeRecentSearch(item);
              final list = await _dataStore.loadRecentSearches();
              if (mounted) setState(() => _recentSearches = list);
            },
          ),
        ));
      }
    }

    // 联网建议词：紧跟在近期搜索后面（无痕标签页不联网拉建议）。
    if (q.isNotEmpty &&
        s.suggestRemote &&
        !_currentTab.private &&
        _remoteSuggestions.isNotEmpty) {
      for (final item in _remoteSuggestions) {
        rows.add(row(
          leading: EngineLogo(index: _defaultEngineIndex, size: 18),
          title: item,
          subtitle: '用 ${SearchEngines.name(_defaultEngineIndex)} 搜索',
          onTap: () => _searchWith(_defaultEngineIndex, item),
        ));
      }
    }

    if (q.isNotEmpty && s.suggestBookmarks) {
      final hits = _allBookmarkItems()
          .where((b) =>
              b.name.toLowerCase().contains(q) ||
              b.url.toLowerCase().contains(q))
          .take(3);
      for (final b in hits) {
        rows.add(row(
          leading: Icon(Icons.star_border,
              size: 19, color: scheme.onSurfaceVariant),
          title: b.name,
          subtitle: b.url,
          onTap: () => _go(b.url),
        ));
      }
    }

    if (q.isNotEmpty && s.suggestHistory) {
      final hits = _history
          .where((h) =>
              h.title.toLowerCase().contains(q) ||
              h.url.toLowerCase().contains(q))
          .take(3);
      for (final h in hits) {
        rows.add(row(
          leading:
              Icon(Icons.schedule, size: 19, color: scheme.onSurfaceVariant),
          title: h.title.isEmpty ? h.url : h.title,
          subtitle: h.url,
          onTap: () => _go(h.url),
        ));
      }
    }

    if (q.isNotEmpty && s.suggestTabs) {
      for (var i = 0; i < _tabs.length; i++) {
        final t = _tabs[i];
        if (_isBlank(t)) continue;
        if (t.title.toLowerCase().contains(q) ||
            t.url.toLowerCase().contains(q)) {
          rows.add(row(
            leading: Icon(Icons.tab_outlined,
                size: 19, color: scheme.onSurfaceVariant),
            title: t.title,
            subtitle: t.url,
            onTap: () => _selectTab(i),
          ));
        }
      }
    }

    if (rows.isEmpty) {
      if (q.isEmpty) return const SizedBox.shrink();
      // 没命中任何来源 → 给一条默认搜索兜底；换引擎走地址栏左侧菜单
      rows.add(row(
        leading: EngineLogo(index: _defaultEngineIndex, size: 18),
        title: '搜索「${_address.text.trim()}」',
        subtitle: '用 ${SearchEngines.name(_defaultEngineIndex)} 搜索',
        onTap: () => _searchWith(_defaultEngineIndex, _address.text),
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        elevation: 6,
        shadowColor: Colors.black26,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      ),
    );
  }

  void _reload() {
    final controller = _currentController;
    if (controller == null) {
      _openAddressEditor();
      return;
    }
    controller.reload();
  }

  void _openAddressEditor() {
    setState(() {
      _showingTabs = false;
      _showingAddressEditor = true;
      _address.text = _currentTab.url;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _addressFocus.requestFocus();
    });
  }

  void _closeAddressEditor() {
    _addressFocus.unfocus();
    if (mounted) {
      setState(() => _showingAddressEditor = false);
    }
  }

  Future<void> _saveBookmark() async {
    final tab = _currentTab;
    if (tab.private) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无痕标签页不会保存书签')));
      return;
    }
    if (tab.url.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先打开一个网页')));
      return;
    }
    final name = await showBookmarkNameDialog(context, initialName: tab.title);
    if (name != null && name.isNotEmpty) {
      await widget.model.addBookmark(url: tab.url, name: name);
    }
  }

  void _showTabs() {
    showTabs();
  }

  Future<void> _findInPage() async {
    final controller = _currentController;
    if (controller == null) return;
    final query = await showFindInPageDialog(context);
    if (query == null) return;
    if (query.isEmpty) {
      try {
        await controller.runJavaScript(BrowserJavaScript.clearHighlights);
      } catch (_) {
        // 页面未加载完成或脚本注入失败时静默忽略。
      }
      return;
    }
    Object? result;
    try {
      result = await controller.runJavaScriptReturningResult(
        BrowserJavaScript.findAndHighlight(query),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前页面不支持查找高亮')),
      );
      return;
    }
    if (!mounted) return;
    // Android 返回形如 "3" 的字符串；去掉可能的引号再解析。
    final raw = result.toString().replaceAll("'", '');
    final count = int.tryParse(raw) ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('找到 $count 处匹配内容')),
    );
  }

  Future<void> _sharePage() async {
    final tab = _currentTab;
    if (tab.url.isEmpty) return;
    try {
      await Share.share('${tab.title}\n${tab.url}', subject: tab.title);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：$e')),
      );
    }
  }

  Future<void> _saveScreenshot() async {
    final tab = _currentTab;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path =
          '${directory.path}/yilan_${DateTime.now().millisecondsSinceEpoch}.png';
      final native = MethodChannelScreenshotService();
      ScreenshotResult result;
      try {
        result = await native.captureLong(
          options: ScreenshotOptions(savePath: path, sourceUrl: tab.url),
        );
      } on ScreenshotException catch (error) {
        if (error.code != ScreenshotErrorCode.unsupported) rethrow;
        result = await _captureFlutterFallback();
      }
      if (!result.hasSavedFile) {
        result = await saveScreenshotResult(result, path);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('长截图已保存：${result.path ?? path}')),
      );
      return;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('当前页面截图失败：$error')),
      );
    }
  }

  Future<ScreenshotResult> _captureFlutterFallback() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('页面尚未渲染完成');
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('无法生成图片');
      return ScreenshotResult(
        bytes: bytes.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
    } catch (error) {
      throw ScreenshotException(
        ScreenshotErrorCode.captureFailed,
        'Flutter 页面截图失败',
        details: error,
      );
    }
  }

  void _translatePage() {
    final url = _currentTab.url;
    if (url.isEmpty) return;
    _go(BrowserNavigation.translationUrl(url));
  }

  Future<void> _addToReadingList() async {
    final tab = _currentTab;
    if (tab.private || tab.url.isEmpty) return;

    var excerpt = '';
    try {
      final result = await tab.controller?.runJavaScriptReturningResult(
        BrowserJavaScript.extractText(maxLength: 500),
      );
      excerpt = result?.toString() ?? '';
    } catch (_) {}

    final entry = ReadingItem(
      title: tab.title,
      url: tab.url,
      savedAt: DateTime.now(),
      excerpt: excerpt,
    );
    _readingList.removeWhere((item) => item.url == tab.url);
    _readingList.insert(0, entry);
    await _dataStore.saveReadingList(_readingList);

    // Saving should be instant; the offline copy is filled in afterwards.
    unawaited(_archiveReadingItem(entry));
    // 阅读模式净化副本同样异步补齐（提取当前已加载的 DOM，质量最高）。
    unawaited(_captureReaderCopy(entry));
  }

  /// 阅读模式：提取当前页正文并在独立阅读页渲染。
  /// 提取失败（无正文/非文章页）时提示并留在原页。
  Future<void> _openReaderMode() async {
    final tab = _currentTab;
    if (tab.private || tab.url.isEmpty) return;
    Object? result;
    try {
      result =
          await tab.controller?.runJavaScriptReturningResult(
        BrowserJavaScript.extractArticle,
      );
    } catch (_) {}
    final article = ReaderArticle.fromJsResult(result);
    if (!mounted) return;
    if (article == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此页面暂不适合阅读模式')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderPage(article: article),
      ),
    );
  }

  /// 保存进阅读清单时异步生成阅读模式副本：
  /// 在页面尚未离开时提取 DOM（结构最完整），写盘后回填 readerHtmlPath。
  Future<void> _captureReaderCopy(ReadingItem entry) async {
    Object? result;
    try {
      result =
          await _currentTab.controller?.runJavaScriptReturningResult(
        BrowserJavaScript.extractArticle,
      );
    } catch (_) {
      return;
    }
    final article = ReaderArticle.fromJsResult(result);
    if (article == null) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
          '${directory.path}/reader_${DateTime.now().microsecondsSinceEpoch}.html');
      await file.writeAsString(readerHtmlDocument(article), flush: true);
      final index = _readingList.indexWhere((item) => item.url == entry.url);
      if (index < 0) return;
      _readingList[index] = _readingList[index].withReaderCopy(file.path);
      await _dataStore.saveReadingList(_readingList);
      if (mounted) setState(() {});
    } catch (_) {
      // 阅读副本生成失败不影响条目本身（在线/离线路径仍可用）。
    }
  }

  Future<void> _archiveReadingItem(ReadingItem entry) async {
    final pageUri = Uri.tryParse(entry.url);
    if (pageUri == null ||
        (pageUri.scheme != 'http' && pageUri.scheme != 'https')) {
      return;
    }
    try {
      final directory = await getApplicationDocumentsDirectory();
      final archive = await OfflineArchiveService().archive(pageUri, directory);
      await _dataStore.upsertOfflineContent(
        OfflineContentMetadata(
          id: archive.directory.path,
          url: entry.url,
          downloadedAt: DateTime.now(),
          htmlPath: archive.index.path,
          resourcesPath: archive.directory.path,
          byteLength: await archive.index.length(),
        ),
      );
      final index = _readingList.indexWhere((item) => item.url == entry.url);
      if (index < 0) return;
      _readingList[index] = ReadingItem(
        title: entry.title,
        url: entry.url,
        savedAt: entry.savedAt,
        excerpt: entry.excerpt,
        offlineContentId: archive.directory.path,
        offlineHtmlPath: archive.index.path,
        offlineResourcesPath: archive.directory.path,
      );
      await _dataStore.saveReadingList(_readingList);
      if (mounted) setState(() {});
      unawaited(_pruneDanglingOfflineCopies());
    } catch (_) {
      // The online entry remains usable when archiving is unavailable.
    }
  }

  void _showCollection({required bool history, bool fromHome = false}) {
    final entries = history
        ? _history
            .map((item) => CollectionEntry(
                  title: item.title,
                  url: item.url,
                  time: item.visitedAt,
                ))
            .toList()
        : _readingList
            .map((item) => CollectionEntry(
                  title: item.title,
                  url: item.url,
                  time: item.savedAt,
                  excerpt: item.excerpt,
                  offlineHtmlPath: item.offlineHtmlPath,
                  readerHtmlPath: item.readerHtmlPath,
                  readAt: item.readAt,
                ))
            .toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowserCollectionPage(
          history: history,
          items: entries,
          onBack: () {
            Navigator.of(context).pop();
            if (fromHome) widget.onOpenBookmarks?.call();
          },
          onOpen: (entry) {
            Navigator.of(context).pop();
            if (!history) _markReadingItemRead(entry.url);
            if (!history && entry.hasOfflineCopy) {
              _openOfflineCopy(entry);
            } else {
              _go(entry.url);
            }
          },
          onConvert: !history
              ? (entry) => _convertReadingItemToBookmark(entry)
              : null,
          onRemove: (url) async {
            if (history) {
              setState(() => _history.removeWhere((item) => item.url == url));
              await _dataStore.saveHistory(_history);
            } else {
              setState(
                  () => _readingList.removeWhere((item) => item.url == url));
              await _dataStore.saveReadingList(_readingList);
            }
          },
          onClear: () async {
            if (history) {
              _history.clear();
              await _dataStore.saveHistory(_history);
            } else {
              _readingList.clear();
              await _dataStore.saveReadingList(_readingList);
            }
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  /// 打开阅读清单条目即视为已读（稍后读队列的收尾动作）。
  Future<void> _markReadingItemRead(String url) async {
    final index = _readingList.indexWhere((item) => item.url == url);
    if (index < 0 || !_readingList[index].isUnread) return;
    setState(() {
      _readingList[index] = _readingList[index].markRead(DateTime.now());
    });
    await _dataStore.saveReadingList(_readingList);
  }

  /// 把阅读清单条目转成首页书签（收藏 = 图书馆，清单 = 待办，互通不重复）。
  Future<void> _convertReadingItemToBookmark(CollectionEntry entry) async {
    await widget.model
        .addBookmark(url: entry.url, name: entry.title.isEmpty
            ? entry.url : entry.title);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已收藏到书签：${entry.title.isEmpty
          ? entry.url : entry.title}')),
    );
  }

  /// 归档结束后顺手摘掉磁盘上已不存在的离线副本引用（自愈）。
  Future<void> _pruneDanglingOfflineCopies() async {
    final pruned = await _dataStore.pruneMissingOfflineContent();
    if (pruned == 0 || !mounted) return;
    final items = await _dataStore.loadReadingList();
    if (!mounted) return;
    setState(() {
      _readingList
        ..clear()
        ..addAll(items);
    });
  }

  /// Reads a saved copy in a dedicated tab so the live page's
  /// browsing history stays untouched.
  /// 优先阅读模式净化副本（干净省流），缺失时回落原始离线快照。
  void _openOfflineCopy(CollectionEntry entry) {
    final readerPath = entry.readerHtmlPath;
    final readerFile = (readerPath != null && readerPath.isNotEmpty)
        ? File(readerPath)
        : null;
    if (readerFile != null && readerFile.existsSync()) {
      final tab = _BrowserTab(url: entry.url, private: false)
        ..title = entry.title.isEmpty ? '阅读模式' : entry.title;
      final controller = _createController(tab)
        ..setBackgroundColor(const Color(0xFFFBFBF8));
      tab.controller = controller;
      controller.loadFile(readerFile.path);
      _tabs.add(tab);
      _active = _tabs.length - 1;
      _address.text = entry.url;
      setState(() {
        _showingTabs = false;
        _showingAddressEditor = false;
      });
      _notifyTabCount();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已用阅读模式打开保存的文章')),
      );
      return;
    }
    final file = File(entry.offlineHtmlPath!);
    if (!file.existsSync()) {
      _go(entry.url);
      return;
    }
    final tab = _BrowserTab(url: entry.url, private: false)
      ..title = entry.title.isEmpty ? '离线阅读' : entry.title;
    final controller = _createController(tab)..setBackgroundColor(Colors.white);
    tab.controller = controller;
    controller.loadFile(file.path);
    _tabs.add(tab);
    _active = _tabs.length - 1;
    _address.text = entry.url;
    setState(() {
      _showingTabs = false;
      _showingAddressEditor = false;
    });
    _notifyTabCount();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在离线阅读已保存的副本')),
    );
  }

  void _showBrowserMenu() {
    final blocked = _currentTab.blockedCount;
    showBrowserMenuSheet(context, categories: [
      if (widget.model.settings.adBlock)
        BrowserMenuCategory(
          icon: Icons.shield_outlined,
          title: '防护',
          subtitle: '广告与追踪拦截（本页 $blocked 项）',
          actions: [
            menuTile(context, icon: Icons.shield_moon_outlined,
                title: '已拦截 $blocked 项', onTap: () {}),
          ],
        ),
      BrowserMenuCategory(
        icon: Icons.build_outlined,
        title: '页面工具',
        subtitle: '查找、截图、分享、翻译',
        actions: [
          menuTile(context, icon: Icons.search, title: '搜索或输入网址', onTap: () {
            Navigator.pop(context);
            _openAddressEditor();
          }),
          menuTile(context, icon: Icons.find_in_page_outlined, title: '在页面中查找',
              onTap: () {
            Navigator.pop(context);
            _findInPage();
          }),
          menuTile(context, icon: Icons.chrome_reader_mode_outlined,
              title: '阅读模式',
              subtitle: '只保留正文与图片', onTap: () {
            Navigator.pop(context);
            _openReaderMode();
          }),
          menuTile(context,
              icon: Icons.screenshot_outlined,
              title: '保存页面截图',
              subtitle: '当前内核优先截取可见区域', onTap: () {
            Navigator.pop(context);
            _saveScreenshot();
          }),
          menuTile(context, icon: Icons.share_outlined, title: '分享页面', onTap: () {
            Navigator.pop(context);
            _sharePage();
          }),
          menuTile(context, icon: Icons.translate, title: '翻译为中文', onTap: () {
            Navigator.pop(context);
            _translatePage();
          }),
        ],
      ),
      BrowserMenuCategory(
        icon: Icons.collections_bookmark_outlined,
        title: '收藏与阅读',
        subtitle: '收藏网页、阅读清单',
        actions: [
          menuTile(context, icon: Icons.star_border, title: '收藏网页', onTap: () {
            Navigator.pop(context);
            _saveBookmark();
          }),
          menuTile(context, icon: Icons.bookmark_add_outlined, title: '加入阅读清单',
              onTap: () {
            Navigator.pop(context);
            _addToReadingList();
          }),
          menuTile(context, icon: Icons.chrome_reader_mode_outlined, title: '阅读清单',
              onTap: () {
            Navigator.pop(context);
            _showCollection(history: false);
          }),
        ],
      ),
      BrowserMenuCategory(
        icon: Icons.history,
        title: '浏览数据',
        subtitle: '历史记录',
        actions: [
          menuTile(context, icon: Icons.history, title: '历史记录', onTap: () {
            Navigator.pop(context);
            _showCollection(history: true);
          }),
        ],
      ),
      if (widget.downloads != null)
        BrowserMenuCategory(
          icon: Icons.download_outlined,
          title: '下载中心',
          subtitle: '查看下载任务',
          actions: [
            menuTile(context, icon: Icons.download_outlined, title: '查看下载任务',
                onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      DownloadCenterPage(controller: widget.downloads!),
                ),
              );
            }),
          ],
        ),
      BrowserMenuCategory(
        icon: Icons.tab_outlined,
        title: '标签页',
        subtitle: '无痕浏览、整理标签页',
        actions: [
          menuTile(context, icon: Icons.visibility_off_outlined, title: '新建无痕标签页',
              onTap: () {
            Navigator.pop(context);
            _addTab('', private: true);
          }),
          menuTile(context, icon: Icons.delete_sweep_outlined, title: '关闭其他标签页',
              onTap: () {
            Navigator.pop(context);
            _closeOtherTabs();
          }),
        ],
      ),
      BrowserMenuCategory(
        icon: Icons.settings_outlined,
        title: '设置',
        subtitle: '搜索引擎、无痕浏览等',
        actions: [
          menuTile(context, icon: Icons.settings_outlined, title: '浏览器设置',
              onTap: () {
            Navigator.pop(context);
            widget.onOpenSettings?.call();
          }),
        ],
      ),
    ]);
  }

  /// Chromium 的 net::ERR_* 描述转成人话；没匹配上就原样展示。
  static String _friendlyLoadError(String raw) {
    const map = <String, String>{
      'ERR_INTERNET_DISCONNECTED': '网络未连接，请检查网络后重试',
      'ERR_CONNECTION_TIMED_OUT': '连接超时，站点可能暂时不可用',
      'ERR_TIMED_OUT': '连接超时，站点可能暂时不可用',
      'ERR_CONNECTION_REFUSED': '站点拒绝了连接',
      'ERR_NAME_NOT_RESOLVED': '找不到该网站，检查网址是否正确',
      'ERR_ADDRESS_UNREACHABLE': '无法访问该地址',
      'ERR_BLOCKED_BY_ADMINISTRATOR': '该地址已被阻止访问',
      'ERR_ACCESS_DENIED': '访问被拒绝',
      'ERR_CACHE_MISS': '页面缓存已失效，请重新加载',
      'ERR_ABORTED': '加载被中断，请重新打开',
    };
    for (final entry in map.entries) {
      if (raw.contains(entry.key)) return entry.value;
    }
    return raw;
  }

  Widget _tabContent(_BrowserTab tab) {
    if (tab.controller == null) {
      // URL 已定但 WebView 还没挂上（首帧主题依赖导致延后挂载）：
      // 显示加载占位，避免闪现"新标签页"引导卡。
      if (tab.url.isNotEmpty || tab.loading) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
      }
      return _NewTabView(
        private: tab.private,
        onFocusAddress: _openAddressEditor,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (tab.error != null)
          // 出错时盖住 WebView：Chromium 会渲染自己的英文错误页，
          // 留着它就会从我们错误卡底下露出来。
          ColoredBox(color: Theme.of(context).colorScheme.surface)
        else
          WebViewWidget(controller: tab.controller!),
        if (tab.loading)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (tab.error != null)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                margin: const EdgeInsets.all(24),
                elevation: 8,
                shadowColor: Colors.black26,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 30, 28, 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.wifi_off_outlined,
                            size: 30,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer),
                      ),
                      const SizedBox(height: 16),
                      const Text('网页暂时无法加载',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(_friendlyLoadError(tab.error!),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                          onPressed: _reload,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新加载')),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopTabStrip(BrowserDesignTokens tokens) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: tokens.chromeBackground,
        border: Border(bottom: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 0),
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final item = _tabs[index];
                final selected = index == _active;
                return Material(
                  color:
                      selected ? tokens.toolbarBackground : Colors.transparent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                  child: InkWell(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(10),
                    ),
                    onTap: () => _selectTab(index),
                    child: SizedBox(
                      width: 210,
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(
                            item.private
                                ? Icons.visibility_off_outlined
                                : Icons.public,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭标签页',
                            onPressed: () => _closeTab(index),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: '新建标签页',
            onPressed: () =>
                _addTab('', private: widget.model.settings.incognito),
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildTabOverview() {
    final tokens = context.browserTokens;
    final visible = <int>[
      for (var i = 0; i < _tabs.length; i++)
        if (!_isBlank(_tabs[i]) && (!_privateTabsOnly || _tabs[i].private)) i,
    ];
    final scheme = Theme.of(context).colorScheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: ColoredBox(
        color: tokens.chromeBackground,
        child: SafeArea(
          child: Column(
            children: [
              // Vivaldi 式总览头部：大标题 + 计数，右上角 X 关闭
              _OverviewEntrance(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 8, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _privateTabsOnly ? '无痕标签页' : '标签页（$_realTabCount）',
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: '完成',
                        onPressed: _closeTabOverview,
                        icon: const Icon(Icons.close, size: 24),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_privateTabsOnly
                                    ? Icons.visibility_off_outlined
                                    : Icons.tab_outlined,
                                size: 40, color: scheme.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(_privateTabsOnly ? '还没有无痕标签页' : '暂无打开的标签页'),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: .78,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, position) {
                          final index = visible[position];
                          final item = _tabs[index];
                          final selected = index == _active;
                          final location = item.url.isEmpty
                              ? '新标签页'
                              : _BrowserTab._host(item.url);
                          return _TabPreviewCard(
                            item: item,
                            selected: selected,
                            location: location,
                            onTap: () => _selectTab(index),
                            onClose: () => _closeTab(index),
                          );
                        },
                      ),
              ),
              // Vivaldi 式底部：中央悬浮 pill（计数/无痕筛选/关闭其他）+ 右侧 FAB 新建
              _OverviewEntrance(
                delay: const Duration(milliseconds: 60),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: SizedBox(
                      height: 56,
                      child: Stack(
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              decoration: BoxDecoration(
                                color: tokens.toolbarBackground,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: tokens.divider),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x161E2846),
                                    blurRadius: 14,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              height: 52,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 计数：与旁边图标同视觉重量（无边框方块）
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Center(
                                      child: Text(
                                        '$_realTabCount',
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 17,
                                          height: 1,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: IconButton(
                                      tooltip: '恢复关闭的标签页',
                                      onPressed: _recentlyClosed.isEmpty
                                          ? null
                                          : _restoreRecentlyClosed,
                                      padding: EdgeInsets.zero,
                                      icon: Icon(
                                        Icons.restore_outlined,
                                        size: 22,
                                        color: _recentlyClosed.isEmpty
                                            ? scheme.onSurfaceVariant
                                                .withValues(alpha: .35)
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: IconButton(
                                      tooltip: '只看无痕',
                                      onPressed: () => setState(() =>
                                          _privateTabsOnly =
                                              !_privateTabsOnly),
                                      padding: EdgeInsets.zero,
                                      icon: Icon(
                                        Icons.visibility_off_outlined,
                                        size: 22,
                                        color: _privateTabsOnly
                                            ? AppColors.brandStrong
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: IconButton(
                                      tooltip: '关闭其他',
                                      onPressed: _tabs.length < 2
                                          ? null
                                          : _closeOtherTabs,
                                      padding: EdgeInsets.zero,
                                      icon: Icon(
                                        Icons.delete_sweep_outlined,
                                        size: 22,
                                        color: _tabs.length < 2
                                            ? scheme.onSurfaceVariant
                                                .withValues(alpha: .35)
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Material(
                              color: AppColors.brand,
                              borderRadius: BorderRadius.circular(999),
                              elevation: 3,
                              shadowColor: const Color(0x334353C4),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  // 新建标签 = 回「一览」主页（不产生空白标签页）
                                  _closeTabOverview(returnToOrigin: false);
                                  widget.onOpenBookmarks?.call();
                                },
                                child: const SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: Icon(Icons.add,
                                      color: Colors.white, size: 26),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color? _parseHexColor(String input) {
    var hex = input.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 3) {
      hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
    }
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    return Color(int.tryParse(hex, radix: 16) ?? 0);
  }

  static Brightness _titleBrightness(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
  }

  @override
  void dispose() {
    widget.model.removeListener(_onSettingsChanged);
    _sessionSaveTimer?.cancel();
    _suggestDebounce?.cancel();
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  Widget _tabCountButton() {
    final count = _realTabCount;
    return BrowserToolbarButton(
      key: const ValueKey('tab-count-button'),
      tooltip: '标签页',
      icon: Icons.copy_outlined,
      onPressed: _showTabs,
      badge: count == 0 ? null : '$count',
    );
  }

  Widget _chromeButton({
    required String tooltip,
    required IconData icon,
    VoidCallback? onPressed,
    bool selected = false,
    Key? key,
  }) {
    return BrowserToolbarButton(
      key: key,
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
      selected: selected,
    );
  }

  Widget _buildMobileTabStrip(BrowserDesignTokens tokens) {
    return BrowserTabStrip(
      scrollable: true,
      // 新建标签不产生空白页：回到「一览」主页挑书签或输入网址。
      onNewTab: () => widget.onOpenBookmarks?.call(),
      chips: [
        for (var i = 0; i < _tabs.length; i++)
          if (!_isBlank(_tabs[i]))
            BrowserTabChip(
              label: _tabs[i].title,
              selected: i == _active,
              private: _tabs[i].private,
              faviconUrl: _tabs[i].faviconUrl,
              onTap: () => _selectTab(i),
              onClose: _tabs.length > 1 ? () => _closeTab(i) : null,
            ),
      ],
    );
  }

  Widget _buildMobileOmnibox(_BrowserTab tab) {
    final location = tab.url.isEmpty ? '' : tab.url;
    return BrowserOmnibox(
      controller: _address,
      focusNode: _addressFocus,
      hintText: '搜索或输入网址',
      displayText: location,
      editing: _showingAddressEditor,
      onActivate: _openAddressEditor,
      onSubmit: _go,
      onChanged: _onAddressChanged,
      onEngineTap: _showEnginePicker,
      engineButtonKey: _engineButtonKey,
      engineIndex: _defaultEngineIndex,
      onClose: _closeAddressEditor,
      private: tab.private,
      insecure: tab.url.startsWith('http://'),
      onReload: tab.controller == null ? null : _reload,
    );
  }

  Widget _buildMobileBottomToolbar(
      _BrowserTab tab, BrowserDesignTokens tokens) {
    return BrowserToolbarFrame(
      keyName: 'browser-browser-toolbar',
      buttons: [
        _chromeButton(
          tooltip: '面板',
          icon: Icons.view_sidebar_outlined,
          onPressed: _showBrowserMenu,
        ),
        _chromeButton(
          key: const ValueKey('nav-back-button'),
          tooltip: '后退',
          icon: Icons.arrow_back,
          onPressed: tab.canGoBack ? _goBackInPage : null,
        ),
        _chromeButton(
          tooltip: '回到 Home',
          icon: Icons.home,
          onPressed: widget.onOpenBookmarks,
          selected: false,
        ),
        _chromeButton(
          key: const ValueKey('nav-forward-button'),
          tooltip: '前进',
          icon: Icons.arrow_forward,
          onPressed: tab.canGoForward ? _goForwardInPage : null,
        ),
        _tabCountButton(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = _currentTab;
    final tokens = context.browserTokens;
    final desktop = MediaQuery.sizeOf(context).width >= 840;
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // While the address editor is open the keyboard must not cover it: lift
    // the whole chrome above the keyboard, mirroring the old resize behavior
    // but only for the editing state. Normal browsing never resizes.
    final keyboardLift =
        !desktop && _showingAddressEditor ? MediaQuery.viewInsetsOf(context).bottom : 0.0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: _chromeColor,
        statusBarIconBrightness: _titleBrightness(_chromeColor),
        statusBarBrightness: _titleBrightness(_chromeColor) == Brightness.light
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarColor: const Color(0xFFF5F7FB),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: ColoredBox(
        color: tokens.chromeBackground,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                if (!desktop && topInset > 0)
                  SizedBox(
                    height: topInset,
                    child: ColoredBox(color: _chromeColor),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: keyboardLift),
                    child: Column(
                      children: [
                        if (desktop) _buildDesktopTabStrip(tokens),
                  if (desktop)
                    Container(
                      color: tokens.toolbarBackground,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: SafeArea(
                        bottom: false,
                        child: Row(
                          children: [
                            _chromeButton(
                                tooltip: '后退 / 返回书签',
                                icon: Icons.arrow_back_ios_new,
                                onPressed: _backOrBookmarks),
                            const SizedBox(width: 6),
                            _chromeButton(
                                tooltip: '网页前进',
                                icon: Icons.arrow_forward_ios,
                                onPressed:
                                    tab.canGoForward ? _goForwardInPage : null),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _address,
                                focusNode: _addressFocus,
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.go,
                                textCapitalization: TextCapitalization.none,
                                autocorrect: false,
                                 enableSuggestions: false,
                                 onSubmitted: _go,
                                 onChanged: _onAddressChanged,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: tokens.addressBarForeground,
                                    fontWeight: FontWeight.w500),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  prefixIcon: Icon(
                                      tab.private
                                          ? Icons.visibility_off_outlined
                                          // 明文 http 不亮锁：锁只属于 https。
                                          : (tab.url.startsWith('https://') ||
                                                  tab.url.isEmpty)
                                              ? Icons.lock_outline
                                              : Icons.language,
                                      size: 17),
                                  hintText: '搜索或输入网址',
                                  suffixIcon: _address.text.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: '清空',
                                          icon:
                                              const Icon(Icons.close, size: 17),
                                          onPressed: () {
                                            _address.clear();
                                            setState(() {});
                                          },
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (hasWebPage) ...[
                              _chromeButton(
                                  tooltip: '刷新',
                                  icon: Icons.refresh,
                                  onPressed: _reload),
                              const SizedBox(width: 6),
                              _chromeButton(
                                  tooltip: '收藏网页',
                                  icon: Icons.star_border,
                                  onPressed: _saveBookmark),
                              const SizedBox(width: 6),
                            ],
                            _tabCountButton(),
                            const SizedBox(width: 6),
                            _chromeButton(
                                tooltip: '页面菜单',
                                icon: Icons.more_horiz,
                                onPressed: _showBrowserMenu),
                          ],
                        ),
                      ),
                    ),
                  if (desktop && _showingAddressEditor)
                    _buildAddressSuggestions(),
                  if (!desktop) _buildMobileTabStrip(tokens),
                  if (!desktop) _buildMobileOmnibox(tab),
                  if (!desktop && _showingAddressEditor)
                    _buildAddressSuggestions(),
                  if (tab.loading) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: RepaintBoundary(
                      key: _captureKey,
                      child: IndexedStack(
                        index: _active,
                        children: [
                          for (final item in _tabs)
                            KeyedSubtree(
                              key: ValueKey(item),
                              child: RepaintBoundary(
                                key: item.previewKey,
                                child: _tabContent(item),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!desktop)
                    SizedBox(
                      height: 72 + bottomInset,
                      child: ColoredBox(
                        color: tokens.toolbarBackground,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: bottomInset),
                          child: _buildMobileBottomToolbar(tab, tokens),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ],
          ),
          // 标签页概览作为覆盖层，内容树保持挂载以便随时补拍快照
          if (_showingTabs) _buildTabOverview(),
        ],
        ),
      ),
    );
  }
}

/// 总览唤起动画：上滑 + 淡入 + 轻缩放（菜单/浮层唤起的通用手感）。
class _OverviewEntrance extends StatefulWidget {
  const _OverviewEntrance({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<_OverviewEntrance> createState() => _OverviewEntranceState();
}

class _OverviewEntranceState extends State<_OverviewEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320));
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    // 立即起播（测试环境不允许挂起 timer；错峰感用曲线近似即可）
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) {
        final t = _a.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - t)),
            child: Transform.scale(scale: .94 + .06 * t, child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _TabPreviewCard extends StatelessWidget {
  const _TabPreviewCard({
    required this.item,
    required this.selected,
    required this.location,
    required this.onTap,
    required this.onClose,
  });

  final _BrowserTab item;
  final bool selected;
  final String location;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.browserTokens;
    final borderColor = selected ? AppColors.brand : tokens.divider;
    final borderWidth = selected ? 2.4 : 1.0;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: tokens.toolbarBackground,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      item.previewBytes != null
                          ? Image.memory(
                              item.previewBytes!,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : (item.previewImageUrl != null
                              ? Image.network(
                                  item.previewImageUrl!,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (_, child, progress) =>
                                      progress == null
                                          ? child
                                          : ColoredBox(
                                              color: scheme
                                                  .surfaceContainerHighest
                                                  .withValues(alpha: .5)),
                                  errorBuilder: (_, __, ___) =>
                                      _TabPreviewPlaceholder(
                                          item: item, location: location),
                                )
                              : _TabPreviewPlaceholder(
                                  item: item, location: location)),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          tooltip: '关闭标签页',
                          onPressed: onClose,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(24, 24),
                            padding: EdgeInsets.zero,
                            backgroundColor:
                                Colors.black.withValues(alpha: .5),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.close, size: 14),
                        ),
                      ),
                      if (item.loading)
                        const Align(
                          alignment: Alignment.topCenter,
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 7, 7, 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: item.faviconUrl != null
                          ? Image.network(
                              item.faviconUrl!,
                              width: 22,
                              height: 22,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => BrowserBrandMark(
                                  letter: item.private ? 'P' : 'V',
                                  selected: selected),
                            )
                          : BrowserBrandMark(
                              letter: item.private ? 'P' : 'V',
                              selected: selected,
                            ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabPreviewPlaceholder extends StatelessWidget {
  const _TabPreviewPlaceholder({required this.item, required this.location});

  final _BrowserTab item;
  final String location;

  @override
  Widget build(BuildContext context) {
    final tokens = context.browserTokens;
    final privateColor = tokens.privateAccent;
    return ColoredBox(
      color: item.private ? privateColor.withValues(alpha: .10) : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 22,
            color: item.private
                ? privateColor.withValues(alpha: .16)
                : tokens.chromeBackground,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(
                  item.private ? Icons.visibility_off_outlined : Icons.lock,
                  size: 10,
                  color:
                      item.private ? privateColor : tokens.addressBarForeground,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8,
                      color: tokens.addressBarForeground.withValues(alpha: .68),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 10, 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: item.private
                          ? privateColor.withValues(alpha: .18)
                          : AppColors.brand.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      item.private
                          ? Icons.visibility_off_outlined
                          : Icons.public,
                      color:
                          item.private ? privateColor : AppColors.brandStrong,
                      size: 16,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  for (final width in [1.0, .72])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: FractionallySizedBox(
                        widthFactor: width,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: tokens.divider.withValues(alpha: .72),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewTabView extends StatelessWidget {
  const _NewTabView({required this.private, required this.onFocusAddress});

  final bool private;
  final VoidCallback onFocusAddress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.browserTokens;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 34, 28, 30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  tokens.toolbarBackground,
                  scheme.primary.withValues(alpha: .07)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: tokens.divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                      color: scheme.primaryContainer, shape: BoxShape.circle),
                  child: Icon(
                      private ? Icons.visibility_off_outlined : Icons.public,
                      size: 34,
                      color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 20),
                Text(private ? '无痕浏览' : '新标签页',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(private ? '关闭此标签页后，不保留本次浏览数据' : '使用上方地址栏开始浏览',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth < 180
                      ? const SizedBox.shrink()
                      : FilledButton.icon(
                          onPressed: onFocusAddress,
                          icon: const Icon(Icons.search),
                          label: const Text('开始浏览'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
