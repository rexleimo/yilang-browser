import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ---------------------------------------------------------------------------
/// Yilan UI Kit —— 轻量可复用设计系统组件
///
/// 设计语言（严格对齐 homeapp 风格参考）：
/// - 靛蓝 (#4353C4) 主色：按钮、选中态、开关、图标底座
/// - 暖橙只做「输入焦点」点缀，绿色做选中打勾，绝不大面积铺色
/// - 小标签用中性深灰（不是品牌色），标题大而重、副文小而浅，层级分明
/// - 白色大圆角卡片 + 极轻投影；行高 52+，区块间距 26+
///
/// 复用方式：把本文件拷到其他项目，改 [UIKit] 静态色值即可整体换肤。
/// ---------------------------------------------------------------------------
abstract final class UIKit {
  /// 主色（参考图 indigo）。换项目时改这一处。
  static Color accent = const Color(0xFF4353C4);

  /// 主色的浅底（图标底座、选中卡片背景）。
  static Color accentSoft = const Color(0xFFEEF0FB);

  /// 输入类焦点的暖色点缀（参考图输入框描边色）。
  static Color warm = const Color(0xFFF0A43F);

  /// 选中打勾的绿色。
  static Color success = const Color(0xFF23BD7B);

  // 页面与卡片
  static const Color bg = Color(0xFFF2F3F7);
  static const Color card = Colors.white;
  static const Color ink = Color(0xFF1B1D28);
  static const Color sub = Color(0xFF9AA0AE);
  static const Color hairline = Color(0xFFECEEF4);

  // 圆角
  static const double rCard = 20;
  static const double rTile = 13;
  static const double rSheet = 28;
  static const double rButton = 26;

  static List<BoxShadow> get cardShadow => const [
        BoxShadow(
          color: Color(0x0D1B2A4A),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ];
}

/// 浅灰底 + 顶部大标题的页面骨架。
class UiScreen extends StatelessWidget {
  const UiScreen({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    required this.children,
    this.bottomInset = 28,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> children;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: UIKit.bg,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          children: [
            Row(
              children: [
                if (onBack != null)
                  _BackButton(onTap: onBack!)
                else
                  const SizedBox(width: 40),
                const SizedBox(width: 12),
                Text(title,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: UIKit.ink)),
              ],
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 6),
                child: Text(subtitle!,
                    style: const TextStyle(
                        fontSize: 13,
                        color: UIKit.sub,
                        height: 1.55)),
              ),
            const SizedBox(height: 26),
            ...children,
            SizedBox(height: bottomInset),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.arrow_back_ios_new, size: 18, color: UIKit.ink),
        ),
      ),
    );
  }
}

/// 分组小标签（如「浏览器」「关于」）——中性深灰，不抢主色的戏。
class UiSectionLabel extends StatelessWidget {
  const UiSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .3,
          color: Color(0xFF6E7480),
        ),
      ),
    );
  }
}

/// 白色大圆角卡片，自动在子项之间画内缩发丝线。
class UiCard extends StatelessWidget {
  const UiCard({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: UIKit.card,
        borderRadius: BorderRadius.circular(UIKit.rCard),
        boxShadow: UIKit.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    indent: 74,
                    endIndent: 16,
                    color: UIKit.hairline,
                  ),
              ],
            ],
          ),
        ),
    );
  }
}

/// 设置行：44px 图标底座 + 标题/副标题 + 尾部（自定义或 值+箭头）。
class UiTile extends StatelessWidget {
  const UiTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.value,
    this.showChevron = true,
    this.onTap,
    this.accentIcon = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// 完全自定义尾部（如开关）；给了就忽略 [value]/[showChevron]。
  final Widget? trailing;

  /// 尾部文字（如「百度」「v0.1.0」）。
  final String? value;
  final bool showChevron;
  final VoidCallback? onTap;

  /// false 时图标底座用灰色调（次要行）。
  final bool accentIcon;

