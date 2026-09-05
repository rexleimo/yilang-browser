import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// The type of image requested from the host platform.
enum ScreenshotType { visible, long }

class ScreenshotOptions {
  const ScreenshotOptions({
    this.maxWidth,
    this.maxHeight = 12000,
    this.savePath,
    this.sourceUrl,
  });

  final int? maxWidth;
  final int? maxHeight;
  final String? savePath;

  /// 发起截图的页面 URL：原生侧在多个 WebView 实例里据此挑出目标。
  final String? sourceUrl;

  Map<String, Object?> toArguments() => <String, Object?>{
        if (maxWidth != null) 'maxWidth': maxWidth,
        if (maxHeight != null) 'maxHeight': maxHeight,
        if (savePath != null) 'savePath': savePath,
        if (sourceUrl != null) 'url': sourceUrl,
      };
}

class ScreenshotResult {
  const ScreenshotResult({
    required this.bytes,
    this.path,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final String? path;
  final int? width;
  final int? height;

  bool get hasSavedFile => path != null && path!.isNotEmpty;
}

enum ScreenshotErrorCode {
  unsupported,
  permissionDenied,
  invalidRequest,
  captureFailed,
  saveFailed,
  unknown,
}

class ScreenshotException implements Exception {
  const ScreenshotException(this.code, this.message, {this.details});

  final ScreenshotErrorCode code;
  final String message;
  final Object? details;

  @override
  String toString() => 'ScreenshotException($code): $message';
}

abstract interface class ScreenshotService {
  Future<ScreenshotResult> captureVisible({ScreenshotOptions options});
  Future<ScreenshotResult> captureLong({ScreenshotOptions options});
}

/// MethodChannel implementation shared by Android, iOS and desktop hosts.
///
/// The host returns a map containing `bytes` (base64 or Uint8List), and may
/// additionally return `path`, `width`, and `height`.
class MethodChannelScreenshotService implements ScreenshotService {
  MethodChannelScreenshotService({MethodChannel? channel})
      : channel = channel ??
            const MethodChannel('com.yilan.yilan_browser/screenshot');

  final MethodChannel channel;

  @override
  Future<ScreenshotResult> captureVisible({
    ScreenshotOptions options = const ScreenshotOptions(),
  }) =>
      _capture(ScreenshotType.visible, options);

  @override
  Future<ScreenshotResult> captureLong({
    ScreenshotOptions options = const ScreenshotOptions(),
  }) =>
      _capture(ScreenshotType.long, options);

  Future<ScreenshotResult> _capture(
    ScreenshotType type,
    ScreenshotOptions options,
  ) async {
    if ((options.maxWidth != null && options.maxWidth! <= 0) ||
        (options.maxHeight != null && options.maxHeight! <= 0)) {
      throw const ScreenshotException(
        ScreenshotErrorCode.invalidRequest,
        'Maximum screenshot dimensions must be positive',
      );
    }

    final method =
        type == ScreenshotType.visible ? 'captureVisible' : 'captureLong';
    try {
      final raw = await channel.invokeMethod<Object?>(
        method,
        options.toArguments(),
      );
      return _decodeResult(raw);
    } on MissingPluginException catch (error) {
      throw ScreenshotException(
        ScreenshotErrorCode.unsupported,
        'Screenshot is not supported on this platform',
        details: error,
      );
    } on PlatformException catch (error) {
      throw ScreenshotException(
        _mapError(error.code),
        error.message ?? 'Screenshot failed',
        details: error.details,
      );
    } on ScreenshotException {
      rethrow;
    } catch (error) {
      throw ScreenshotException(
        ScreenshotErrorCode.captureFailed,
        'Screenshot failed',
        details: error,
      );
    }
  }

  ScreenshotResult _decodeResult(Object? raw) {
    if (raw is Uint8List) return ScreenshotResult(bytes: raw);
    if (raw is List<int>) {
      return ScreenshotResult(bytes: Uint8List.fromList(raw));
    }
    if (raw is! Map) {
      throw const ScreenshotException(
        ScreenshotErrorCode.captureFailed,
        'Host returned an invalid screenshot response',
      );
    }
    final value = raw['bytes'];
    final Uint8List bytes;
    if (value is Uint8List) {
      bytes = value;
    } else if (value is List) {
      bytes = Uint8List.fromList(value.cast<int>());
    } else if (value is String) {
      try {
        bytes = base64Decode(value);
      } on FormatException catch (error) {
        throw ScreenshotException(
          ScreenshotErrorCode.captureFailed,
          'Host returned invalid image data',
          details: error,
        );
      }
    } else {
      throw const ScreenshotException(
        ScreenshotErrorCode.captureFailed,
        'Host returned no image data',
      );
    }
    return ScreenshotResult(
      bytes: bytes,
      path: raw['path'] as String?,
      width: (raw['width'] as num?)?.toInt(),
      height: (raw['height'] as num?)?.toInt(),
    );
  }

  ScreenshotErrorCode _mapError(String code) {
    switch (code) {
      case 'unsupported':
      case 'not_implemented':
        return ScreenshotErrorCode.unsupported;
      case 'permission_denied':
        return ScreenshotErrorCode.permissionDenied;
      case 'invalid_request':
        return ScreenshotErrorCode.invalidRequest;
      case 'save_failed':
        return ScreenshotErrorCode.saveFailed;
      case 'capture_failed':
        return ScreenshotErrorCode.captureFailed;
      default:
        return ScreenshotErrorCode.unknown;
    }
  }
}

/// Tries the native implementation first and uses [fallback] on unsupported
/// platforms. Other failures are preserved so real errors are not hidden.
class FallbackScreenshotService implements ScreenshotService {
  const FallbackScreenshotService(this.primary, this.fallback);

  final ScreenshotService primary;
  final ScreenshotService fallback;

  @override
  Future<ScreenshotResult> captureVisible({
    ScreenshotOptions options = const ScreenshotOptions(),
  }) =>
      _withFallback(
        () => primary.captureVisible(options: options),
        () => fallback.captureVisible(options: options),
      );

  @override
  Future<ScreenshotResult> captureLong({
    ScreenshotOptions options = const ScreenshotOptions(),
  }) =>
      _withFallback(
        () => primary.captureLong(options: options),
        () => fallback.captureLong(options: options),
      );

  Future<ScreenshotResult> _withFallback(
    Future<ScreenshotResult> Function() operation,
    Future<ScreenshotResult> Function() fallbackOperation,
  ) async {
    try {
      return await operation();
    } on ScreenshotException catch (error) {
      if (error.code != ScreenshotErrorCode.unsupported) rethrow;
      return fallbackOperation();
    }
  }
}

/// Writes a channel result to the requested path when the host did not do so.
Future<ScreenshotResult> saveScreenshotResult(
  ScreenshotResult result,
  String path,
) async {
  try {
    await File(path).writeAsBytes(result.bytes);
    return ScreenshotResult(
      bytes: result.bytes,
      path: path,
      width: result.width,
      height: result.height,
    );
  } on FileSystemException catch (error) {
    throw ScreenshotException(
      ScreenshotErrorCode.saveFailed,
      'Unable to save screenshot',
      details: error,
    );
  }
}
