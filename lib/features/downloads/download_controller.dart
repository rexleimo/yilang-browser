import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/models/download_task.dart';
import '../../core/storage/download_task_store.dart';

abstract class DownloadPlatform {
  Future<Map<Object?, Object?>?> enqueue({
    required String url,
    required String fileName,
  });
  Future<Map<Object?, Object?>?> status(String platformId);
  Future<void> cancel(String platformId);
  Future<Map<Object?, Object?>?> retry({
    required String url,
    required String fileName,
  });
  Future<void> open(String platformId);
}

class MethodChannelDownloadPlatform implements DownloadPlatform {
  const MethodChannelDownloadPlatform();

  static const _channel =
      MethodChannel('com.yilan.yilan_browser/android_browser');

  void _checkPlatform() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('当前平台不支持系统下载服务');
    }
  }

  @override
  Future<Map<Object?, Object?>?> enqueue({
    required String url,
    required String fileName,
  }) async {
    _checkPlatform();
    return _channel.invokeMapMethod<Object?, Object?>('enqueueDownload', {
      'url': url,
      'fileName': fileName,
    });
  }

  @override
  Future<void> cancel(String platformId) async {
    _checkPlatform();
    await _channel.invokeMethod<void>('cancelDownload', {'id': platformId});
  }

  @override
  Future<void> open(String platformId) async {
    _checkPlatform();
    await _channel.invokeMethod<void>('openDownload', {'id': platformId});
  }

  @override
  Future<Map<Object?, Object?>?> retry({
    required String url,
    required String fileName,
  }) =>
      enqueue(url: url, fileName: fileName);

  @override
  Future<Map<Object?, Object?>?> status(String platformId) async {
    _checkPlatform();
    return _channel.invokeMapMethod<Object?, Object?>('downloadStatus', {
      'id': platformId,
    });
  }
}

/// Coordinates durable task records with Android's system download manager.
class DownloadController extends ChangeNotifier {
  DownloadController(
      {required DownloadTaskStore store, DownloadPlatform? platform})
      : _store = store,
        _platform = platform ?? const MethodChannelDownloadPlatform();

  final DownloadTaskStore _store;
  final DownloadPlatform _platform;
  List<DownloadTask> _tasks = const [];
  bool loading = false;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  Future<void> load() async {
    loading = true;
    notifyListeners();
    _tasks = await _store.loadTasks();
    await refresh();
    loading = false;
    notifyListeners();
  }

