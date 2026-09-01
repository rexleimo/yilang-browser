import 'dart:convert';

/// The lifecycle state of a persisted download.
enum DownloadTaskStatus {
  queued,
  running,
  paused,
  completed,
  failed,
  cancelled,
}

extension DownloadTaskStatusValue on DownloadTaskStatus {
  String get value => name;
}

class DownloadTaskStatusCodec {
  static DownloadTaskStatus fromValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return DownloadTaskStatus.values.firstWhere(
      (status) => status.name == normalized,
      orElse: () => DownloadTaskStatus.queued,
    );
  }
}

/// A JSON-safe snapshot used to resume a download after the app restarts.
class DownloadRecoveryMetadata {
  const DownloadRecoveryMetadata({
    this.temporaryPath,
    this.etag,
    this.lastModified,
    this.acceptRanges,
    this.resumeOffset,
    this.requestHeaders = const <String, String>{},
    this.extra = const <String, Object?>{},
  });

  final String? temporaryPath;
  final String? etag;
  final DateTime? lastModified;
  final bool? acceptRanges;
  final int? resumeOffset;
  final Map<String, String> requestHeaders;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
        if (temporaryPath != null) 'temporaryPath': temporaryPath,
        if (etag != null) 'etag': etag,
        if (lastModified != null)
          'lastModified': lastModified!.toIso8601String(),
        if (acceptRanges != null) 'acceptRanges': acceptRanges,
        if (resumeOffset != null) 'resumeOffset': resumeOffset,
        if (requestHeaders.isNotEmpty) 'requestHeaders': requestHeaders,
        if (extra.isNotEmpty) 'extra': extra,
      };

  factory DownloadRecoveryMetadata.fromJson(Map<String, Object?> json) {
    final headers = json['requestHeaders'];
    final extra = json['extra'];
    return DownloadRecoveryMetadata(
      temporaryPath: _nullableString(json['temporaryPath'] ?? json['tempPath']),
      etag: _nullableString(json['etag']),
      lastModified: _date(json['lastModified']),
      acceptRanges:
          json['acceptRanges'] is bool ? json['acceptRanges'] as bool : null,
      resumeOffset: _int(json['resumeOffset'] ?? json['downloadedBytes']),
      requestHeaders: headers is Map
          ? headers
              .map((key, value) => MapEntry(key.toString(), value.toString()))
          : const <String, String>{},
      extra: extra is Map
          ? extra.cast<String, Object?>()
          : const <String, Object?>{},
    );
  }
}

/// Complete durable state for one download request.
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.targetPath,
    this.fileName = '',
    this.title = '',
    this.status = DownloadTaskStatus.queued,
    this.progress = 0,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.error,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.startedAt,
    this.pausedAt,
    this.completedAt,
    this.failedAt,
    this.cancelledAt,
    this.recovery,
    this.mimeType,
    this.checksum,
    this.extra = const <String, Object?>{},
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final String url;
  final String targetPath;
  final String fileName;
  final String title;
  final DownloadTaskStatus status;
  final double progress;
  final int downloadedBytes;
  final int? totalBytes;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? pausedAt;
  final DateTime? completedAt;
  final DateTime? failedAt;
  final DateTime? cancelledAt;
  final DownloadRecoveryMetadata? recovery;
  final String? mimeType;
  final String? checksum;
  final Map<String, Object?> extra;

  bool get isTerminal => const {
        DownloadTaskStatus.completed,
        DownloadTaskStatus.failed,
        DownloadTaskStatus.cancelled,
      }.contains(status);

  bool get isRecoverable =>
      status == DownloadTaskStatus.paused ||
      status == DownloadTaskStatus.running;

  DownloadTask copyWith({
    String? id,
    String? url,
    String? targetPath,
    String? fileName,
    String? title,
    DownloadTaskStatus? status,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    Object? error = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? startedAt = _unset,
    Object? pausedAt = _unset,
    Object? completedAt = _unset,
    Object? failedAt = _unset,
    Object? cancelledAt = _unset,
    Object? recovery = _unset,
    Object? mimeType = _unset,
    Object? checksum = _unset,
    Map<String, Object?>? extra,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      url: url ?? this.url,
      targetPath: targetPath ?? this.targetPath,
      fileName: fileName ?? this.fileName,
      title: title ?? this.title,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      error: identical(error, _unset) ? this.error : error as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startedAt: identical(startedAt, _unset)
          ? this.startedAt
          : startedAt as DateTime?,
      pausedAt:
          identical(pausedAt, _unset) ? this.pausedAt : pausedAt as DateTime?,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
      failedAt:
          identical(failedAt, _unset) ? this.failedAt : failedAt as DateTime?,
      cancelledAt: identical(cancelledAt, _unset)
          ? this.cancelledAt
          : cancelledAt as DateTime?,
      recovery: identical(recovery, _unset)
          ? this.recovery
          : recovery as DownloadRecoveryMetadata?,
      mimeType:
          identical(mimeType, _unset) ? this.mimeType : mimeType as String?,
      checksum:
          identical(checksum, _unset) ? this.checksum : checksum as String?,
      extra: extra ?? this.extra,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'url': url,
        'targetPath': targetPath,
        'fileName': fileName,
        'title': title,
        'status': status.value,
        'progress': progress,
        'downloadedBytes': downloadedBytes,
        if (totalBytes != null) 'totalBytes': totalBytes,
        if (error != null) 'error': error,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (pausedAt != null) 'pausedAt': pausedAt!.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
        if (failedAt != null) 'failedAt': failedAt!.toIso8601String(),
        if (cancelledAt != null) 'cancelledAt': cancelledAt!.toIso8601String(),
        if (recovery != null) 'recovery': recovery!.toJson(),
        if (mimeType != null) 'mimeType': mimeType,
        if (checksum != null) 'checksum': checksum,
        if (extra.isNotEmpty) 'extra': extra,
      };

  factory DownloadTask.fromJson(Map<String, Object?> json) => DownloadTask(
        id: _string(json['id']),
        url: _string(json['url']),
        targetPath: _string(json['targetPath'] ?? json['destinationPath']),
        fileName: _string(json['fileName']),
        title: _string(json['title']),
        status: DownloadTaskStatusCodec.fromValue(json['status']),
        progress: _double(json['progress']),
        downloadedBytes: _int(json['downloadedBytes']) ?? 0,
        totalBytes: _int(json['totalBytes']),
        error: _nullableString(json['error']),
        createdAt: _date(json['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        updatedAt: _date(json['updatedAt'] ?? json['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        startedAt: _date(json['startedAt']),
        pausedAt: _date(json['pausedAt']),
        completedAt: _date(json['completedAt']),
        failedAt: _date(json['failedAt']),
        cancelledAt: _date(json['cancelledAt']),
        recovery: json['recovery'] is Map
            ? DownloadRecoveryMetadata.fromJson(
                (json['recovery'] as Map).cast<String, Object?>())
            : null,
        mimeType: _nullableString(json['mimeType']),
        checksum: _nullableString(json['checksum']),
        extra: json['extra'] is Map
            ? (json['extra'] as Map).cast<String, Object?>()
            : const <String, Object?>{},
      );

  @override
  String toString() => jsonEncode(toJson());
}

const _unset = Object();
String _string(Object? value) => value is String ? value : '';
String? _nullableString(Object? value) => value is String ? value : null;
int? _int(Object? value) => value is int
    ? value
    : value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
double _double(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;
DateTime? _date(Object? value) => value is String
    ? DateTime.tryParse(value)
    : value is num
        ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
        : null;
