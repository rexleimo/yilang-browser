import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yilan_browser/core/models/download_task.dart';
import 'package:yilan_browser/core/storage/download_task_store.dart';

DownloadTask task(String id, DownloadTaskStatus status, DateTime updatedAt) =>
    DownloadTask(
      id: id,
      url: 'https://example.test/$id',
      targetPath: '/downloads/$id.bin',
      fileName: '$id.bin',
      title: 'Task $id',
      status: status,
      progress: status == DownloadTaskStatus.completed ? 1 : .25,
      downloadedBytes: 25,
      totalBytes: 100,
      error: status == DownloadTaskStatus.failed ? 'network timeout' : null,
      createdAt: updatedAt.subtract(const Duration(minutes: 2)),
      updatedAt: updatedAt,
      startedAt: updatedAt.subtract(const Duration(minutes: 1)),
      recovery: status == DownloadTaskStatus.paused
          ? const DownloadRecoveryMetadata(
              temporaryPath: '/tmp/a.part',
              etag: 'etag-1',
              resumeOffset: 25,
              acceptRanges: true,
              requestHeaders: {'Authorization': 'token'},
            )
          : null,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round trip preserves all task states and recovery metadata', () {
    final updated = DateTime.utc(2025, 1, 2, 3, 4, 5);
    for (final status in DownloadTaskStatus.values) {
      final original = task(status.name, status, updated);
      final restored = DownloadTask.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.status, status);
      expect(restored.progress, original.progress);
      expect(restored.targetPath, original.targetPath);
      expect(restored.updatedAt, updated);
    }

    final recovery = DownloadTask.fromJson(
      task('paused', DownloadTaskStatus.paused, updated).toJson(),
    ).recovery!;
    expect(recovery.temporaryPath, '/tmp/a.part');
    expect(recovery.resumeOffset, 25);
    expect(recovery.requestHeaders['Authorization'], 'token');
  });

  test('status codec safely handles unknown persisted values', () {
    expect(DownloadTaskStatusCodec.fromValue('RUNNING'),
        DownloadTaskStatus.running);
    expect(DownloadTaskStatusCodec.fromValue('unknown'),
        DownloadTaskStatus.queued);
  });

  group('SharedPrefsDownloadTaskStore', () {
    test('upsert replaces by id and survives a new store instance', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsDownloadTaskStore(prefs);
      final now = DateTime.utc(2025, 2, 1);
      await store.upsert(task('one', DownloadTaskStatus.queued, now));
      await store.upsert(task('one', DownloadTaskStatus.running, now));
      await store.upsert(task('two', DownloadTaskStatus.paused, now));

      final loaded = await SharedPrefsDownloadTaskStore(prefs).loadTasks();
      expect(loaded.map((item) => item.id), ['one', 'two']);
      expect(loaded.first.status, DownloadTaskStatus.running);
      expect(await store.loadRecoverableTasks(), hasLength(2));
    });

    test('search matches id, title, path, URL, state, and error', () async {
      final store = await SharedPrefsDownloadTaskStore.create();
      final now = DateTime.utc(2025, 3, 1);
      await store.saveTasks([
        task('alpha', DownloadTaskStatus.failed, now),
        task('beta', DownloadTaskStatus.completed, now),
      ]);

      expect((await store.search('ALPHA')).single.id, 'alpha');
      expect((await store.search('network')).single.id, 'alpha');
      expect((await store.search('COMPLETED')).single.id, 'beta');
      expect(await store.search(''), hasLength(2));
    });

    test('cleanup removes terminal tasks, optionally bounded by date',
        () async {
      final store = await SharedPrefsDownloadTaskStore.create();
      final old = DateTime.utc(2025, 1, 1);
      final recent = DateTime.utc(2025, 2, 1);
      await store.saveTasks([
        task('done-old', DownloadTaskStatus.completed, old),
        task('failed-recent', DownloadTaskStatus.failed, recent),
        task('paused', DownloadTaskStatus.paused, old),
      ]);

      expect(await store.cleanup(before: DateTime.utc(2025, 1, 15)), 1);
      expect((await store.loadTasks()).map((item) => item.id),
          ['failed-recent', 'paused']);
      expect(await store.cleanup(), 1);
      expect((await store.loadTasks()).map((item) => item.id), ['paused']);
    });

    test('deletes tasks, clears recovery metadata, and clears storage',
        () async {
      final store = await SharedPrefsDownloadTaskStore.create();
      final paused =
          task('paused', DownloadTaskStatus.paused, DateTime.utc(2025));
      await store.upsert(paused);
      expect(await store.clearRecoveryMetadata('paused'), isTrue);
      expect((await store.findById('paused'))!.recovery, isNull);
      expect(await store.delete('missing'), isFalse);
      expect(await store.delete('paused'), isTrue);
      await store.upsert(paused);
      await store.clear();
      expect(await store.loadTasks(), isEmpty);
    });
  });
}
