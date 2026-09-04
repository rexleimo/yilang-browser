import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// 上下文菜单项。
class CtxMenuItem {
  const CtxMenuItem(this.icon, this.label, this.color, this.onTap);

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// iOS 式深色磨砂上下文菜单卡片。
class CtxMenuCard extends StatelessWidget {
  const CtxMenuCard({super.key, required this.items});

  final List<CtxMenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xE6242426),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: Colors.white.withValues(alpha: .08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Container(
                      height: 0.5,
                      margin: const EdgeInsets.symmetric(horizontal: 15),
                      color: Colors.white24,
                    ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: items[i].onTap,
                    child: SizedBox(
                      height: 44,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(items[i].icon, size: 18, color: items[i].color),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                items[i].label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: items[i].color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
