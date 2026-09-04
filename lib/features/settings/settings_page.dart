import 'package:flutter/material.dart';

import '../../core/logic/board_model.dart';
import '../../core/logic/search_engines.dart';
import '../../core/widgets/browser_chrome.dart';
import '../../core/widgets/ui_kit.dart';
import '../../theme/app_theme.dart';

/// Application settings — 系统式分层设置：分组卡片 + 子页推进（← 返回 / X 关闭），
/// 顶部支持搜索过滤。行为对齐 Brave 设置页的操作习惯。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.model, this.onBack});

  final BoardModel model;
  final VoidCallback? onBack;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _query = '';

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _openSearchSettings(BuildContext context) {
    _push(context, _SearchSubPage(widget.model));
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final s = model.settings;
        final q = _query.trim().toLowerCase();
        bool hit(String title) => q.isEmpty || title.toLowerCase().contains(q);

        final rowsGeneral = [
          if (hit('搜索引擎'))
            UiTile(
              icon: Icons.search,
              title: '搜索引擎',
              value: SearchEngines.name(s.searchEngineIndex),
              onTap: () => _openSearchSettings(context),
            ),
          if (hit('外观'))
            UiTile(
              icon: Icons.palette_outlined,
              title: '外观',
              value: s.darkMode ? '深色' : '浅色',
              onTap: () => _push(context, _AppearanceSubPage(model)),
            ),
        ];
        final rowsPrivacy = [
          if (hit('无痕浏览'))
            UiTile(
              icon: Icons.visibility_off_outlined,
              title: '无痕浏览',
              subtitle: '新建标签页时默认使用无痕模式',
              trailing: UiSwitch(
                value: s.incognito,
                onChanged: (value) {
                  s.incognito = value;
                  model.save();
                },
              ),
            ),
          if (hit('广告拦截'))
            UiTile(
              icon: Icons.block_outlined,
              title: '广告拦截',
              subtitle: '拦截广告、跟踪脚本与弹窗（内置规则）',
              trailing: UiSwitch(
                value: s.adBlock,
                onChanged: (value) {
                  s.adBlock = value;
                  model.save();
                },
              ),
            ),
          if (hit('隐私说明'))
            UiTile(
              icon: Icons.privacy_tip_outlined,
              title: '隐私说明',
              value: '本机优先',
              onTap: () => _push(context, const _PrivacySubPage()),
            ),
        ];
        final rowsData = [
          if (hit('书签云同步'))
            UiTile(
              icon: Icons.cloud_outlined,
              title: '书签云同步（实验）',
              subtitle: '当前只保存在本机，云端同步尚未接入',
              trailing: UiSwitch(
                value: s.sync,
                onChanged: (value) {
                  s.sync = value;
                  model.save();
                },
              ),
            ),
        ];
        final rowsAbout = [
          if (hit('关于一览'))
            UiTile(
              icon: Icons.info_outline,
              title: '关于一览 Yilan',
              value: 'v0.1.0',
              onTap: () => _push(context, const _AboutSubPage()),
            ),
        ];

        return UiScreen(
          title: '设置',
          subtitle: '配置一览浏览器和书签行为',
          onBack: widget.onBack,
          children: [
            // 系统式搜索框：过滤下方所有条目
            Material(
              color: Colors.transparent,
              child: Container(
                height: 46,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: UIKit.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: UIKit.hairline),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 19, color: UIKit.sub),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        style:
                            const TextStyle(fontSize: 14.5, color: UIKit.ink),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: '搜索设置',
                          hintStyle:
                              TextStyle(fontSize: 14.5, color: UIKit.sub),
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _query = ''),
                        child:
                            const Icon(Icons.close, size: 17, color: UIKit.sub),
                      ),
                  ],
                ),
              ),
            ),
            if (rowsGeneral.isNotEmpty) ...[
              const UiSectionLabel('常规'),
              UiCard(children: rowsGeneral),
              const SizedBox(height: 26),
            ],
            if (rowsPrivacy.isNotEmpty) ...[
              const UiSectionLabel('隐私'),
              UiCard(children: rowsPrivacy),
              const SizedBox(height: 26),
            ],
            if (rowsData.isNotEmpty) ...[
              const UiSectionLabel('数据'),
              UiCard(children: rowsData),
              const SizedBox(height: 26),
            ],
            if (rowsAbout.isNotEmpty) ...[
              const UiSectionLabel('关于'),
              UiCard(children: rowsAbout),
              const SizedBox(height: 26),
            ],
            if (q.isNotEmpty &&
                rowsGeneral.isEmpty &&
                rowsPrivacy.isEmpty &&
                rowsData.isEmpty &&
                rowsAbout.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text('没有匹配的设置项',
                      style: TextStyle(fontSize: 13.5, color: UIKit.sub)),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 系统式子页壳：← 返回 + 标题 + X 关闭。
class _SubPageScaffold extends StatelessWidget {
  const _SubPageScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UIKit.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭设置',
                    onPressed: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                    icon: const Icon(Icons.close, size: 22),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 搜索引擎单选行：品牌 Logo + 名称 + 选中态。
class _EngineOptionRow extends StatelessWidget {
  const _EngineOptionRow({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            EngineLogo(index: index, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                SearchEngines.name(index),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppColors.brand, size: 22)
            else
              Icon(Icons.circle_outlined,
                  color: scheme.onSurfaceVariant.withValues(alpha: .4),
                  size: 22),
          ],
        ),
      ),
    );
  }
}

/// 搜索设置：常规 / 无痕两套默认引擎 + 地址栏建议开关。
class _SearchSubPage extends StatelessWidget {
  const _SearchSubPage(this.model);

