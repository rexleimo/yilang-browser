import 'package:flutter/material.dart';

/// 首页背景预设：索引持久化在 `Settings.homeBackground`，
/// 自定义图片路径持久化在 `Settings.homeBackgroundPath`。
///
/// 预设顺序即 UI 展示顺序；索引 0 恒为「跟随主题」的默认外观
/// （不画渐变、不换图），保证老数据与越界索引都能安全回落。
class HomeBackgroundPreset {
  const HomeBackgroundPreset(
    this.name, {
    required this.gradient,
    required this.navigationBarColor,
    this.lightNavigationBarIcons = false,
    this.usesCustomImage = false,
  });

  /// 选择器里展示的名字。
  final String name;

  /// 背景渐变；null 表示跟随主题（默认浅灰，不画背景装饰）。
  final Gradient? gradient;

  /// Android 底部系统导航条配色（跟随背景深浅）。
  final Color navigationBarColor;

  /// 导航条图标是否用浅色（深色背景时为 true）。
  final bool lightNavigationBarIcons;

  /// true = 使用 `Settings.homeBackgroundPath` 指向的用户图片。
  final bool usesCustomImage;
}

const List<HomeBackgroundPreset> homeBackgroundPresets = [
  HomeBackgroundPreset(
    '默认',
    gradient: null,
    navigationBarColor: Color(0xFFF5F7FB),
  ),
  HomeBackgroundPreset(
    '靛蓝晨曦',
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFE9ECFB), Color(0xFFC7CFF4), Color(0xFF98A6E9)],
      stops: [0.0, 0.55, 1.0],
    ),
    navigationBarColor: Color(0xFF98A6E9),
  ),
  HomeBackgroundPreset(
    '暖橙日落',
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFF0DB), Color(0xFFFFD9A8), Color(0xFFF5B26B)],
      stops: [0.0, 0.55, 1.0],
    ),
    navigationBarColor: Color(0xFFF5B26B),
  ),
  HomeBackgroundPreset(
    '青竹',
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFE1F5EB), Color(0xFFBCE6D0), Color(0xFF8FD0AE)],
      stops: [0.0, 0.55, 1.0],
    ),
    navigationBarColor: Color(0xFF8FD0AE),
  ),
  HomeBackgroundPreset(
    '樱花粉',
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFCE7EF), Color(0xFFF9CEDD), Color(0xFFF2A7C2)],
      stops: [0.0, 0.55, 1.0],
    ),
    navigationBarColor: Color(0xFFF2A7C2),
  ),
  HomeBackgroundPreset(
    '星空夜',
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF1B2440), Color(0xFF131A2E), Color(0xFF0E1420)],
      stops: [0.0, 0.55, 1.0],
    ),
    navigationBarColor: Color(0xFF0E1420),
    lightNavigationBarIcons: true,
  ),
  HomeBackgroundPreset(
    '自定义图片',
    gradient: null,
    navigationBarColor: Color(0xFF10151F),
    lightNavigationBarIcons: true,
    usesCustomImage: true,
  ),
];

/// 越界索引回落到默认预设（索引 0），保证持久层脏数据不致红屏。
HomeBackgroundPreset resolveHomeBackground(int index) {
  if (index < 0 || index >= homeBackgroundPresets.length) {
    return homeBackgroundPresets[0];
  }
  return homeBackgroundPresets[index];
}
