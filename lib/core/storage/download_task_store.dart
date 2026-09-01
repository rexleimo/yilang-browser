import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_task.dart';

/// Persistence contract for download task snapshots.
abstract class DownloadTaskStore {
  Future<List<DownloadTask>> loadTasks();
  Future<DownloadTask?> findById(String id);
  Future<void> saveTasks(List<DownloadTask> tasks);
  Future<void> upsert(DownloadTask task);
  Future<bool> delete(String id);
  Future<int> cleanup({DateTime? before, Set<DownloadTaskStatus>? statuses});
  Future<void> clear();
  Future<List<DownloadTask>> search(String query);
  Future<List<DownloadTask>> loadRecoverableTasks();
  Future<bool> clearRecoveryMetadata(String id);
}

/// JSON-backed local implementation. UI and download transports are independent
/// from this store and can persist a snapshot after every progress update.
class SharedPrefsDownloadTaskStore implements DownloadTaskStore {
  SharedPrefsDownloadTaskStore(this._prefs);

  static const int storageVersion = 1;
  static const String storageKey = 'yilan_download_tasks_v1';
  static const String versionKey = 'yilan_download_tasks_version';

  final SharedPreferences _prefs;

  static Future<SharedPrefsDownloadTaskStore> create() async =>
      SharedPrefsDownloadTaskStore(await SharedPreferences.getInstance());

  @override
  Future<List<DownloadTask>> loadTasks() async {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      final items = decoded is Map ? decoded['items'] : decoded;
      if (items is! List) return const [];
      final tasks = <DownloadTask>[];
      for (final item in items.whereType<Map>()) {
        try {
          final task = DownloadTask.fromJson(item.cast<String, Object?>());
          if (task.id.trim().isNotEmpty) tasks.add(task);
        } catch (_) {
          // Ignore one damaged record while retaining the rest of the queue.
        }
      }
      final seen = <String>{};
      return [
        for (final task in tasks)
          if (seen.add(task.id)) task
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<DownloadTask?> findById(String id) async {
    final normalized = id.trim();
    for (final task in await loadTasks()) {
      if (task.id == normalized) return task;
    }
    return null;
  }

  @override
  Future<void> saveTasks(List<DownloadTask> tasks) async {
    final unique = <String, DownloadTask>{};
    for (final task in tasks) {
      if (task.id.trim().isNotEmpty) unique[task.id] = task;
    }
    await _prefs.setString(
      storageKey,
      jsonEncode(unique.values.map((task) => task.toJson()).toList()),
    );
    await _prefs.setInt(versionKey, storageVersion);
  }

  @override
  Future<void> upsert(DownloadTask task) async {
    final tasks = (await loadTasks()).toList();
    final index = tasks.indexWhere((item) => item.id == task.id);
    if (index == -1) {
      tasks.add(task);
    } else {
      tasks[index] = task;
    }
    await saveTasks(tasks);
  }

  @override
  Future<bool> delete(String id) async {
    final tasks = await loadTasks();
    final remaining = tasks.where((task) => task.id != id).toList();
    if (remaining.length == tasks.length) return false;
    await saveTasks(remaining);
    return true;
  }

  @override
  Future<int> cleanup(
      {DateTime? before, Set<DownloadTaskStatus>? statuses}) async {
    final tasks = await loadTasks();
    final removableStatuses = statuses ??
        const {
          DownloadTaskStatus.completed,
          DownloadTaskStatus.failed,
          DownloadTaskStatus.cancelled,
        };
    final remaining = tasks.where((task) {
      if (!removableStatuses.contains(task.status)) return true;
      return before != null && !task.updatedAt.isBefore(before);
    }).toList();
    final removed = tasks.length - remaining.length;
    if (removed > 0) await saveTasks(remaining);
    return removed;
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(storageKey);
    await _prefs.remove(versionKey);
  }

  @override
  Future<List<DownloadTask>> search(String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return loadTasks();
    return (await loadTasks()).where((task) {
      final text = [
        task.id,
        task.url,
        task.fileName,
        task.title,
        task.targetPath,
        task.status.value,
        task.error ?? '',
      ].join('\n').toLowerCase();
      return text.contains(needle);
    }).toList();
  }

  @override
  Future<List<DownloadTask>> loadRecoverableTasks() async {
    return (await loadTasks()).where((task) => task.isRecoverable).toList();
  }

  @override
  Future<bool> clearRecoveryMetadata(String id) async {
    final task = await findById(id);
    if (task == null || task.recovery == null) return false;
    await upsert(task.copyWith(recovery: null));
    return true;
  }
}

/// Short alias for callers that do not need to name the backing technology.
typedef LocalDownloadTaskStore = SharedPrefsDownloadTaskStore;
