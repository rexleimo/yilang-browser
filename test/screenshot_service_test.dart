import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/features/browser/browser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelScreenshotService', () {
    const name = 'test.screenshot';
    late MethodChannel channel;
    late List<MethodCall> calls;

    setUp(() {
      channel = const MethodChannel(name);
      calls = <MethodCall>[];
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('sends visible capture options and decodes base64 response', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return <String, Object?>{
          'bytes': 'aGVsbG8=',
          'path': '/tmp/visible.png',
          'width': 10,
          'height': 20,
        };
      });

      final result =
          await MethodChannelScreenshotService(channel: channel).captureVisible(
        options: const ScreenshotOptions(
          maxWidth: 800,
          maxHeight: 1200,
          savePath: '/tmp/visible.png',
        ),
      );

      expect(calls.single.method, 'captureVisible');
      expect(calls.single.arguments, <String, Object?>{
        'maxWidth': 800,
        'maxHeight': 1200,
        'savePath': '/tmp/visible.png',
      });
      expect(result.bytes, Uint8List.fromList(<int>[104, 101, 108, 108, 111]));
      expect(result.path, '/tmp/visible.png');
      expect(result.width, 10);
      expect(result.height, 20);
    });

    test('uses long method and accepts raw bytes', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return Uint8List.fromList(<int>[1, 2, 3]);
      });

      final result =
          await MethodChannelScreenshotService(channel: channel).captureLong(
        options: const ScreenshotOptions(maxHeight: 4000),
      );

      expect(calls.single.method, 'captureLong');
      expect(calls.single.arguments, <String, Object?>{'maxHeight': 4000});
      expect(result.bytes, Uint8List.fromList(<int>[1, 2, 3]));
    });

    test('maps platform errors', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'permission_denied', message: 'no');
      });

      expect(
        () => MethodChannelScreenshotService(channel: channel).captureVisible(),
        throwsA(isA<ScreenshotException>().having(
          (error) => error.code,
          'code',
          ScreenshotErrorCode.permissionDenied,
        )),
      );
    });

    test('maps missing plugin to unsupported', () async {
      expect(
        () => MethodChannelScreenshotService(channel: channel).captureLong(),
        throwsA(isA<ScreenshotException>().having(
          (error) => error.code,
          'code',
          ScreenshotErrorCode.unsupported,
        )),
      );
    });

    test('falls back only when native service is unsupported', () async {
      final fallback = _FakeService();
      final service = FallbackScreenshotService(
        _FailingService(ScreenshotErrorCode.unsupported),
        fallback,
      );

      final result = await service.captureLong();

      expect(result.bytes, Uint8List.fromList(<int>[9]));
      expect(fallback.longCalls, 1);
    });
  });
}

class _FakeService implements ScreenshotService {
  int longCalls = 0;

  @override
  Future<ScreenshotResult> captureVisible(
          {ScreenshotOptions options = const ScreenshotOptions()}) async =>
      ScreenshotResult(bytes: Uint8List(0));

  @override
  Future<ScreenshotResult> captureLong(
      {ScreenshotOptions options = const ScreenshotOptions()}) async {
    longCalls++;
    return ScreenshotResult(bytes: Uint8List.fromList(<int>[9]));
  }
}

class _FailingService implements ScreenshotService {
  _FailingService(this.code);
  final ScreenshotErrorCode code;

  @override
  Future<ScreenshotResult> captureVisible(
          {ScreenshotOptions options = const ScreenshotOptions()}) =>
      Future.error(ScreenshotException(code, 'unsupported'));

  @override
  Future<ScreenshotResult> captureLong(
          {ScreenshotOptions options = const ScreenshotOptions()}) =>
      Future.error(ScreenshotException(code, 'unsupported'));
}
