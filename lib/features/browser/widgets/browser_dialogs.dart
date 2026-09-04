import 'package:flutter/material.dart';

import '../../../core/widgets/ui_kit.dart';

/// Ephemeral dialogs owned by the browser feature.
///
/// IMPORTANT: never `dispose()` the [TextEditingController] created for these
/// dialogs. The dialog's future resolves as soon as the route starts popping,
/// but the dialog widgets keep animating (fade-out + keyboard insets change)
/// for a few frames. Disposing the controller there makes the still-mounted
/// [TextField] rebuild against a disposed notifier —
/// "A TextEditingController was used after being disposed", followed by the
/// framework's `_dependents.isEmpty` assertion and a red error screen.
/// The controller has no native resources; GC reclaims it after unmount.

/// 在页面中查找对话框。
///
/// 返回值：
/// - `null`  → 用户点了「取消」或点击遮罩关闭
/// - `''`    → 用户点了「清除高亮」
/// - 非空    → 要查找的文字（已 trim）
Future<String?> showFindInPageDialog(BuildContext context) {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('在页面中查找'),
      content: KeyboardFocusKickoff(
        focusNode: focusNode,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: '输入文字'),
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, ''),
          child: const Text('清除高亮'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('查找'),
        ),
      ],
    ),
  );
}

/// 收藏网页的命名对话框，返回用户输入的名称（未 trim 交由调用方处理）。
Future<String?> showBookmarkNameDialog(
  BuildContext context, {
  required String initialName,
}) {
  final controller = TextEditingController(text: initialName);
  final focusNode = FocusNode();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('收藏网页'),
      content: KeyboardFocusKickoff(
        focusNode: focusNode,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    ),
  );
}
