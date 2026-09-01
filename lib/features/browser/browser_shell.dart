import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Responsive browser chrome shared by desktop and mobile layouts.
class BrowserShell extends StatelessWidget {
  const BrowserShell({
    super.key,
    required this.desktopTabBar,
    required this.addressBar,
    required this.content,
    required this.mobileToolbar,
    required this.tabOverview,
    required this.showTabOverview,
    this.desktopBreakpoint = 840,
  });

  final Widget desktopTabBar;
  final Widget addressBar;
  final Widget content;
  final Widget mobileToolbar;
  final Widget tabOverview;
  final bool showTabOverview;
  final double desktopBreakpoint;

  @override
  Widget build(BuildContext context) {
    final tokens = context.browserTokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= desktopBreakpoint;
        if (showTabOverview) return tabOverview;

        return ColoredBox(
          color: tokens.chromeBackground,
          child: Column(
            children: [
              if (desktop) desktopTabBar,
              addressBar,
              Expanded(child: content),
              if (!desktop) mobileToolbar,
            ],
          ),
        );
      },
    );
  }
}
