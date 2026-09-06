import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../services/vault_store.dart';

/// 隐私空间（超级保密箱）。
///
/// 三态：未设密码 → 设置流程；已锁定 → 密码解锁；已解锁 → 记录列表。
/// 解锁状态下可一键回到浏览器开一个隐私空间标签页，浏览记录只进保险箱。
class VaultPage extends StatefulWidget {
  const VaultPage({super.key, required this.store, this.onBrowseInVault});

  final VaultStore store;

  /// 「开始浏览」回调：由浏览器面板进入时传入，用于打开隐私空间标签页。
  final VoidCallback? onBrowseInVault;

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        if (!widget.store.hasPassword) return _setupScaffold;
        if (!widget.store.unlocked) return _unlockScaffold;
        return _contentScaffold;
      },
    );
  }

  // ---------- 通用装饰 ----------

  Widget _shell({required Widget child, List<Widget> actions = const []}) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私空间'),
        actions: actions,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _heroIcon(IconData icon, {Color? color}) {
    final tokens = context.browserTokens;
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (color ?? tokens.privateAccent).withValues(alpha: .14),
        border: Border.all(
            color: (color ?? tokens.privateAccent).withValues(alpha: .5),
            width: 1.5),
      ),
      child: Icon(icon, size: 40, color: color ?? tokens.privateAccent),
    );
  }

  TextField _passwordField(TextEditingController controller, String label,
      {void Function(String)? onSubmitted, String? errorText}) {
    final tokens = context.browserTokens;
    return TextField(
      controller: controller,
      obscureText: _obscure,
      autofocus: true,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        prefixIcon: Icon(Icons.lock_outline, color: tokens.privateAccent),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      onSubmitted: onSubmitted,
    );
  }

  // ---------- 1. 首次设置密码 ----------

  Widget get _setupScaffold {
    return _shell(
      child: Column(
        children: [
          _heroIcon(Icons.enhanced_encryption_outlined),
          const SizedBox(height: 18),
          const Text('设置隐私空间密码',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            '在隐私空间里的浏览记录会加密保存，\n只有输入密码才能查看。密码不设找回，\n忘记密码将清空全部记录。',
            textAlign: TextAlign.center,
            style: TextStyle(
                height: 1.6,
                fontSize: 13.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 26),
          _passwordField(_password, '设置密码（至少 4 位）'),
          const SizedBox(height: 14),
          _passwordField(_confirm, '再输一次确认', errorText: _error),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.lock_outline),
              label: const Text('开启隐私空间'),
              onPressed: _busy ? null : _submitSetup,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitSetup() async {
    final password = _password.text.trim();
    if (password.length < 4) {
      setState(() => _error = '密码至少 4 位');
      return;
    }
    if (password != _confirm.text.trim()) {
      setState(() => _error = '两次输入不一致');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.store.setPassword(password);
    _password.clear();
    _confirm.clear();
    setState(() => _busy = false);
  }

  // ---------- 2. 解锁 ----------

  Widget get _unlockScaffold {
    return _shell(
      child: Column(
        children: [
          _heroIcon(Icons.lock_outlined),
          const SizedBox(height: 18),
          const Text('隐私空间已锁定',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('输入密码查看加密的浏览记录',
              style: TextStyle(
                  fontSize: 13.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 26),
          _passwordField(_password, '输入密码',
              onSubmitted: (_) => _submitUnlock(), errorText: _error),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.key_outlined),
              label: const Text('解锁'),
              onPressed: _busy ? null : _submitUnlock,
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _busy ? null : _confirmForgot,
            child: Text('忘记密码？重置并清空隐私空间',
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitUnlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.store.verify(_password.text.trim());
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = '密码不正确';
      });
      return;
    }
    _password.clear();
    setState(() => _busy = false);
  }

  Future<void> _confirmForgot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置隐私空间？'),
        content: const Text('忘记密码无法找回记录。重置将删除密码与隐私空间里的全部浏览记录，此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('重置并清空')),
        ],
      ),
    );
    if (ok == true) await widget.store.resetAll();
  }

  // ---------- 3. 已解锁：记录列表 ----------

  Widget get _contentScaffold {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.browserTokens;
    final records = widget.store.records;
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私空间'),
        actions: [
          IconButton(
            tooltip: '锁定',
            icon: const Icon(Icons.lock_outline),
            onPressed: _busy ? null : _lockNow,
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'clear') _confirmClearVault();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    leading: Icon(Icons.delete_forever_outlined),
                    title: Text('清空浏览记录'),
                    dense: true,
                  )),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: tokens.privateAccent,
                        foregroundColor:
                            Colors.white,
                      ),
                      icon: const Icon(Icons.visibility_off_outlined, size: 18),
                      label: const Text('在此空间中浏览',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      onPressed:
                          widget.onBrowseInVault == null ? null : _browseInVault,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _heroIcon(Icons.lock_outlined),
                        const SizedBox(height: 14),
                        Text('这里还没有浏览记录',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface)),
                        const SizedBox(height: 6),
                        Text('在隐私空间中打开的网页会记录在这里',
                            style: TextStyle(
                                fontSize: 13, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final record = records[index];
                      final host = Uri.tryParse(record.url)?.host ?? '';
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest
                              .withValues(alpha: .45),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outlined,
                                size: 16,
                                color: tokens.privateAccent.withValues(alpha: .8)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    record.title.isEmpty ? host : record.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurface),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    host,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            Text(_formatTime(record.visitedAt),
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _browseInVault() async {
    // 先确保护密钥在手的记录落盘，再交回浏览器开标签页。
    await widget.store.persist();
    widget.onBrowseInVault?.call();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _lockNow() async {
    await widget.store.persist(); // 防抖窗口内的记录先落盘
    widget.store.lock();
  }

  Future<void> _confirmClearVault() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空浏览记录？'),
        content: const Text('将删除隐私空间里的全部浏览记录（保留密码），此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) {
      await widget.store.resetRecords();
    }
  }

  static String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${time.year}-${time.month}-${time.day}';
  }
}
