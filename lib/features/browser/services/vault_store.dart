import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_data_store.dart';

/// 隐私空间（超级保密箱）存储。
///
/// 与无痕的分工：无痕什么都不留；隐私空间的浏览行为正常留痕，但记录
/// 用密码派生密钥加密后落盘，且只有输入密码解锁后才能查看。
///
/// 安全边界（如实说明）：
/// - 密码本身只存「随机盐 + SHA-256(盐 + 密码)」，不存明文；
/// - 记录用「SHA-256(盐 + 'vault-data' + 密码) 派生的密钥流」做异或后落盘——
///   裸读 SharedPreferences 看不到任何明文记录；这属于防"随手翻看"的
///   轻量加密，不是对抗取证级攻击的方案；
/// - 忘记密码 = 数据不可恢复（重置即清空整个隐私空间）。
class VaultStore extends ChangeNotifier {
  static const _passwordKey = 'yilan_vault_password_v1';
  static const _dataKey = 'yilan_vault_data_v1';
  static const _maxRecords = 500;

  /// 解锁状态与会话密钥只活在内存里：冷启动必须重新输密码。
  bool _unlocked = false;
  String? _sessionKey;
  bool _loaded = false;
  Timer? _saveDebounce;

  /// 解锁后缓存的明文记录（newest first）。
  final List<BrowserRecord> _records = <BrowserRecord>[];

  bool get loaded => _loaded;
  bool get unlocked => _unlocked;
  bool get hasPassword => _passwordBlob != null;
  List<BrowserRecord> get records => List.unmodifiable(_records);

  Map<String, Object?>? _passwordBlob;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_passwordKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        if (data is Map) _passwordBlob = Map<String, Object?>.from(data);
      }
    } catch (_) {
      // 数据损坏按未设置密码处理。
      _passwordBlob = null;
    }
    notifyListeners();
  }

  // ---------- 密码 ----------

  /// 首次设置密码（调用方需先确认 [hasPassword] == false）。设置完成即解锁。
  Future<void> setPassword(String password) async {
    assert(password.length >= 4);
    final salt = _randomSalt();
    _passwordBlob = {
      'salt': salt,
      'hash': _hash(salt, password),
    };
    _sessionKey = password;
    _unlocked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_passwordKey, jsonEncode(_passwordBlob));
    notifyListeners();
  }

  /// 校验密码；成功则解锁并解密记录。
  Future<bool> verify(String password) async {
    final blob = _passwordBlob;
    if (blob == null) return false;
    final salt = (blob['salt'] as String?) ?? '';
    if (_hash(salt, password) != ((blob['hash'] as String?) ?? '')) {
      return false;
    }
    _sessionKey = password;
    _unlocked = true;
    await _decryptRecords();
    notifyListeners();
    return true;
  }

  /// 上锁：内存里的明文记录与会话密钥立刻丢弃（磁盘上本来就是密文）。
  void lock() {
    _unlocked = false;
    _sessionKey = null;
    _records.clear();
    notifyListeners();
  }

  /// 忘记密码的唯一出路：连记录带密码一起清空（调用方负责二次确认）。
  Future<void> resetAll() async {
    _unlocked = false;
    _sessionKey = null;
    _records.clear();
    _passwordBlob = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_passwordKey);
    await prefs.remove(_dataKey);
    notifyListeners();
  }

  /// 只清空浏览记录，保留密码与解锁状态（详情页「清空浏览记录」入口）。
  Future<void> resetRecords() async {
    _records.clear();
    await persist();
    notifyListeners();
  }

  // ---------- 记录 ----------

  /// 记录一次隐私空间浏览（相同 URL 去重置顶，环形上限 [_maxRecords]）。
  void addRecord(BrowserRecord record) {
    if (!_unlocked || record.url.isEmpty) return;
    _records.removeWhere((item) => item.url == record.url);
    _records.insert(0, record);
    if (_records.length > _maxRecords) {
      _records.removeRange(_maxRecords, _records.length);
    }
    notifyListeners();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(persist());
    });
  }

  /// 把当前明文记录加密写盘（防抖窗口内也会落盘；锁定前调用可确保不丢）。
  Future<void> persist() async {
    final sessionKey = _sessionKey;
    if (sessionKey == null) return; // 未解锁时不应有明文可写
    final payload = utf8.encode(jsonEncode({
      'records': [for (final r in _records) r.toJson()],
    }));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dataKey,
        base64Encode(_xorStream(payload, _dataKeyBytes(sessionKey))));
  }

  /// 解锁后从磁盘解密记录到内存。
  Future<void> _decryptRecords() async {
    _records.clear();
    final sessionKey = _sessionKey;
    if (sessionKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_dataKey);
      if (raw == null || raw.isEmpty) return;
      final bytes = _xorStream(base64Decode(raw), _dataKeyBytes(sessionKey));
      final data = jsonDecode(utf8.decode(bytes));
      if (data is Map && data['records'] is List) {
        for (final item in (data['records'] as List)) {
          if (item is Map) {
            _records.add(BrowserRecord.fromJson(
                Map<String, Object?>.from(item.cast<String, Object?>())));
          }
        }
      }
    } catch (_) {
      // 解密失败（数据损坏等）：按空记录处理，不抛出。
      _records.clear();
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  // ---------- 加密基元 ----------

  static String _hash(String salt, String password) =>
      sha256.convert([...utf8.encode(salt), ...utf8.encode(password)]).toString();

  List<int> _dataKeyBytes(String password) =>
      sha256.convert(utf8.encode('yilan-vault-data|${_currentSalt()}|$password'))
          .bytes;

  String _currentSalt() => (_passwordBlob?['salt'] as String?) ?? '';

  static String _randomSalt() {
    final rnd = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }

  /// 流式异或：密钥流 = SHA-256(key || 计数器) 按 32 字节分块循环。
  static Uint8List _xorStream(List<int> data, List<int> key) {
    final out = Uint8List(data.length);
    Uint8List block = Uint8List(0);
    for (var i = 0; i < data.length; i++) {
      if (i % 32 == 0) {
        final counter = ByteData(4)..setUint32(0, i ~/ 32);
        block = Uint8List.fromList(sha256
            .convert([...key, ...counter.buffer.asUint8List()]).bytes);
      }
      out[i] = data[i] ^ block[i % 32];
    }
    return out;
  }
}
