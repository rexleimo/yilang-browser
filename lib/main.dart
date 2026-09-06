import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/core.dart';
import 'features/bookmark_desktop/bookmark_desktop.dart';
import 'features/browser/browser.dart';
import 'features/downloads/downloads.dart';
import 'features/settings/settings.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebase();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.black,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final store = await SqliteBookmarkStore.create();
  FaviconService.init(FaviconService(store));
  final model = BoardModel(store: store);
  await model.load();
  final downloadStore = await SharedPrefsDownloadTaskStore.create();
  final downloads = DownloadController(store: downloadStore);
  runApp(YilanApp(model: model, downloads: downloads));
}

/// 初始化 Firebase（Analytics / 内测分发数据）。
///
/// 配置缺失时（例如 fork 仓库没有 google-services.json /
/// GoogleService-Info.plist）降级为无 Firebase 运行，不影响 App 其他功能。
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }
}

/// 一览 · Yilan —— 书签浏览器
class YilanApp extends StatelessWidget {
  const YilanApp({super.key, required this.model, this.downloads});

  final BoardModel model;
  final DownloadController? downloads;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => MaterialApp(
        title: '一览 Yilan',
        debugShowCheckedModeBanner: false,
        theme: buildAppLightTheme(),
        darkTheme: buildAppDarkTheme(),
        themeMode: model.settings.darkMode ? ThemeMode.dark : ThemeMode.light,
        home: HomeShell(model: model, downloads: downloads),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.model, this.downloads});

  final BoardModel model;
  final DownloadController? downloads;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

/// Verification hook: builds with --dart-define=YILAN_DEMO_URL=<url> start
/// directly in the browsing state. Normal builds are unaffected.
const String _demoUrl = String.fromEnvironment('YILAN_DEMO_URL');

class _HomeShellState extends State<HomeShell> {
  int _tab = _demoUrl.isEmpty ? 0 : 1;
  final int _browserRequest = 0;
  int _settingsReturnTab = 0;
  List<BrowserTabSummary> _tabSummaries = const [];
  final String? _pendingUrl = _demoUrl.isEmpty ? null : _demoUrl;
  final GlobalKey<BrowserPageState> _browserKey = GlobalKey<BrowserPageState>();

  /// BrowserPage 在 IndexedStack 里随首帧一起构建，state 通常已就绪——
  /// 同步交接 URL，保证切到浏览器的那一帧就已经带着地址，
  /// 不会先闪一帧"新标签页"引导卡。state 未就绪时退回 postFrame。
  void _withBrowser(void Function(BrowserPageState browser) fn) {
    final browser = _browserKey.currentState;
    if (browser != null) {
      fn(browser);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final browser = _browserKey.currentState;
        if (browser != null) fn(browser);
      });
    }
  }

  void _openBrowserTab(int index) {
    widget.model.exitEdit();
    setState(() => _tab = 1);
    _withBrowser((browser) => browser.selectExternalTab(index));
  }

  void _openUrlInBrowser(String raw) {
    widget.model.exitEdit();
    setState(() {
      _tab = 1;
    });
    _withBrowser((browser) => browser.openAddress(raw));
  }

  /// Home tiles open a fresh tab instead of clobbering the live page; the
  /// address bar still edits the current tab.
  void _openUrlInNewTab(String raw) {
    widget.model.exitEdit();
    setState(() => _tab = 1);
    _withBrowser((browser) =>
        browser.openInNewTab(raw, private: widget.model.settings.incognito));
  }

  void _openNewBrowserTab() {
    widget.model.exitEdit();
    setState(() => _tab = 1);
    _withBrowser((browser) =>
        browser.openNewTab(private: widget.model.settings.incognito));
  }

  /// Home's tab button must enter the live tab overview, never create a tab.
  void _showBrowserTabs() {
    widget.model.exitEdit();
    setState(() => _tab = 1);
    _withBrowser((browser) => browser.showTabs(fromHome: true));
  }

  void _showReadingList() {
    widget.model.exitEdit();
    setState(() => _tab = 1);
    _withBrowser((browser) => browser.showReadingList(fromHome: true));
  }

  void _showHistory() {
    widget.model.exitEdit();
    setState(() => _tab = 1);
    _withBrowser((browser) => browser.showHistory(fromHome: true));
  }

  void _showDownloads() {
    final downloads = widget.downloads;
    if (downloads == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DownloadCenterPage(controller: downloads),
    ));
  }

  void _openIncognitoTab() {
    widget.model.exitEdit();
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _browserKey.currentState?.openNewTab(private: true);
    });
  }

  void _goToBookmarks() {
    widget.model.exitEdit();
    if (mounted) setState(() => _tab = 0);
  }

  Future<void> _handleSystemBack() async {
    if (_tab == 1) {
      final handled = await _browserKey.currentState?.handleBack() ?? false;
      if (!handled) _goToBookmarks();
      return;
    }
    if (_tab == 2) {
      if (mounted) setState(() => _tab = _settingsReturnTab);
      return;
    }
    if (_tab != 0) _goToBookmarks();
  }

  void _openSettings(int returnTab) {
    widget.model.exitEdit();
    setState(() {
      _settingsReturnTab = returnTab;
      _tab = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      selectedTab: AppShellTab.values[_tab],
      onBack: _handleSystemBack,
      onTabSelected: (tab) {
        final index = tab.index;
        if (index == 0) widget.model.exitEdit();
        setState(() => _tab = index);
      },
      body: IndexedStack(
        index: _tab,
        children: [
          BookmarkDesktopPage(
            model: widget.model,
            active: _tab == 0,
            onOpenUrl: _openUrlInNewTab,
            onSubmitAddress: _openUrlInBrowser,
            onOpenSettings: () => _openSettings(0),
            onOpenBrowser: _openNewBrowserTab,
            onOpenTabs: _showBrowserTabs,
            onOpenReadingList: _showReadingList,
            onOpenHistory: _showHistory,
            onOpenDownloads: _showDownloads,
            onNewIncognitoTab: _openIncognitoTab,
            tabSummaries: _tabSummaries,
            onSelectBrowserTab: _openBrowserTab,
          ),
          BrowserPage(
            key: _browserKey,
            model: widget.model,
            initialUrl: _pendingUrl ?? '',
            openRequest: _browserRequest,
            onOpenSettings: () => _openSettings(1),
            onOpenBookmarks: _goToBookmarks,
            onTabsChanged: (summaries) {
              if (mounted) setState(() => _tabSummaries = summaries);
            },
            downloads: widget.downloads,
          ),
          SettingsPage(
            model: widget.model,
            downloads: widget.downloads,
            onBack: _handleSystemBack,
            onClearBrowsingData: (scopes) async {
              // IndexedStack 里 BrowserPage 随首帧构建，state 一般已就绪。
              final browser = _browserKey.currentState;
              if (browser == null) return const {};
              return browser.clearBrowsingData(scopes);
            },
          ),
        ],
      ),
    );
  }
}
