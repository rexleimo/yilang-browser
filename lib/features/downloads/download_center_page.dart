import 'package:flutter/material.dart';

import '../../core/models/download_task.dart';
import 'download_controller.dart';

class DownloadCenterPage extends StatefulWidget {
  const DownloadCenterPage({super.key, required this.controller});

  final DownloadController controller;

  @override
  State<DownloadCenterPage> createState() => _DownloadCenterPageState();
}

class _DownloadCenterPageState extends State<DownloadCenterPage> {
  final _search = TextEditingController();
  DownloadTaskStatus? _status;

  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final tasks = widget.controller.filtered(_search.text, _status);
        return Scaffold(
          appBar: AppBar(
            title: const Text('下载中心'),
            actions: [
              IconButton(
                tooltip: '刷新下载状态',
                onPressed: widget.controller.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: '搜索文件名、网址或失败原因',
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    ChoiceChip(
                      label: const Text('全部'),
                      selected: _status == null,
                      onSelected: (_) => setState(() => _status = null),
                    ),
                    for (final status in DownloadTaskStatus.values)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text(_statusLabel(status)),
                          selected: _status == status,
                          onSelected: (_) => setState(() => _status = status),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: widget.controller.loading
                    ? const Center(child: CircularProgressIndicator())
                    : tasks.isEmpty
                        ? Center(
                            child: Text(
                              _search.text.isEmpty && _status == null
                                  ? '暂无下载任务'
                                  : '没有匹配的下载任务',
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: tasks.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, index) => _DownloadTaskCard(
                              task: tasks[index],
                              onRetry: () =>
                                  widget.controller.retry(tasks[index]),
                              onCancel: () =>
                                  widget.controller.cancel(tasks[index]),
                              onDelete: () =>
                                  widget.controller.delete(tasks[index]),
                              onOpen: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final error =
                                    await widget.controller.open(tasks[index]);
                                if (error != null && mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('无法打开文件：$error')),
                                  );
                                }
                              },
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DownloadTaskCard extends StatelessWidget {
  const _DownloadTaskCard({
    required this.task,
    required this.onRetry,
    required this.onCancel,
    required this.onDelete,
    required this.onOpen,
  });

  final DownloadTask task;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final active = task.status == DownloadTaskStatus.queued ||
        task.status == DownloadTaskStatus.running ||
        task.status == DownloadTaskStatus.paused;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon(task.status)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(task.title.isEmpty ? task.fileName : task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Chip(label: Text(_statusLabel(task.status))),
              ],
            ),
            const SizedBox(height: 8),
            Text(task.url, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (active) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                  value: task.totalBytes == null ? null : task.progress),
              const SizedBox(height: 4),
              Text(
                  '${_bytes(task.downloadedBytes)}${task.totalBytes == null ? '' : ' / ${_bytes(task.totalBytes!)}'}'),
            ],
            if (task.error != null && task.error!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('失败原因：${task.error}',
                  key: const Key('download-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                if (task.status == DownloadTaskStatus.completed)
                  TextButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('打开文件')),
                if (task.status == DownloadTaskStatus.failed ||
                    task.status == DownloadTaskStatus.cancelled)
                  TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试')),
                if (active)
                  TextButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('取消')),
                TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(DownloadTaskStatus status) => switch (status) {
      DownloadTaskStatus.queued => '等待中',
      DownloadTaskStatus.running => '下载中',
      DownloadTaskStatus.paused => '已暂停',
      DownloadTaskStatus.completed => '已完成',
      DownloadTaskStatus.failed => '失败',
      DownloadTaskStatus.cancelled => '已取消',
    };

IconData _icon(DownloadTaskStatus status) => switch (status) {
      DownloadTaskStatus.completed => Icons.check_circle_outline,
      DownloadTaskStatus.failed => Icons.error_outline,
      DownloadTaskStatus.cancelled => Icons.cancel_outlined,
      _ => Icons.downloading_outlined,
    };

String _bytes(int value) {
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
}
