import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/logic/board_model.dart';
import 'core/storage/bookmark_store.dart';
import 'core/storage/download_task_store.dart';
import 'core/widgets/app_shell.dart';
import 'features/bookmark_desktop/bookmark_desktop_page.dart';
import 'features/browser/browser_page.dart';
import 'features/downloads/download_controller.dart';
import 'features/settings/settings_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.black,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final store = await SharedPrefsBookmarkStore.create();
  final model = BoardModel(store: store);
  await model.load();
  final downloadStore = await SharedPrefsDownloadTaskStore.create();
  final downloads = DownloadController(store: downloadStore);
  runApp(YilanApp(model: model, downloads: downloads));
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
  int _tabCount = 1;
  final String? _pendingUrl = _demoUrl.isEmpty ? null : _demoUrl;
  final GlobalKey<BrowserPageState> _browserKey = GlobalKey<BrowserPageState>();

  void _openUrlInBrowser(String raw) {
    widget.model.exitEdit();
    setState(() {
      _tab = 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _browserKey.currentState?.openAddress(raw);
    });
  }

  /// Home tiles open a fresh tab instead of clobbering the live page; the
  /// address bar still edits the current tab.
  void _openUrlInNewTab(String raw) {
    widget.model.exitEdit();
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _browserKey.currentState?.openInNewTab(raw,
          private: widget.model.settings.incognito);
    });
  }

  void _openNewBrowserTab() {
    widget.model.exitEdit();
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _browserKey.currentState?.openNewTab(
        private: widget.model.settings.incognito,
      );
    });
  }

  /// Home's tab button must enter the live tab overview, never create a tab.
  void _showBrowserTabs() {
    widget.model.exitEdit();
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _browserKey.currentState?.showTabs(fromHome: true);
    });
  }

  void _showReadingList() {
    widget.model.exitEdit();
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _browserKey.currentState?.showReadingList(fromHome: true);
    });
  }

  void _showHistory() {
    widget.model.exitEdit();
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _browserKey.currentState?.showHistory(fromHome: true);
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
            tabCount: _tabCount,
          ),
          BrowserPage(
            key: _browserKey,
            model: widget.model,
            initialUrl: _pendingUrl ?? '',
            openRequest: _browserRequest,
            onOpenSettings: () => _openSettings(1),
            onOpenBookmarks: _goToBookmarks,
            onTabCountChanged: (count) {
              if (mounted) setState(() => _tabCount = count);
            },
            downloads: widget.downloads,
          ),
          SettingsPage(model: widget.model, onBack: _handleSystemBack),
        ],
      ),
    );
  }
}
