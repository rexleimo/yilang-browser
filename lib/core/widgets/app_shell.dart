import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The application-level destinations shared by every primary page.
enum AppShellTab { bookmarks, browser, settings }

/// Shared application boundary for the primary destinations.
///
/// The browser pages own their complete mobile chrome, including the 72px
/// browser toolbar. Keeping a second app-level NavigationBar here would stack
/// two unrelated navigation systems at the bottom of the phone viewport.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.body,
    required this.selectedTab,
    required this.onTabSelected,
    this.onBack,
    this.top,
  });

  static const double bottomBarHeight = 72;

  final Widget body;
  final AppShellTab selectedTab;
  // Kept in the API for callers that coordinate shell state.
  final ValueChanged<AppShellTab> onTabSelected;
  final Future<void> Function()? onBack;
  final PreferredSizeWidget? top;

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: top,
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      extendBody: false,
      body: _AppShellBackground(child: body),
    );

    final topInset = MediaQuery.viewPaddingOf(context).top;
    final withSystemBarSurface = Stack(
      fit: StackFit.expand,
      children: [
        scaffold,
        if (topInset > 0)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: topInset,
            child: const ColoredBox(color: Colors.black),
          ),
      ],
    );

    if (onBack == null) return withSystemBarSurface;
    return PopScope(
      canPop: selectedTab == AppShellTab.bookmarks,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack!();
      },
      child: withSystemBarSurface,
    );
  }
}

class _AppShellBackground extends StatelessWidget {
  const _AppShellBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.browserTokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tokens.chromeBackground,
            Color.lerp(tokens.chromeBackground, tokens.toolbarBackground, .5)!,
          ],
        ),
      ),
      child: child,
    );
  }
}
