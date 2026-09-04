import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/features/browser/browser.dart';

void main() {
  late HttpServer server;
  late Directory temp;
  late Uri origin;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = Uri.parse('http://${server.address.host}:${server.port}');
    temp = await Directory.systemTemp.createTemp('offline_archive_test_');
  });

  tearDown(() async {
    await server.close(force: true);
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('archives same-origin resources and remains readable over HTTP',
      () async {
    final png = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    server.listen((request) {
      final path = request.uri.path;
      if (path == '/') {
        request.response
          ..headers.contentType =
              ContentType('text', 'html', charset: 'iso-8859-1')
          ..add(latin1.encode('''
<!doctype html><html><head>
<meta charset="iso-8859-1">
<link rel="icon" href="/icon.ico">
<link rel="stylesheet" href="styles/site.css">
</head><body>
<h1>Caf\u00e9</h1>
<img src="images/photo.png">
<img src="$origin/images/photo.png">
<img src="/missing.png">
</body></html>
'''));
      } else if (path == '/styles/site.css') {
        request.response
          ..headers.contentType = ContentType('text', 'css')
          ..add(
              utf8.encode('body { background-image: url(../images/bg.png); }'));
      } else if (path == '/images/photo.png' || path == '/images/bg.png') {
        request.response
          ..headers.contentType = ContentType('image', 'png')
          ..add(png);
      } else if (path == '/icon.ico') {
        request.response
          ..headers.contentType = ContentType('image', 'x-icon')
          ..add([0, 1, 2, 3]);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      request.response.close();
    });

    final archive = await OfflineArchiveService().archive(
      origin,
      temp,
    );
    final html = await archive.index.readAsString();
    final manifest = jsonDecode(await archive.manifest.readAsString())
        as Map<String, dynamic>;
    final resources = manifest['resources'] as List<dynamic>;

    expect(html, contains('Caf\u00e9'));
    expect(html, isNot(contains('/images/photo.png')));
    expect(html, contains('/missing.png'));
    expect(html, contains('resources/'));
    expect(await archive.index.exists(), isTrue);
    expect(await archive.manifest.exists(), isTrue);
    expect(
        await File('${archive.directory.path}/${archive.assets.values.first}')
            .exists(),
        isTrue);
    expect(resources, hasLength(5));
    expect(resources.where((item) => (item as Map)['localPath'] == null),
        hasLength(1));
    expect(
        resources.any(
            (item) => (item as Map)['url'].toString().endsWith('/missing.png')),
        isTrue);

    final readableServer =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    readableServer.listen((request) async {
      final relative =
          request.uri.path == '/' ? '/index.html' : request.uri.path;
      final file = File('${archive.directory.path}$relative');
      if (await file.exists()) {
        request.response.add(await file.readAsBytes());
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final client = HttpClient();
    final response = await client
        .getUrl(
          Uri.parse(
              'http://${readableServer.address.host}:${readableServer.port}/'),
        )
        .then((request) => request.close());
    expect(response.statusCode, HttpStatus.ok);
    expect(await utf8.decoder.bind(response).join(), contains('Caf\u00e9'));
    client.close(force: true);
    await readableServer.close(force: true);
  });

  test('cleanup retains the requested number of archives', () async {
    final service = OfflineArchiveService();
    for (var i = 0; i < 3; i++) {
      final directory = Directory('${temp.path}/archive_$i');
      await directory.create();
      await File('${directory.path}/index.html').writeAsString('$i');
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await service.cleanup(temp, keep: 1);
    final remaining = await temp
        .list()
        .where(
            (entity) => entity is Directory && entity.path.contains('archive_'))
        .length;
    expect(remaining, 1);
  });
}
