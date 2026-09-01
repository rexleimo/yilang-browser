import 'package:flutter/material.dart';

import '../../core/logic/board_model.dart';
import '../../theme/app_theme.dart';

/// Application settings.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.model, this.onBack});

  final BoardModel model;
  final VoidCallback? onBack;

  Future<void> _chooseSearchEngine(BuildContext context) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择搜索引擎'),
        children: [
          for (var i = 0; i < Settings.engines.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, i),
              child: Row(
                children: [
                  Icon(
                    i == model.settings.searchEngineIndex
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: i == model.settings.searchEngineIndex
                        ? AppColors.primary
                        : AppColors.subText,
                  ),
                  const SizedBox(width: 10),
                  Text(Settings.engines[i]),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) {
      model.settings.searchEngineIndex = selected;
      await model.save();
    }
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: '一览 Yilan',
      applicationVersion: '0.1.0',
      applicationLegalese: '书签与浏览器工作台',
    );
  }

  void _showPrivacy(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('隐私说明'),
        content:
            const Text('一览优先在本机保存书签、历史记录和阅读清单。无痕标签页关闭后不写入历史或书签。网页内容由当前网站直接提供。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final s = model.settings;
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Row(
                children: [
                  if (onBack != null)
                    IconButton(
                      tooltip: '返回',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_ios_new),
                    ),
                  const Expanded(
                    child: Text('设置',
                        style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('配置一览浏览器和书签行为',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 22),
              const _SectionTitle('浏览器'),
              _Card(
                children: [
                  _ActionRow(
                    icon: Icons.search,
                    title: '搜索引擎',
                    value: Settings.engines[s.searchEngineIndex
                        .clamp(0, Settings.engines.length - 1)],
                    onTap: () => _chooseSearchEngine(context),
                  ),
                  _SwitchRow(
                    icon: Icons.visibility_off_outlined,
                    title: '无痕浏览',
                    subtitle: '新建标签页时默认使用无痕模式',
                    value: s.incognito,
                    onChanged: (value) {
                      s.incognito = value;
                      model.save();
                    },
                  ),
                  _SwitchRow(
                    icon: Icons.block_outlined,
                    title: '广告拦截（实验）',
                    subtitle: '当前仅保存偏好，网页拦截规则仍在开发',
                    value: s.adBlock,
                    onChanged: (value) {
                      s.adBlock = value;
                      model.save();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const _SectionTitle('外观与数据'),
              _Card(
                children: [
                  _SwitchRow(
                    icon: Icons.dark_mode_outlined,
                    title: '深色模式',
                    value: s.darkMode,
                    onChanged: (value) {
                      s.darkMode = value;
                      model.save();
                    },
                  ),
                  _SwitchRow(
                    icon: Icons.cloud_outlined,
                    title: '书签云同步（实验）',
                    subtitle: '当前只保存在本机，云端同步尚未接入',
                    value: s.sync,
                    onChanged: (value) {
                      s.sync = value;
                      model.save();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const _SectionTitle('关于'),
              _Card(
                children: [
                  _ActionRow(
                    icon: Icons.privacy_tip_outlined,
                    title: '隐私说明',
                    value: '本机优先',
                    onTap: () => _showPrivacy(context),
                  ),
                  _ActionRow(
                    icon: Icons.info_outline,
                    title: '关于一览 Yilan',
                    value: 'v0.1.0',
                    onTap: () => _showAbout(context),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: tokens.surface.withValues(alpha: .78),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1)
            Divider(height: 1, indent: 58, color: tokens.outline),
        ],
      ]),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow(
      {required this.icon,
      required this.title,
      required this.value,
      required this.onTap});

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(color: tokens.textSecondary)),
          Icon(Icons.chevron_right, color: tokens.textSecondary)
        ],
      ),
      onTap: onTap,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow(
      {required this.icon,
      required this.title,
      required this.value,
      required this.onChanged,
      this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textSecondary)),
      value: value,
      onChanged: onChanged,
    );
  }
}