  List<DownloadTask> filtered(String query, DownloadTaskStatus? status) {
    final needle = query.trim().toLowerCase();
    return _tasks.where((task) {
      if (status != null && task.status != status) return false;
      return needle.isEmpty ||
          [
            task.title,
            task.fileName,
            task.url,
            task.targetPath,
            task.error ?? ''
          ].join('\n').toLowerCase().contains(needle);
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> enqueue(String url, {String? fileName}) async {
    final name = fileName?.trim().isNotEmpty == true
        ? fileName!.trim()
        : _fileNameFor(url);
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final now = DateTime.now().toUtc();
    var task = DownloadTask(
      id: id,
      url: url,
      targetPath: '',
      fileName: name,
      title: name,
      status: DownloadTaskStatus.queued,
      createdAt: now,
      updatedAt: now,
    );
    await _upsert(task);
    try {
      final result = await _platform.enqueue(url: url, fileName: name);
      task = _withPlatformResult(task, result,
          fallbackStatus: DownloadTaskStatus.running);
    } catch (error) {
      task = task.copyWith(
          status: DownloadTaskStatus.failed,
          error: '$error',
          failedAt: now,
          updatedAt: DateTime.now().toUtc());
    }
    await _upsert(task);
  }

  Future<void> refresh() async {
    for (final task in List<DownloadTask>.from(_tasks)) {
      final platformId = task.extra['platformId']?.toString();
      if (platformId == null || task.isTerminal) continue;
      try {
        final result = await _platform.status(platformId);
        await _upsert(
            _withPlatformResult(task, result, fallbackStatus: task.status));
      } catch (error) {
        await _upsert(task.copyWith(
          status: DownloadTaskStatus.failed,
          error: '$error',
          failedAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ));
      }
    }
  }

  Future<void> retry(DownloadTask task) async {
    final now = DateTime.now().toUtc();
    try {
      final result =
          await _platform.retry(url: task.url, fileName: task.fileName);
      await _upsert(_withPlatformResult(
        task.copyWith(
            error: null,
            progress: 0,
            downloadedBytes: 0,
            status: DownloadTaskStatus.queued,
            updatedAt: now),
        result,
        fallbackStatus: DownloadTaskStatus.running,
      ));
    } catch (error) {
      await _upsert(task.copyWith(
          status: DownloadTaskStatus.failed,
          error: '$error',
          failedAt: now,
          updatedAt: now));
    }
  }

  Future<void> cancel(DownloadTask task) async {
    final now = DateTime.now().toUtc();
    try {
      final id = task.extra['platformId']?.toString();
      if (id != null) await _platform.cancel(id);
      await _upsert(task.copyWith(
          status: DownloadTaskStatus.cancelled,
          cancelledAt: now,
          updatedAt: now));
    } catch (error) {
      await _upsert(task.copyWith(
          status: DownloadTaskStatus.failed,
          error: '$error',
          failedAt: now,
          updatedAt: now));
    }
  }

  Future<String?> open(DownloadTask task) async {
    try {
      final id = task.extra['platformId']?.toString();
      if (id == null) throw StateError('下载任务没有系统文件标识');
      await _platform.open(id);
      return null;
    } catch (error) {
      return '$error';
    }
  }

  Future<void> delete(DownloadTask task) async {
    await _store.delete(task.id);
    _tasks = _tasks.where((item) => item.id != task.id).toList();
    notifyListeners();
  }

  DownloadTask _withPlatformResult(
      DownloadTask task, Map<Object?, Object?>? result,
      {required DownloadTaskStatus fallbackStatus}) {
    final map = result ?? const <Object?, Object?>{};
    final status = _status(map['status']?.toString()) ?? fallbackStatus;
    final downloaded = _int(map['downloadedBytes']) ?? task.downloadedBytes;
    final total = _int(map['totalBytes']) ?? task.totalBytes;
    final progress =
        total != null && total > 0 ? downloaded / total : task.progress;
    final extra = {
      ...task.extra,
      if (map['id'] != null) 'platformId': '${map['id']}'
    };
    final now = DateTime.now().toUtc();
    return task.copyWith(
      status: status,
      downloadedBytes: downloaded,
      totalBytes: total,
      progress: progress.clamp(0, 1).toDouble(),
      targetPath: map['localPath']?.toString() ?? task.targetPath,
      error: map['error']?.toString(),
      extra: extra,
      updatedAt: now,
      completedAt:
          status == DownloadTaskStatus.completed ? now : task.completedAt,
      failedAt: status == DownloadTaskStatus.failed ? now : task.failedAt,
    );
  }

  Future<void> _upsert(DownloadTask task) async {
    await _store.upsert(task);
    final index = _tasks.indexWhere((item) => item.id == task.id);
    if (index == -1) {
      _tasks = [..._tasks, task];
    } else {
      _tasks = [..._tasks]..[index] = task;
    }
    notifyListeners();
  }

  static int? _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value');
  static DownloadTaskStatus? _status(String? value) {
    for (final status in DownloadTaskStatus.values) {
      if (status.name == value) return status;
    }
    return null;
  }

  static String _fileNameFor(String url) {
    final name = Uri.tryParse(url)
        ?.pathSegments
        .where((part) => part.isNotEmpty)
        .lastOrNull;
    return name == null || name.isEmpty ? 'download' : name;
  }
}
