import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logic/board_model.dart';
import '../../theme/app_theme.dart';
import '../../theme/home_backgrounds.dart';

/// 首页背景选择器（共享组件）：
/// Home 设置弹层与 设置页·外观 子页共用。
/// 内部监听 BoardModel —— 点选后 `model.save()` 触发重建，父级无需 setState。
///
/// 设计语言：壁纸缩略图（圆角方块 + 渐变实拍预览），
/// 选中态 = 品牌环 + 白隙 + 勾选徽章 + 微缩放；不带节标题，由宿主提供。
class HomeBackgroundPicker extends StatelessWidget {
  const HomeBackgroundPicker({super.key, required this.model});

  final BoardModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final imagePresetIndex =
            homeBackgroundPresets.indexWhere((p) => p.usesCustomImage);
        final customActive = model.settings.homeBackground == imagePresetIndex &&
            (model.settings.homeBackgroundPath?.isNotEmpty ?? false);

        void select(int index) {
          model.settings.homeBackground = index;
          model.save();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 14,
              children: [
                for (var i = 0; i < homeBackgroundPresets.length; i++)
                  if (!homeBackgroundPresets[i].usesCustomImage)
                    _WallpaperThumb(
                      key: ValueKey('home_bg_preset_$i'),
                      preset: homeBackgroundPresets[i],
                      name: homeBackgroundPresets[i].name,
                      selected: model.settings.homeBackground == i,
                      onTap: () => select(i),
                    ),
              ],
            ),
            const SizedBox(height: 18),
            _CustomImageRow(
              active: customActive,
              imagePath: customActive ? model.settings.homeBackgroundPath : null,
              onPick: () async {
                final path = await _pickHomeBackgroundImage();
                if (path == null) return;
                model.settings.homeBackground = imagePresetIndex;
                model.settings.homeBackgroundPath = path;
                await model.save();
              },
              onClear: () => select(0),
            ),
          ],
        );
      },
    );
  }
}

/// 壁纸缩略图：圆角方块渐变预览 + 选中环/勾选徽章/微缩放。
class _WallpaperThumb extends StatelessWidget {
  const _WallpaperThumb({
    super.key,
    required this.preset,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  static const _size = 64.0;

  final HomeBackgroundPreset preset;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 外层框恒定尺寸：选中不改变占位，同行标签基线对齐；
            // 选中语义由环 + 内容缩放表达。
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: _size + 10,
              height: _size + 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected ? AppColors.brand : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: AnimatedScale(
                  scale: selected ? 1.0 : 0.90,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: preset.gradient ??
                          const LinearGradient(colors: [
                            Color(0xFFF7F9FC),
                            Color(0xFFEDF1F7)
                          ]),
                      border: preset.gradient == null
                          ? Border.all(color: tokens.outline)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: selected
                              ? AppColors.brand.withValues(alpha: .28)
                              : const Color(0x140E1420),
                          blurRadius: selected ? 10 : 5,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 壁纸隐喻：底部"地平线"柔光渐隐（深色壁纸下减弱）。
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.white.withValues(
                                      alpha: preset.lightNavigationBarIcons
                                          ? .12
                                          : .32),
                                ],
                                stops: const [0.5, 1.0],
                              ),
                            ),
                          ),
                        ),
                        if (selected)
                          const Positioned(
                            right: 4,
                            top: 4,
                            child: _CheckBadge(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
              const SizedBox(height: 7),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: selected ? AppColors.brand : AppColors.subText,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                child: Text(name),
              ),
          ],
        ),
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.brand,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: const Icon(Icons.check, size: 11, color: Colors.white),
    );
  }
}

/// 自定义图片行：与「深色模式」tile 同语言——左侧 squircle 缩略
/// （选图后显示当前壁纸缩略图），标题 + 副标题，右侧操作。
class _CustomImageRow extends StatelessWidget {
  const _CustomImageRow({
    required this.active,
    required this.imagePath,
    required this.onPick,
    required this.onClear,
  });

  final bool active;
  final String? imagePath;
  final Future<void> Function() onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final leading = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.brand.withValues(alpha: .10),
      ),
      child: active && imagePath != null && File(imagePath!).existsSync()
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(imagePath!),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            )
          : const Icon(Icons.wallpaper_outlined,
              size: 22, color: AppColors.brand),
    );

    return Row(
      children: [
        leading,
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('自定义图片',
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
              SizedBox(height: 3),
              Text('用相册图片，自动加暗遮罩',
                  style: TextStyle(fontSize: 12, color: AppColors.subText)),
            ],
          ),
        ),
        if (active)
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('清除',
                style: TextStyle(color: AppColors.subText)),
          ),
        TextButton(
          onPressed: () => onPick(),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(active ? '换一张 ›' : '选择图片 ›',
              style: const TextStyle(
                  color: AppColors.brand, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// 选图后拷进应用文档目录（file_picker 的临时路径可能被系统回收），
/// 固定前缀命名并清理旧副本，避免缓存堆积。
Future<String?> _pickHomeBackgroundImage() async {
  final result = await FilePicker.platform.pickFiles(type: FileType.image);
  final picked = result?.files.single;
  final pickedPath = picked?.path;
  if (pickedPath == null) return null;
  final docs = await getApplicationDocumentsDirectory();
  const prefix = 'home_background_custom';
  for (final entity in docs.listSync()) {
    if (entity is File &&
        entity.uri.pathSegments.last.startsWith(prefix) &&
        entity.path != pickedPath) {
      try {
        await entity.delete();
      } catch (_) {}
    }
  }
  final ext = (picked?.extension?.isNotEmpty ?? false)
      ? '.${picked!.extension}'
      : '.jpg';
  final target = File('${docs.path}/$prefix$ext');
  await File(pickedPath).copy(target.path);
  return target.path;
}
