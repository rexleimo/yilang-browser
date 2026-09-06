import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单条拦截聚合记录：同一个「页面域 + 被拦域 + 类型」只占一条，[count] 累加。
class AdBlockEvent {
  AdBlockEvent({
    required this.pageHost,
    required this.host,
    required this.kind,
    required this.count,
    required this.lastAt,
  });

  factory AdBlockEvent.fromJson(Map<String, dynamic> j) => AdBlockEvent(
        pageHost: (j['p'] as String?) ?? '',
        host: (j['h'] as String?) ?? '',
        kind: (j['k'] as String?) ?? 'ad',
        count: (j['c'] as num?)?.toInt() ?? 0,
        lastAt: (j['t'] as num?)?.toInt() ?? 0,
      );

  /// 拦截发生在哪个页面（主框架域）。
  final String pageHost;

  /// 被拦的资源域；空字符串表示页面内的广告位元素（cosmetic 隐藏）。
  final String host;

  /// ad = 广告资源，track = 追踪器，pop = 弹窗 / 整页跳转。
  final String kind;

  int count;
  int lastAt; // epoch 毫秒，最近一次命中时间

  Map<String, dynamic> toJson() => {
        'p': pageHost,
        'h': host,
        'k': kind,
        'c': count,
        't': lastAt,
      };
}

/// 拦截日志存储（Brave Shields 式「到底拦了什么」的落地）。
///
/// - 明细按三元组聚合、newest-first，环形上限 [_maxEvents] 防膨胀；
/// - 累计值与按日计数独立持久化：明细被裁剪也不影响统计；
/// - 无痕标签页的写入由调用方跳过（与「无痕数据不落盘」一致）。
class AdBlockLogStore extends ChangeNotifier {
  static const _storageKey = 'yilan_ad_block_log_v1';
  static const _maxEvents = 500;
  static const _maxDays = 30;

  final List<AdBlockEvent> _events = <AdBlockEvent>[]; // newest first
  int _total = 0;
  final Map<String, int> _daily = <String, int>{}; // yyyy-MM-dd -> 次数
  bool _loaded = false;
  Timer? _saveDebounce;

  /// 最近拦截明细（聚合后，最新在前）。
  List<AdBlockEvent> get events => List.unmodifiable(_events);

  /// 累计拦截次数（含已因环形裁剪丢失明细的部分）。
  int get total => _total;

  /// 今日拦截次数。
  int get today => _daily[_dayKey(DateTime.now())] ?? 0;

  bool get loaded => _loaded;

  /// 某类拦截的累计次数（基于现存明细聚合）。
  int countByKind(String kind) => _events
      .where((e) => e.kind == kind)
      .fold(0, (sum, e) => sum + e.count);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        if (data is Map) {
          _total = (data['total'] as num?)?.toInt() ?? 0;
          final daily = data['daily'];
          if (daily is Map) {
            daily.forEach((key, value) {
              final count = value is num ? value.toInt() : 0;
              if (key is String && count > 0) _daily[key] = count;
            });
          }
          final events = data['events'];
          if (events is List) {
            for (final item in events) {
              if (item is Map) {
                _events.add(AdBlockEvent.fromJson(Map<String, dynamic>.from(
                    item.cast<String, dynamic>())));
              }
            }
          }
        }
      }
    } catch (_) {
      // 数据损坏时按空日志起步，不影响浏览。
    }
    _trimDays();
    notifyListeners();
  }

  /// 记录一次（或一批）拦截。无痕标签页请勿调用。
  void record({
    required String pageHost,
    required String host,
    required String kind,
    int count = 1,
  }) {
    if (count <= 0) return;
    final now = DateTime.now();
    _total += count;
    final day = _dayKey(now);
    _daily[day] = (_daily[day] ?? 0) + count;
    for (var i = 0; i < _events.length; i++) {
      final e = _events[i];
      if (e.pageHost == pageHost && e.host == host && e.kind == kind) {
        e.count += count;
        e.lastAt = now.millisecondsSinceEpoch;
        if (i != 0) {
          _events.removeAt(i);
          _events.insert(0, e);
        }
        _changed();
        return;
      }
    }
    _events.insert(
        0,
        AdBlockEvent(
          pageHost: pageHost,
          host: host,
          kind: kind,
          count: count,
          lastAt: now.millisecondsSinceEpoch,
        ));
    if (_events.length > _maxEvents) {
      _events.removeRange(_maxEvents, _events.length);
    }
    _changed();
  }

  /// 立即把当前状态写盘（防抖窗口内的增量也会落盘）。幂等。
  Future<void> flush() => _persist();

  /// 清空全部明细与统计（详情页的「清空记录」、隐私清理入口）。
  Future<void> clear() async {
    _events.clear();
    _total = 0;
    _daily.clear();
    notifyListeners();
    _saveDebounce?.cancel();
    await _persist();
  }

  void _changed() {
    notifyListeners();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode({
        'total': _total,
        'daily': _daily,
        'events': [for (final e in _events.take(_maxEvents)) e.toJson()],
      }));
    } catch (_) {
      // 落盘失败不影响内存态。
    }
  }

  void _trimDays() {
    if (_daily.length <= _maxDays) return;
    final keys = _daily.keys.toList()..sort();
    for (final key in keys.take(_daily.length - _maxDays)) {
      _daily.remove(key);
    }
  }

  static String _dayKey(DateTime time) {
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '${time.year}-$m-$d';
  }

  @override
  void dispose() {
    // 未落盘的增量直接补一次写（fire-and-forget，dispose 里不能 await）。
    _saveDebounce?.cancel();
    unawaited(_persist());
    super.dispose();
  }
}