  @override
  Widget build(BuildContext context) {
    final effectiveTrailing = trailing ??
        (value == null && !showChevron
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (value != null)
                  Text(value!,
                      style: const TextStyle(
                          fontSize: 13, color: UIKit.sub)),
                if (showChevron) ...[
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFFB9BEC9)),
                ],
              ]));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              _IconBadge(icon: icon, accent: accentIcon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: UIKit.ink,
                            height: 1.25)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              color: UIKit.sub,
                              height: 1.45)),
                    ],
                  ],
                ),
              ),
              if (effectiveTrailing != null) ...[
                const SizedBox(width: 10),
                effectiveTrailing,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 图标底座：44px 圆角方块。主色行用浅靛蓝底+靛蓝图标，次要行用中性灰。
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.accent});

  final IconData icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: accent ? UIKit.accentSoft : const Color(0xFFF3F4F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon,
          size: 19, color: accent ? UIKit.accent : const Color(0xFF7A8090)),
    );
  }
}

/// 自绘开关（不依赖 Material Switch 皮肤，风格跨项目一致）。
class UiSwitch extends StatelessWidget {
  const UiSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? UIKit.accent : const Color(0xFFE3E5EC),
          borderRadius: BorderRadius.circular(15),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Color(0x33000000), blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部圆角面板骨架：把手 + 标题 + 内容。
Future<T?> showUiSheet<T>({
  required BuildContext context,
  required String title,
  required List<Widget> children,
  bool scrollable = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(ctx).size.height * .72,
      ),
      decoration: const BoxDecoration(
        color: UIKit.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(UIKit.rSheet)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFE3E5EC),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(title,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: UIKit.ink)),
          ),
          const SizedBox(height: 14),
          if (scrollable)
            Flexible(
              child: SingleChildScrollView(
                child: Column(children: children),
              ),
            )
          else
            ...children,
        ],
      ),
    ),
  );
}

/// 选项卡片：图标底座 + 标题/副标题 + 右侧选中圆。
/// 选中的卡片带 accent 细边框 + 打勾实心圆（参考 homeapp「Reset via email ✓」）。
class UiOptionTile extends StatelessWidget {
  const UiOptionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? UIKit.accentSoft : const Color(0xFFF6F7FA),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? UIKit.accent.withValues(alpha: .45)
                    : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: Row(
              children: [
                _IconBadge(icon: icon, accent: selected),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: UIKit.ink)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: const TextStyle(
                                fontSize: 11, color: UIKit.sub)),
                      ],
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? UIKit.success : Colors.transparent,
                    border: Border.all(
                      color:
                          selected ? UIKit.success : const Color(0xFFD8DBE2),
                      width: 1.6,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check,
                          size: 15, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 主按钮：accent 填充胶囊，52px 高，全宽。
class UiButton extends StatelessWidget {
  const UiButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onPressed == null ? const Color(0xFFD6D9E0) : UIKit.accent,
      borderRadius: BorderRadius.circular(UIKit.rButton),
      child: InkWell(
        borderRadius: BorderRadius.circular(UIKit.rButton),
        onTap: onPressed,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(label,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 键盘引导：autofocus 在弹窗/过渡动画期间发出的 IME 请求会被系统丢弃
/// （窗口尚未可聚焦），表现为「输入框聚焦了但键盘不弹出」。
///
/// 本组件监听所在路由的过渡动画：过渡结束后再补一次 ——
/// - 焦点已在但键盘没出来 → 显式 `TextInput.show` 重发显示请求；
/// - 焦点还没拿到 → `requestFocus()`。
///
/// 不用 Timer 延时（避免测试 pending-timer 失败），直接挂路由动画状态。
/// 用法：包裹目标 TextField（或作为其兄弟节点），传入同一个 FocusNode。
class KeyboardFocusKickoff extends StatefulWidget {
  const KeyboardFocusKickoff({
    super.key,
    required this.focusNode,
    this.child,
  });

  final FocusNode focusNode;
  final Widget? child;

  @override
  State<KeyboardFocusKickoff> createState() => _KeyboardFocusKickoffState();
}

class _KeyboardFocusKickoffState extends State<KeyboardFocusKickoff> {
  Animation<double>? _animation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null) {
      // 非路由场景（如直接内嵌在页面里）：本帧结束后直接引导。
      _scheduleKick();
      return;
    }
    if (anim.status == AnimationStatus.completed) {
      _scheduleKick();
    } else if (_animation != anim) {
      _animation?.removeStatusListener(_onStatus);
      _animation = anim;
      anim.addStatusListener(_onStatus);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _animation?.removeStatusListener(_onStatus);
      _animation = null;
      _scheduleKick();
    }
  }

  void _scheduleKick() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.focusNode.hasFocus) {
        // 焦点已被 autofocus 拿到但 IME 请求被丢弃：显式重发。
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      } else {
        widget.focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}
