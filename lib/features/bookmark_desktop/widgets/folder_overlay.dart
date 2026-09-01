import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/bookmark.dart';
import '../../../theme/app_theme.dart';
import 'bookmark_tile.dart';

/// Folder contents shown as a bounded bottom surface.
class FolderOverlay extends StatelessWidget {
  const FolderOverlay({
    super.key,
    required this.folder,
    required this.onClose,
    required this.onOpenEntity,
  });

  final BookmarkFolder folder;
  final VoidCallback onClose;
  final void Function(BookmarkEntity) onOpenEntity;

  @override
  Widget build(BuildContext context) {
    final rows = math.max(1, (folder.children.length / 3).ceil());
    final preferredHeight = 116 + rows * 108.0;
    final panelHeight = math
        .min(
          MediaQuery.sizeOf(context).height * .62,
          math.max(244, preferredHeight),
        )
        .toDouble();

    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        child: ColoredBox(
          color: const Color(0x73202422),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: GestureDetector(
                onTap: () {},
                child: Semantics(
                  label: '${folder.name} 文件夹',
                  child: SizedBox(
                    key: const ValueKey('bookmark-folder-panel'),
                    width: 350,
                    height: panelHeight,
                    child: Material(
                      color: const Color(0xFFFAFAFC),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 12, 16),
                        child: Column(
                          children: [
                            Container(
                              width: 34,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.subText.withValues(alpha: .35),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: '返回书签',
                                  onPressed: onClose,
                                  icon: const Icon(Icons.arrow_back),
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      Text(
                                        folder.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${folder.children.length} 个书签',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.subText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: '关闭文件夹',
                                  onPressed: onClose,
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: GridView.count(
                                crossAxisCount: 3,
                                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 8,
                                childAspectRatio: 0.72,
                                children: [
                                  for (final child in folder.children)
                                    GestureDetector(
                                      onTap: () => onOpenEntity(child),
                                      child: BookmarkTile(
                                        entity: child,
                                        iconSize: 58,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