  final BoardModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final s = model.settings;
        return _SubPageScaffold(title: '搜索', children: [
          const UiSectionLabel('默认搜索引擎'),
          UiCard(
            children: [
              for (var i = 0; i < SearchEngines.names.length; i++)
                _EngineOptionRow(
                  index: i,
                  selected: i == SearchEngines.clamp(s.searchEngineIndex),
                  onTap: () {
                    s.searchEngineIndex = i;
                    model.save();
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          const UiSectionLabel('无痕模式搜索引擎'),
          UiCard(
            children: [
              for (var i = 0; i < SearchEngines.names.length; i++)
                _EngineOptionRow(
                  index: i,
                  selected:
                      i == SearchEngines.clamp(s.privateSearchEngineIndex),
                  onTap: () {
                    s.privateSearchEngineIndex = i;
                    model.save();
                  },
                ),
              const UiTile(
                icon: Icons.help_outline,
                title: '什么是无痕搜索引擎？',
                subtitle: '无痕标签页里搜索时优先使用这里的引擎',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const UiSectionLabel('地址栏建议'),
          UiCard(
            children: [
              UiTile(
                icon: Icons.history,
                title: '近期搜索',
                subtitle: '地址栏下拉里快速找回最近搜过的内容',
                trailing: UiSwitch(
                  value: s.suggestRecent,
                  onChanged: (value) {
                    s.suggestRecent = value;
                    model.save();
                  },
                ),
              ),
              UiTile(
                icon: Icons.star_border,
                title: '搜索书签',
                trailing: UiSwitch(
                  value: s.suggestBookmarks,
                  onChanged: (value) {
                    s.suggestBookmarks = value;
                    model.save();
                  },
                ),
              ),
              UiTile(
                icon: Icons.history_edu_outlined,
                title: '搜索历史记录',
                trailing: UiSwitch(
                  value: s.suggestHistory,
                  onChanged: (value) {
                    s.suggestHistory = value;
                    model.save();
                  },
                ),
              ),
              UiTile(
                icon: Icons.tab_outlined,
                title: '搜索打开的标签页',
                trailing: UiSwitch(
                  value: s.suggestTabs,
                  onChanged: (value) {
                    s.suggestTabs = value;
                    model.save();
                  },
                ),
              ),
            ],
          ),
        ]);
      },
    );
  }
}

class _AppearanceSubPage extends StatelessWidget {
  const _AppearanceSubPage(this.model);

  final BoardModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final s = model.settings;
        return _SubPageScaffold(title: '外观', children: [
          const UiSectionLabel('常规'),
          UiCard(children: [
            UiTile(
              icon: Icons.dark_mode_outlined,
              title: '深色模式',
              subtitle: '强制网页内容使用深色配色',
              trailing: UiSwitch(
                value: s.darkMode,
                onChanged: (value) {
                  s.darkMode = value;
                  model.save();
                },
              ),
            ),
          ]),
        ]);
      },
    );
  }
}

class _PrivacySubPage extends StatelessWidget {
  const _PrivacySubPage();

  @override
  Widget build(BuildContext context) {
    return const _SubPageScaffold(title: '隐私说明', children: [
      UiPrivacyCard(
        text:
            '一览优先在本机保存书签、历史记录和阅读清单。无痕标签页关闭后不写入历史或书签。网页内容由当前网站直接提供。',
      ),
      SizedBox(height: 16),
      UiSectionLabel('数据'),
      UiCard(children: [
        UiTile(
          icon: Icons.history,
          title: '历史记录',
          subtitle: '仅保存在本机，可随时清空',
        ),
        UiTile(
          icon: Icons.bookmark_add_outlined,
          title: '阅读清单',
          subtitle: '离线保存的待读页面列表',
        ),
      ]),
    ]);
  }
}

class _AboutSubPage extends StatelessWidget {
  const _AboutSubPage();

  @override
  Widget build(BuildContext context) {
    return _SubPageScaffold(title: '关于一览 Yilan', children: [
      const UiAboutCard(
        icon: Icons.dashboard_outlined,
        name: '一览 Yilan',
        version: 'v0.1.0',
        description: '书签与浏览器工作台',
      ),
      const SizedBox(height: 16),
      UiCard(children: [
        UiTile(
          icon: Icons.privacy_tip_outlined,
          title: '隐私说明',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const _PrivacySubPage()),
          ),
        ),
      ]),
    ]);
  }
}

/// 关于卡片（Kit 组件：图标 + 应用名 + 版本胶囊 + 描述）。
class UiAboutCard extends StatelessWidget {
  const UiAboutCard({
    super.key,
    required this.icon,
    required this.name,
    required this.version,
    required this.description,
  });

  final IconData icon;
  final String name;
  final String version;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: UIKit.accentSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, size: 28, color: UIKit.accent),
          ),
          const SizedBox(height: 12),
          Text(name,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: UIKit.ink)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: UIKit.accentSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(version,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: UIKit.accent)),
          ),
          const SizedBox(height: 10),
          Text(description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12.5, color: UIKit.sub, height: 1.6)),
        ],
      ),
    );
  }
}

/// 隐私说明卡片：描述文字。
class UiPrivacyCard extends StatelessWidget {
  const UiPrivacyCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: UIKit.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.lock_outline, size: 18, color: UIKit.accent),
              ),
              const SizedBox(width: 10),
              const Text('本机优先',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: UIKit.ink)),
            ],
          ),
          const SizedBox(height: 12),
          Text(text,
              style: const TextStyle(
                  fontSize: 13, color: UIKit.sub, height: 1.7)),
        ],
      ),
    );
  }
}
