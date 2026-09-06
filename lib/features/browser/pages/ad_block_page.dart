import 'package:flutter/material.dart';

import '../services/ad_block_log_store.dart';

/// 拦截详情页：Brave Shields 式的「到底拦了什么」。
///
/// 结构：发光盾牌 + 计数动画的 Hero 区 → 广告/追踪器/本页三张统计卡 →
/// 按站点聚合的拦截明细（类型徽章 + 命中次数 + 相对时间）。
class AdBlockPage extends StatefulWidget {
  const AdBlockPage({
    super.key,
    required this.store,
    this.currentPageHost = '',
    this.currentPageBlocked = 0,
  });

  final AdBlockLogStore store;
  final String currentPageHost;
  final int currentPageBlocked;

  @override
  State<AdBlockPage> createState() => _AdBlockPageState();
}

class _AdBlockPageState extends State<AdBlockPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _entrance = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('拦截防护'),
        actions: [
          if (widget.store.total > 0)
            IconButton(
              tooltip: '清空记录',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final events = widget.store.events;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _HeroCard(
                pulse: _pulse,
                entrance: _entrance,
                total: widget.store.total,
                today: widget.store.today,
              ),
              const SizedBox(height: 14),
              _StatRow(
                entrance: _entrance,
                pageHost: widget.currentPageHost,
                pageBlocked: widget.currentPageBlocked,
                adCount: widget.store.countByKind('ad'),
                trackCount: widget.store.countByKind('track'),
              ),
              const SizedBox(height: 22),
              if (events.isEmpty)
                _EmptyState(entrance: _entrance)
              else ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text('拦截明细',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800)),
                ),
                for (var i = 0; i < events.length; i++)
                  _EventTile(
                    event: events[i],
                    entrance: _entrance,
                    // 首屏前 10 条做瀑布式入场，长列表直接静态渲染。
                    stagger: i < 10 ? i / 12.0 : 0,
                  ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    '明细最多保留最近 500 条聚合记录，统计数字不受影响',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空拦截记录？'),
        content: const Text('将删除全部拦截明细与累计统计，此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) await widget.store.clear();
  }
}

/// 类型 → (标签, 图标, 主题色)。
class _KindMeta {
  const _KindMeta(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

const Map<String, _KindMeta> _kindMetas = {
  'ad': _KindMeta('广告', Icons.block_outlined, Color(0xFF4353C4)),
  'track': _KindMeta('追踪器', Icons.track_changes_outlined, Color(0xFF6A4CF5)),
  'pop': _KindMeta('弹窗', Icons.open_in_new_outlined, Color(0xFFD97A2B)),
};

_KindMeta _metaOf(String kind) => _kindMetas[kind] ?? _kindMetas['ad']!;

String _hostLabel(String host) => host.isEmpty ? '页面广告元素' : host;

String _relativeTime(int epochMs) {
  final delta = DateTime.now().millisecondsSinceEpoch - epochMs;
  if (epochMs <= 0 || delta < 0) return '刚刚';
  if (delta < 60 * 1000) return '刚刚';
  if (delta < 60 * 60 * 1000) return '${delta ~/ (60 * 1000)} 分钟前';
  if (delta < 24 * 60 * 60 * 1000) return '${delta ~/ (60 * 60 * 1000)} 小时前';
  final day = delta ~/ (24 * 60 * 60 * 1000);
  if (day == 1) return '昨天';
  if (day < 30) return '$day 天前';
  final date = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return '${date.year}-${date.month}-${date.day}';
}

/// Hero：渐变底 + 呼吸光环盾牌 + 数字滚动。
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.pulse,
    required this.entrance,
    required this.total,
    required this.today,
  });

  final Animation<double> pulse;
  final Animation<double> entrance;
  final int total;
  final int today;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return FadeTransition(
      opacity: CurvedAnimation(parent: entrance, curve: Curves.easeOut),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: dark
                ? const [Color(0xFF20284E), Color(0xFF161A38)]
                : const [Color(0xFF4353C4), Color(0xFF6A4CF5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: pulse,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(pulse.value);
                return CustomPaint(
                  painter: _ShieldGlowPainter(t),
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: const BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_outlined,
                        size: 46, color: Colors.white),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: total),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => Text(
                '$value',
                style: const TextStyle(
                  fontSize: 54,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontFeatures: [], // 数字tabular由字体默认
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('累计拦截',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '今日 +$today',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 盾牌呼吸光环：两圈随相位扩张并淡出的圆环。
class _ShieldGlowPainter extends CustomPainter {
  _ShieldGlowPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final phase = t;
    for (var ring = 0; ring < 2; ring++) {
      final p = (phase + ring * 0.5) % 1.0;
      final radius = size.width * (0.52 + p * 0.55);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * (1 - p)
        ..color = Colors.white.withValues(alpha: 0.5 * (1 - p));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ShieldGlowPainter oldDelegate) =>
      oldDelegate.t != t;
}

/// 三张统计卡：本页 / 广告 / 追踪器。
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.entrance,
    required this.pageHost,
    required this.pageBlocked,
    required this.adCount,
    required this.trackCount,
  });

  final Animation<double> entrance;
  final String pageHost;
  final int pageBlocked;
  final int adCount;
  final int trackCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cells = [
      (
        '本页${pageHost.isEmpty ? '' : ' · $pageHost'}',
        pageBlocked,
        const Color(0xFF0FA36B),
        Icons.public_outlined
      ),
      ('广告', adCount, _kindMetas['ad']!.color, Icons.block_outlined),
      ('追踪器', trackCount, _kindMetas['track']!.color,
          Icons.track_changes_outlined),
    ];
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: FadeTransition(
              opacity: CurvedAnimation(
                  parent: entrance,
                  curve: Interval(0.15 + i * 0.1, 0.7 + i * 0.1,
                      curve: Curves.easeOut)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Icon(cells[i].$4, size: 20, color: cells[i].$3),
                    const SizedBox(height: 8),
                    Text('${cells[i].$2}',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurface)),
                    const SizedBox(height: 2),
                    Text(cells[i].$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 单条聚合明细。
class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.entrance,
    required this.stagger,
  });

  final AdBlockEvent event;
  final Animation<double> entrance;
  final double stagger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = _metaOf(event.kind);
    return FadeTransition(
      opacity: CurvedAnimation(
          parent: entrance,
          curve: Interval(stagger, (stagger + 0.3).clamp(0.0, 1.0),
              curve: Curves.easeOut)),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(CurvedAnimation(
            parent: entrance,
            curve: Interval(stagger, (stagger + 0.3).clamp(0.0, 1.0),
                curve: Curves.easeOut))),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(meta.icon, size: 19, color: meta.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_hostLabel(event.host),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface)),
                    const SizedBox(height: 2),
                    Text(
                      event.pageHost.isEmpty
                          ? '${meta.label} · ${_relativeTime(event.lastAt)}'
                          : '${meta.label} · 来自 ${event.pageHost} · ${_relativeTime(event.lastAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '×${event.count}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: meta.color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.entrance});
  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: CurvedAnimation(parent: entrance, curve: const Interval(0.3, 1)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 56),
        alignment: Alignment.center,
        child: Column(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_user_outlined,
                  size: 36, color: Color(0xFF22C55E)),
            ),
            const SizedBox(height: 16),
            Text('还没有拦截记录',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(height: 6),
            Text('浏览时遇到广告与追踪器，会出现在这里',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
