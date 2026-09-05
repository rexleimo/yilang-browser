import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// A pushed, full-screen list (normal navigation with a real back button) for
/// either browsing history or the reading list.
class CollectionEntry {
  const CollectionEntry({
    required this.title,
    required this.url,
    required this.time,
    this.excerpt = '',
    this.offlineHtmlPath,
    this.readerHtmlPath,
    this.readAt,
  });

  final String title;
  final String url;
  final DateTime time;
  final String excerpt;
  final String? offlineHtmlPath;

  /// 阅读模式净化副本路径（仅阅读清单使用）。
  final String? readerHtmlPath;

  /// 阅读完成时间；null 表示未读（仅阅读清单使用）。
  final DateTime? readAt;

  bool get hasOfflineCopy =>
      offlineHtmlPath != null && offlineHtmlPath!.isNotEmpty;

  bool get hasReaderCopy =>
      readerHtmlPath != null && readerHtmlPath!.isNotEmpty;

  bool get isUnread => readAt == null;
}

class BrowserCollectionPage extends StatefulWidget {
  const BrowserCollectionPage({
    super.key,
    required this.history,
    required this.items,
    required this.onOpen,
    this.onRemove,
    this.onClear,
    this.onConvert,
    this.onBack,
  });

  final bool history;

  /// Snapshot of the list when the page opens.
  final List<CollectionEntry> items;
  final ValueChanged<CollectionEntry> onOpen;
  final ValueChanged<String>? onRemove;
  final Future<void> Function()? onClear;

  /// 把条目转成书签（仅阅读清单）。
  final ValueChanged<CollectionEntry>? onConvert;
  final VoidCallback? onBack;

  @override
  State<BrowserCollectionPage> createState() => _BrowserCollectionPageState();
}

class _BrowserCollectionPageState extends State<BrowserCollectionPage> {
  final TextEditingController _search = TextEditingController();
  late List<CollectionEntry> _items;
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CollectionEntry> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _items
        .where((item) {
          if (!widget.history && _unreadOnly && !item.isUnread) return false;
          if (query.isEmpty) return true;
          return item.title.toLowerCase().contains(query) ||
              item.url.toLowerCase().contains(query);
        })
        .toList();
  }

  void _remove(CollectionEntry item) {
    setState(() => _items.removeWhere((entry) => entry.url == item.url));
    widget.onRemove?.call(item.url);
  }

  Future<void> _clearAll() async {
    if (_items.isEmpty || widget.onClear == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.history ? '清空历史记录？' : '清空阅读清单？'),
        content: Text(
            widget.history ? '这只会移除历史记录，不会影响书签和阅读清单。' : '已保存的文章将从阅读清单中移除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(_items.clear);
    await widget.onClear!.call();
  }

  String _stamp(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.browserTokens;
    final scheme = Theme.of(context).colorScheme;
    final items = _filtered;
    return PopScope(
      canPop: widget.onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack?.call();
      },
      child: Scaffold(
        backgroundColor: tokens.chromeBackground,
        appBar: AppBar(
          toolbarHeight: 52,
          backgroundColor: tokens.toolbarBackground,
          foregroundColor: tokens.addressBarForeground,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          title: Text(
            widget.history ? '历史记录' : '阅读清单',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          leading: IconButton(
            tooltip: '返回',
            onPressed: widget.onBack ?? () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back, size: 22),
          ),
          actions: [
            if (widget.onClear != null && _items.isNotEmpty)
              TextButton(
                onPressed: _clearAll,
                child: const Text('清空'),
              ),
          ],
        ),
        body: Column(
          children: [
            Container(
              color: tokens.toolbarBackground,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                        fontSize: 14, color: tokens.addressBarForeground),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor:
                          scheme.surfaceContainerHighest.withValues(alpha: .55),
                      hintText: widget.history ? '搜索历史' : '搜索已保存的文章',
                      prefixIcon: const Icon(Icons.search, size: 19),
                      prefixIconColor: tokens.addressBarForeground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                    ),
                  ),
                  if (!widget.history) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('全部'),
                          selected: !_unreadOnly,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _unreadOnly = false),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text(
                              '未读（${_items.where((item) => item.isUnread).length}）'),
                          selected: _unreadOnly,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _unreadOnly = true),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.history
                                ? Icons.history
                                : Icons.chrome_reader_mode_outlined,
                            size: 44,
                            color: tokens.addressBarForeground
                                .withValues(alpha: .35),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.history ? '还没有浏览记录' : '还没有保存的文章',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: tokens.addressBarForeground),
                          ),
                          if (!widget.history) ...[
                            const SizedBox(height: 6),
                            Text(
                              '在网页的“面板”菜单里点“加入阅读清单”',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 16,
                        color: tokens.divider,
                      ),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final host = Uri.tryParse(item.url)?.host ?? item.url;
                        return InkWell(
                          onTap: () => widget.onOpen(item),
                          onLongPress: widget.onRemove == null
                              ? null
                              : () => _confirmRemove(item),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          if (!widget.history &&
                                              item.isUnread) ...[
                                            Container(
                                              width: 7,
                                              height: 7,
                                              margin: const EdgeInsets.only(
                                                  right: 6),
                                              decoration: const BoxDecoration(
                                                color: AppColors.brand,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                          Expanded(
                                            child: Text(
                                              item.title.isEmpty
                                                  ? item.url
                                                  : item.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14.5,
                                                fontWeight:
                                                    (!widget.history &&
                                                            item.isUnread)
                                                        ? FontWeight.w700
                                                        : FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.url,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        host,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      if (!widget.history &&
                                          item.excerpt.trim().isNotEmpty) ...[
                                        const SizedBox(height: 5),
                                        Text(
                                          item.excerpt.replaceAll('\n', ' '),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 12,
                                              height: 1.35,
                                              color: scheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _stamp(item.time),
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (!widget.history &&
                                        item.hasOfflineCopy)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 6),
                                        child: Icon(
                                          Icons.download_done,
                                          size: 16,
                                          color: AppColors.brandStrong,
                                        ),
                                      ),
                                    if (!widget.history &&
                                        widget.onConvert != null)
                                      IconButton(
                                        tooltip: '转为书签收藏',
                                        onPressed: () =>
                                            widget.onConvert!(item),
                                        visualDensity: VisualDensity.compact,
                                        icon: Icon(
                                          Icons.star_border,
                                          size: 18,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    if (widget.onRemove != null)
                                      IconButton(
                                        tooltip: '移除',
                                        onPressed: () => _confirmRemove(item),
                                        visualDensity: VisualDensity.compact,
                                        icon: Icon(
                                          Icons.close,
                                          size: 18,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(CollectionEntry item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.history ? '从历史记录移除？' : '从阅读清单移除？'),
        content: Text(item.title.isEmpty ? item.url : item.title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('移除')),
        ],
      ),
    );
    if (ok == true) _remove(item);
  }
}
