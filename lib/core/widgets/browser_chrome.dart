import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

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
        borderRadius: BorderRadius.circular(5),
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
    this.onTap,
    this.onClose,
    this.width = 104,
  });

  final String label;
  final bool selected;
  final bool private;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final double width;

  @override
  Widget build(BuildContext context) {
    final tokens = context.browserTokens;
    final foreground = selected ? tokens.addressBarForeground : Colors.white;
    return Material(
      color: selected ? tokens.toolbarBackground : AppColors.brand,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: 34,
          child: Row(
            children: [
              const SizedBox(width: 8),
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

/// Bottom-toolbar button: a 48px rounded chip with an optional tab-count
/// badge. Selected, pressed and disabled states all come from the theme so
/// every surface reads the same.
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
    final button = IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        backgroundColor: selected
            ? AppColors.brand.withValues(alpha: .16)
            : scheme.surfaceContainerHighest.withValues(alpha: .62),
        // A selected-but-disabled button (e.g. "Home" while already on the
        // home page) must keep its selected look; only unselected buttons
        // fade when disabled.
        disabledBackgroundColor: selected
            ? AppColors.brand.withValues(alpha: .16)
            : scheme.surfaceContainerHighest.withValues(alpha: .28),
        disabledForegroundColor: selected
            ? AppColors.brandStrong
            : scheme.onSurface.withValues(alpha: .28),
        foregroundColor:
            selected ? AppColors.brandStrong : scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    if (badge == null) return button;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            right: 1,
            top: 1,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
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
                hintText: hintText,
                border: InputBorder.none,
                hintStyle: TextStyle(
                    color: tokens.addressBarForeground.withValues(alpha: .45)),
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
    this.private = false,
    this.onReload,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final String displayText;
  final bool editing;
  final VoidCallback onActivate;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClose;
  final bool private;
  final VoidCallback? onReload;

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
                Icon(
                  private
                      ? Icons.visibility_off_outlined
                      : hasLocation
                          ? Icons.lock_outline
                          : Icons.search,
                  color: foreground.withValues(alpha: .72),
                  size: 18,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: editing
                      ? TextField(
                          key: const ValueKey('browser-omnibox-input'),
                          controller: controller,
                          focusNode: focusNode,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.go,
                          textCapitalization: TextCapitalization.none,
                          autocorrect: false,
                          enableSuggestions: false,
                          onSubmitted: onSubmit,
                          style: TextStyle(
                            fontSize: 14,
                            color: foreground,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: hintText,
                            hintStyle: TextStyle(
                              color: foreground.withValues(alpha: .48),
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

/// Consistent bottom menu sheet: a drag handle above a list of [menuTile]s.
Future<void> showBrowserMenuSheet(
  BuildContext context, {
  required List<Widget> tiles,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .62,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final scrollController = ScrollController();
      return SafeArea(
        child: Material(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('面板',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      tooltip: '关闭面板',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Scrollbar(
                  controller: scrollController,
                  thumbVisibility: true,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: tiles,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// One line inside a menu sheet.
Widget menuTile(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? subtitle,
  required VoidCallback onTap,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Tooltip(
    message: title,
    child: ListTile(
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    ),
  );
}
