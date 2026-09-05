import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/logic/board_model.dart';
import '../../core/logic/search_engines.dart';
import '../../core/storage/bookmark_codec.dart';
import '../../core/widgets/browser_chrome.dart';
import '../../core/widgets/ui_kit.dart';
import '../../theme/app_theme.dart';
import '../browser/services/browser_data_store.dart';

/// Application settings — 系统式分层设置：分组卡片 + 子页推进（← 返回 / X 关闭），
/// 顶部支持搜索过滤。行为对齐 Brave 设置页的操作习惯。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.model,
    this.onBack,
    this.onClearBrowsingData,
  });

  final BoardModel model;
  final VoidCallback? onBack;

  /// 按范围清除浏览数据（浏览器页执行），返回各范围清理条数。
  final Future<Map<BrowserDataScope, int>> Function(
          Set<BrowserDataScope> scopes)?
      onClearBrowsingData;

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
          if (hit('桌面版'))
            UiTile(
              icon: Icons.desktop_windows_outlined,
              title: '桌面版网站',
              subtitle: '所有标签页以桌面浏览器身份请求网页',
              trailing: UiSwitch(
                value: s.desktopUA,
                onChanged: (value) {
                  s.desktopUA = value;
                  model.save();
                },
              ),
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
          if (hit('清除浏览数据'))
            UiTile(
              icon: Icons.cleaning_services_outlined,
              title: '清除浏览数据',
              subtitle: '历史、Cookie、缓存、近期搜索、离线副本',
              onTap: widget.onClearBrowsingData == null
                  ? null
                  : () => _push(
                        context,
                        _ClearDataSubPage(onClear: widget.onClearBrowsingData!),
                      ),
            ),
          if (hit('启动恢复'))
            UiTile(
              icon: Icons.restore_outlined,
              title: '启动时恢复标签页',
              subtitle: '冷启动后回到上次退出前的标签页集合',
              trailing: UiSwitch(
                value: s.restoreSession,
                onChanged: (value) {
                  s.restoreSession = value;
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
          if (hit('书签导入导出'))
            UiTile(
              icon: Icons.import_export,
              title: '书签导入导出',
              subtitle: '与其他浏览器互通（Netscape HTML）',
              onTap: () => _push(context, _BookmarkTransferSubPage(model)),
            ),
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
                         // 全局输入主题带灰蓝填充和描边，会嵌在自绘胶囊里，
                         // 这里全部关掉只留裸文本
                         decoration: const InputDecoration(
                           isDense: true,
                           filled: false,
                           border: InputBorder.none,
                           enabledBorder: InputBorder.none,
                           focusedBorder: InputBorder.none,
                           contentPadding: EdgeInsets.zero,
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
                icon: Icons.public,
                title: '联网搜索建议',
                subtitle: '输入时向搜索引擎拉取实时建议词（无痕标签页不联网）',
                trailing: UiSwitch(
                  value: s.suggestRemote,
                  onChanged: (value) {
                    s.suggestRemote = value;
                    model.save();
                  },
                ),
              ),
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
              subtitle: '应用界面使用深色配色（网页内容保持原样）',
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

/// 清除浏览数据：勾选范围 → 确认 → 由浏览器页执行（内存与磁盘同步清理）。
class _ClearDataSubPage extends StatefulWidget {
  const _ClearDataSubPage({required this.onClear});

  final Future<Map<BrowserDataScope, int>> Function(Set<BrowserDataScope>) onClear;

  @override
  State<_ClearDataSubPage> createState() => _ClearDataSubPageState();
}

class _ClearDataSubPageState extends State<_ClearDataSubPage> {
  bool _history = true;
  bool _cookies = true;
  bool _cache = true;
  bool _recentSearches = true;
  bool _offlineCopies = false;
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    return _SubPageScaffold(title: '清除浏览数据', children: [
      const UiSectionLabel('选择要清除的内容'),
      UiCard(children: [
        UiTile(
          icon: Icons.history,
          title: '浏览历史',
          trailing: UiSwitch(
            value: _history,
            onChanged: (v) => setState(() => _history = v),
          ),
        ),
        UiTile(
          icon: Icons.cookie_outlined,
          title: 'Cookie 和网站登录态',
          subtitle: '清除后所有网站都需要重新登录',
          trailing: UiSwitch(
            value: _cookies,
            onChanged: (v) => setState(() => _cookies = v),
          ),
        ),
        UiTile(
          icon: Icons.storage_outlined,
          title: '缓存与本地存储',
          trailing: UiSwitch(
            value: _cache,
            onChanged: (v) => setState(() => _cache = v),
          ),
        ),
        UiTile(
          icon: Icons.manage_search,
          title: '近期搜索词',
          trailing: UiSwitch(
            value: _recentSearches,
            onChanged: (v) => setState(() => _recentSearches = v),
          ),
        ),
        UiTile(
          icon: Icons.offline_bolt_outlined,
          title: '离线阅读副本',
          subtitle: '删除已下载的文章副本（阅读清单条目保留）',
          trailing: UiSwitch(
            value: _offlineCopies,
            onChanged: (v) => setState(() => _offlineCopies = v),
          ),
        ),
      ]),
      const SizedBox(height: 20),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _running ? null : _run,
        icon: _running
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.cleaning_services_outlined),
        label: const Text('清除所选数据'),
      ),
    ]);
  }

  Future<void> _run() async {
    final scopes = <BrowserDataScope>{
      if (_history) BrowserDataScope.history,
      if (_cookies) BrowserDataScope.cookies,
      if (_cache) BrowserDataScope.cache,
      if (_recentSearches) BrowserDataScope.recentSearches,
      if (_offlineCopies) BrowserDataScope.offlineCopies,
    };
    if (scopes.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除浏览数据？'),
        content: const Text('所选内容将从本机删除，且无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _running = true);
    try {
      final cleared = await widget.onClear(scopes);
      if (!mounted) return;
      final parts = <String>[];
      if (cleared.containsKey(BrowserDataScope.history)) {
        parts.add('历史 ${cleared[BrowserDataScope.history]} 条');
      }
      if (cleared.containsKey(BrowserDataScope.offlineCopies)) {
        parts.add('离线副本 ${cleared[BrowserDataScope.offlineCopies]} 份');
      }
      if (parts.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已清除所选数据')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已清除：${parts.join('、')}')));
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('清除失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}

/// 书签导入导出：Netscape HTML，与 Chrome/Safari/Firefox 互通。
class _BookmarkTransferSubPage extends StatefulWidget {
  const _BookmarkTransferSubPage(this.model);

  final BoardModel model;

  @override
  State<_BookmarkTransferSubPage> createState() =>
      _BookmarkTransferSubPageState();
}

class _BookmarkTransferSubPageState extends State<_BookmarkTransferSubPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return _SubPageScaffold(title: '书签导入导出', children: [
      const UiSectionLabel('导出'),
      UiCard(children: [
        UiTile(
          icon: Icons.ios_share,
          title: '导出为 HTML 文件',
          subtitle: '生成通用书签文件并可分享保存',
          onTap: _busy ? null : _export,
        ),
      ]),
      const SizedBox(height: 14),
      const UiSectionLabel('导入'),
      UiCard(children: [
        UiTile(
          icon: Icons.file_open_outlined,
          title: '从 HTML 文件导入',
          subtitle: '支持 Chrome / Safari / Firefox 导出的书签文件',
          onTap: _busy ? null : _import,
        ),
      ]),
    ]);
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final directory = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[-:T.]'), '')
          .substring(0, 14);
      final path = '${directory.path}/yilan_bookmarks_$stamp.html';
      final html = BookmarkCodec.exportHtml(widget.model.pages);
      await File(path).writeAsString(html, encoding: utf8);
      if (!mounted) return;
      await Share.shareXFiles([XFile(path, mimeType: 'text/html')],
          subject: '一览 Yilan 书签导出');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['html', 'htm'],
      );
      final path = picked?.files.single.path;
      if (path == null) return;
      final raw = await File(path).readAsString();
      final items = BookmarkCodec.parse(raw);
      final imported = await widget.model.importBookmarks(items);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(imported > 0
            ? '已导入 $imported 条书签（去重后）'
            : '没有发现可导入的新书签'),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
