import 'dart:io';

import 'package:flutter/material.dart';

import '../../../theme/home_backgrounds.dart';

/// 首页背景画布：
/// - 默认预设 → 跟随主题纯色（原版外观）；
/// - 渐变预设 → 整页线性渐变；
/// - 自定义图片 → 铺满全屏 + 暗色遮罩（保证浅色图标/文字可读）。
/// 图片文件丢失时自愈回落默认纯色，不致红屏。
class HomeBackgroundCanvas extends StatelessWidget {
  const HomeBackgroundCanvas({
    super.key,
    required this.preset,
    required this.imagePath,
    required this.fallbackColor,
    required this.child,
  });

  final HomeBackgroundPreset preset;

  /// 仅当 [HomeBackgroundPreset.usesCustomImage] 时生效。
  final String? imagePath;

  /// 默认外观的主题底色（原 chromeBackground）。
  final Color fallbackColor;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (preset.usesCustomImage &&
        imagePath != null &&
        imagePath!.isNotEmpty &&
        File(imagePath!).existsSync()) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(imagePath!), fit: BoxFit.cover),
          const ColoredBox(color: Color(0x33000000)),
          child,
        ],
      );
    }
    final gradient = preset.gradient;
    if (gradient != null) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: child,
      );
    }
    return ColoredBox(color: fallbackColor, child: child);
  }
}
