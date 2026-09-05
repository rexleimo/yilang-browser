import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/search_engines.dart';
import '../../theme/app_theme.dart';
import 'ui_kit.dart';

/// Shared mobile browser chrome: the orange tab strip, toolbar buttons,
/// floating address editor and menu sheet. Home (bookmark desktop) and the
/// web browsing page must render these pieces identically so the shell feels
/// like one product, not two pages that happen to sit next to each other.

/// 20×20 rounded brand square carrying the tab letter (V = normal, P = private).
class BrowserBrandMark extends StatelessWidget {
  const BrowserBrandMark({
    super.key,
    required this.letter,
    required this.selected,
  });

  final String letter;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: selected ? AppColors.brand : AppColors.brandStrong,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One tab card inside the orange strip.
class BrowserTabChip extends StatelessWidget {
  const BrowserTabChip({
    super.key,
    required this.label,
    required this.selected,
    this.private = false,
    this.faviconUrl,
    this.onTap,
    this.onClose,
    this.width = 104,
  });

  final String label;
  final bool selected;
  final bool private;
  final String? faviconUrl;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final double width;

  @override
  Widget build(BuildContext context) {
    final tokens = context.browserTokens;
    final foreground = selected ? tokens.addressBarForeground : Colors.white;
    return Material(
        color: selected ? tokens.toolbarBackground : AppColors.brand,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: 34,
          child: Row(
            children: [
              const SizedBox(width: 8),
              if (faviconUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.network(
                    faviconUrl!,
                    width: 18,
                    height: 18,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => BrowserBrandMark(
                        letter: private ? 'P' : 'V', selected: selected),
                  ),
                )
              else
                BrowserBrandMark(letter: private ? 'P' : 'V', selected: selected),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onClose != null)
                IconButton(
                  tooltip: '关闭标签页',
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 24, height: 34),
                  icon: Icon(
                    Icons.close,
                    size: 13,
                    color: selected
                        ? tokens.addressBarForeground.withValues(alpha: .55)
                        : Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 48px orange strip: horizontally scrollable chips plus a new-tab action.
class BrowserTabStrip extends StatelessWidget {
  const BrowserTabStrip({
    super.key,
    required this.chips,
    required this.onNewTab,
    this.scrollable = false,
    this.newTabTooltip = '新建标签页',
  });

  final List<Widget> chips;
  final VoidCallback onNewTab;
  final bool scrollable;
  final String newTabTooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = context.browserTokens;
    return Container(
      height: 48,
      color: AppColors.brandStrong,
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
      child: Row(
        children: [
          if (scrollable)
            Expanded(
              child: ListView.separated(
                physics: const ClampingScrollPhysics(),
                scrollDirection: Axis.horizontal,
                itemCount: chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => chips[i],
              ),
            )
          else ...[
            ...chips,
            const Spacer(),
          ],
          IconButton(
            tooltip: newTabTooltip,
            onPressed: onNewTab,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 34),
            icon: Icon(Icons.add, color: tokens.addressBarForeground, size: 21),
          ),
        ],
      ),
    );
  }
}

/// Bottom-toolbar button: a plain icon (no chip background, Vivaldi-style).
/// When [badge] is set the glyph becomes a rounded-square outline holding the
/// tab count, like the reference browser's tab-count button.
class BrowserToolbarButton extends StatelessWidget {
  const BrowserToolbarButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.selected = false,
    this.badge,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    Color fg;
    if (selected) {
      fg = AppColors.brandStrong;
    } else if (!enabled) {
      fg = scheme.onSurface.withValues(alpha: .28);
    } else {
      fg = scheme.onSurfaceVariant;
    }
    final Widget glyph = badge != null
        ? Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: fg, width: 1.8),
            ),
            alignment: Alignment.center,
            child: Text(
              badge!,
              style: TextStyle(
                color: fg,
                fontSize: 12.5,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        : Icon(icon, size: 22);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: glyph,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        foregroundColor: fg,
        disabledForegroundColor: fg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// The 72px bottom browser toolbar frame (top hairline + soft upward shadow).
class BrowserToolbarFrame extends StatelessWidget {
  const BrowserToolbarFrame({
    super.key,
    required this.buttons,
    this.keyName = 'browser-toolbar-frame',
  });

  final List<Widget> buttons;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final tokens = context.browserTokens;
    return Container(
      key: ValueKey(keyName),
      height: 72,
      decoration: BoxDecoration(
        color: tokens.toolbarBackground,
        border: Border(top: BorderSide(color: tokens.divider)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x140E1420), blurRadius: 12, offset: Offset(0, -4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: buttons,
        ),
      ),
    );
  }
}

/// 搜索引擎品牌标（地址栏左侧显示当前引擎）。
/// 「此次搜索」来源菜单（Firefox 式）：锚在地址栏 Logo 下方的下拉，
/// 纵向引擎列表 + 书签/标签页/历史/搜索设置快捷入口。
/// [anchorKey] 指向地址栏左侧的引擎按钮；回调由调用方（浏览器/书签页）注入。
Future<void> showSearchSourceMenu(
  BuildContext context, {
  required GlobalKey anchorKey,
  required void Function(int engineIndex) onEngine,
  required VoidCallback onBookmarks,
  required VoidCallback onTabs,
  required VoidCallback onHistory,
  required VoidCallback onSettings,
}) {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final overlayBox =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  RelativeRect? position;
  if (box != null && overlayBox != null && box.attached && overlayBox.attached) {
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    position = RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + box.size.height + 6,
      (overlayBox.size.width - topLeft.dx - box.size.width).clamp(0, 9999),
      0,
    );
  }

  return showMenu<int>(
    context: context,
    position: position,
    color: Theme.of(context).colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    shadowColor: Colors.black26,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
    items: [
      PopupMenuItem<int>(
        enabled: false,
        height: 34,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
        child: Text('此次搜索：',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
      for (var i = 0; i < SearchEngines.names.length; i++)
        PopupMenuItem<int>(
          value: i,
          height: 48,
          child: Row(
            children: [
              EngineLogo(index: i, size: 24),
              const SizedBox(width: 14),
              Text(SearchEngines.name(i),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      const PopupMenuDivider(),
      _sourceItem(5, Icons.star_border, '书签'),
      _sourceItem(6, Icons.tab_outlined, '标签页'),
      _sourceItem(7, Icons.schedule, '历史'),
      const PopupMenuDivider(),
      _sourceItem(8, Icons.settings_outlined, '搜索设置'),
    ],
  ).then<void>((value) {
    if (value == null) return;
    if (value >= 0 && value <= 4) {
      onEngine(value);
      return;
    }
    switch (value) {
      case 5:
        onBookmarks();
      case 6:
        onTabs();
      case 7:
        onHistory();
      case 8:
        onSettings();
    }
  });
}

PopupMenuItem<int> _sourceItem(int value, IconData icon, String label) {
  return PopupMenuItem<int>(
    value: value,
    height: 48,
    child: Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 14),
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

/// 搜索引擎品牌标（地址栏左侧显示当前引擎）。
class EngineLogo extends StatelessWidget {
  const EngineLogo({super.key, required this.index, this.size = 18});

  final int index;
  final double size;

  static const _brands = [
    ('G', Color(0xFF4285F4)), // Google
    ('百', Color(0xFF2932E1)), // 百度
    ('b', Color(0xFF008373)), // 必应
    ('D', Color(0xFFDE5833)), // DuckDuckGo
    ('W', Color(0xFF202122)), // 维基百科
  ];

  @override
  Widget build(BuildContext context) {
    final (letter, color) =
        _brands[index.clamp(0, _brands.length - 1)];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * .3),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * .62,
          height: 1,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Floating one-line search/address editor shown above the toolbar.
class AddressEditorBar extends StatelessWidget {
  const AddressEditorBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onSubmit,
    required this.onClose,
    this.private = false,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClose;
  final bool private;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final tokens = context.browserTokens;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: tokens.toolbarBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tokens.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24141E3C),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Icon(
            private ? Icons.visibility_off_outlined : Icons.search,
            size: 19,
            color: tokens.addressBarForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: KeyboardFocusKickoff(
              focusNode: focusNode,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.go,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: onSubmit,
                style: TextStyle(
                  fontSize: 15,
                  color: tokens.addressBarForeground,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  hintText: hintText,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintStyle: TextStyle(
                      color: tokens.addressBarForeground.withValues(alpha: .45)),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '关闭搜索',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 19),
          ),
        ],
      ),
    );
  }
}

/// A compact address/search control that occupies one stable place in the
/// chrome. It renders either a readable location summary or the actual editor,
/// never both, so mobile pages do not grow a duplicate address UI.
class BrowserOmnibox extends StatelessWidget {
  const BrowserOmnibox({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.displayText,
    required this.editing,
    required this.onActivate,
    required this.onSubmit,
    required this.onClose,
    this.onChanged,
    this.onEngineTap,
    this.engineButtonKey,
    this.leadingSource,
    this.private = false,
    this.insecure = false,
    this.onReload,
    this.engineIndex = 0,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final String displayText;
  final bool editing;
  final VoidCallback onActivate;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String>? onChanged;

  /// 编辑态点左侧引擎 Logo → 弹出"此次搜索"来源菜单（Firefox 式）。
  final VoidCallback? onEngineTap;

  /// 引擎按钮锚点（下拉菜单贴着它定位）。
  final GlobalKey? engineButtonKey;

  /// 覆盖左侧 Logo 的自定义源（书签★ / 历史⏱ 等模式）。
  final Widget? leadingSource;
  final VoidCallback onClose;
  final bool private;

  /// 明文 http 页面：不亮锁图标（锁只属于 https），改用地球标提示非安全。
  final bool insecure;
  final VoidCallback? onReload;

  /// 当前搜索引擎序号（用于左侧品牌 logo）。
  final int engineIndex;

  @override
  Widget build(BuildContext context) {
    final tokens = context.browserTokens;
    final hasLocation = displayText.trim().isNotEmpty;
    final foreground = tokens.addressBarForeground;
    return Container(
      color: tokens.toolbarBackground,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Material(
        color: tokens.addressBarBackground,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: editing ? null : onActivate,
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 12),
                if (editing && onEngineTap != null)
                  // Firefox 式：源 Logo + 下拉箭头 → "此次搜索"菜单
                  InkWell(
                    key: engineButtonKey,
                    onTap: onEngineTap,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          leadingSource ?? EngineLogo(index: engineIndex, size: 18),
                          Icon(
                            Icons.keyboard_arrow_down,
                            size: 16,
                            color: foreground.withValues(alpha: .6),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (private || hasLocation)
                  Icon(
                    private
                        ? Icons.visibility_off_outlined
                        : (insecure ? Icons.language : Icons.lock_outline),
                    color: foreground.withValues(alpha: .72),
                    size: 18,
                  )
                else
                  leadingSource ?? EngineLogo(index: engineIndex, size: 18),
                const SizedBox(width: 9),
                Expanded(
                  child: editing
                      ? KeyboardFocusKickoff(
                          focusNode: focusNode,
                          child: TextField(
                            key: const ValueKey('browser-omnibox-input'),
                            controller: controller,
                            focusNode: focusNode,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.go,
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            enableSuggestions: false,
                            onSubmitted: onSubmit,
                            onChanged: onChanged,
                            style: TextStyle(
                              fontSize: 14,
                              color: foreground,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: false,
                              border: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              hintText: hintText,
                              hintStyle: TextStyle(
                                color: foreground.withValues(alpha: .48),
                              ),
                            ),
                          ),
                        )
                      : Text(
                          hasLocation ? displayText : hintText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hasLocation
                                ? foreground
                                : foreground.withValues(alpha: .52),
                            fontSize: 14,
                            fontWeight:
                                hasLocation ? FontWeight.w500 : FontWeight.w400,
                          ),
                        ),
                ),
                if (editing)
                  IconButton(
                    tooltip: '关闭搜索',
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 18),
                  )
                else if (onReload != null && hasLocation)
                  IconButton(
                    tooltip: '刷新',
                    onPressed: onReload,
                    icon: const Icon(Icons.refresh, size: 18),
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 面板菜单里的一个分类（UC / iOS 设置式：先分类，点进去再看具体条目）。
class BrowserMenuCategory {
  const BrowserMenuCategory({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
}

/// Consistent bottom menu sheet: a Brave-style icon grid — all actions
/// flattened into 4-column cells (icon + label). Height adapts to content,
/// capped at 2 rows; extra entries flow into horizontal swipe pages with a
/// dot indicator (iOS-style). Tapping an entry either performs the action
/// or pushes a full settings page.
Future<void> showBrowserMenuSheet(
  BuildContext context, {
  required List<BrowserMenuCategory> categories,
  String title = '面板',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .8,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _BrowserMenuSheet(categories: categories, title: title),
  );
}

class _BrowserMenuSheet extends StatefulWidget {
  const _BrowserMenuSheet({required this.categories, required this.title});

  final List<BrowserMenuCategory> categories;
  final String title;

  @override
  State<_BrowserMenuSheet> createState() => _BrowserMenuSheetState();
}

class _BrowserMenuSheetState extends State<_BrowserMenuSheet> {
  static const int _cols = 4;
  static const int _maxRows = 2;
  static const int _perPage = _cols * _maxRows;

  final PageController _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = [for (final c in widget.categories) ...c.actions];
    final pages = <List<Widget>>[
      for (var i = 0; i < actions.length; i += _perPage)
        actions.sublist(i, math.min(i + _perPage, actions.length)),
    ];
    // Height must fit the fullest page (earlier pages), not just the last one.
    final rows = math.min((actions.length / _cols).ceil(), _maxRows);

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 2),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: .35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                LayoutBuilder(builder: (ctx, cons) {
                  final cellW = (cons.maxWidth - 28) / _cols;
                  final rowH = cellW / .92;
                  return SizedBox(
                    height: rows * rowH,
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (i) => setState(() => _page = i),
                      children: [
                        for (final pageActions in pages)
                          GridView.count(
                            padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                            crossAxisCount: _cols,
                            childAspectRatio: .92,
                            physics: const NeverScrollableScrollPhysics(),
                            children: pageActions,
                          ),
                      ],
                    ),
                  );
                }),
                if (pages.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < pages.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _page ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? AppColors.brand
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: .3),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 8),
                // 收起（底部常驻退出按钮）
                SizedBox(
                  height: 34,
                  child: IconButton(
                    tooltip: '收起面板',
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.keyboard_arrow_down,
                        size: 26,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: .7)),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一个网格菜单项（Brave 风格：图标 + 标签，居中）。
Widget menuTile(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? subtitle,
  required VoidCallback onTap,
}) {
  final scheme = Theme.of(context).colorScheme;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: AppColors.ink),
          const SizedBox(height: 7),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface.withValues(alpha: .85),
            ),
          ),
        ],
      ),
    ),
  );
}
