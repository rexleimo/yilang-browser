import 'package:flutter/material.dart';

/// 编辑模式底部操作栏
class EditBar extends StatelessWidget {
  const EditBar({
    super.key,
    required this.selectionCount,
    required this.onMove,
    required this.onNewFolder,
    required this.onDone,
  });

  final int selectionCount;
  final VoidCallback onMove;
  final VoidCallback onNewFolder;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final hasSel = selectionCount > 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE0281E28),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x59000000), blurRadius: 26, offset: Offset(0, 8))
        ],
      ),
      child: Row(
        children: [
          Text(
            hasSel ? '已选 $selectionCount 项' : '编辑模式',
            style: const TextStyle(fontSize: 13, color: Color(0xFFC3C9D8)),
          ),
          const SizedBox(width: 10),
          _Btn(label: '移动到', primary: true, onTap: hasSel ? onMove : null),
          const SizedBox(width: 8),
          _Btn(label: '新建文件夹', onTap: hasSel ? onNewFolder : null),
          const Spacer(),
          _Btn(label: '完成', onTap: onDone, filled: true),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn(
      {required this.label,
      this.onTap,
      this.primary = false,
      this.filled = false});

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: filled
              ? Colors.white.withValues(alpha: 0.22)
              : (primary
                  ? const Color(0xFFF89000)
                  : Colors.white.withValues(alpha: 0.14)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: enabled ? Colors.white : Colors.white38,
            fontWeight: filled ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
