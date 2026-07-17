import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/services/webdav/webdav_client.dart';

void main() {
  late HttpServer server;
  late WebDavAccount account;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    account = WebDavAccount(
      id: 'test-account',
      name: 'Test server',
      url: 'http://${server.address.host}:${server.port}/dav/Music/',
      username: 'user',
      password: 'p@ss',
    );
  });

  tearDown(() => server.close(force: true));

  test('sends Basic authorization and the requested Depth header', () async {
    final requestReceived = Completer<void>();

    server.listen((request) async {
      expect(request.method, 'PROPFIND');
      expect(request.headers.value('depth'), '0');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Basic ${base64Encode(utf8.encode('user:p@ss'))}',
      );
      expect(await utf8.decoder.bind(request).join(), contains('<d:propfind'));
      await _sendMultiStatus(request, _emptyDirectoryResponse);
      requestReceived.complete();
    });

    final client = WebDavClient(account);
    addTearDown(client.close);

    await client.testConnection();
    await requestReceived.future;
  });

  test('parses a 207 listing, removes its root, and sorts folders first',
      () async {
    server.listen((request) async {
      expect(request.headers.value('depth'), '1');
      await _sendMultiStatus(request, _directoryListingResponse);
    });

    final client = WebDavClient(account);
    addTearDown(client.close);

    final entries = await client.list();

    expect(entries, hasLength(4));
    expect(entries.first.isDirectory, isTrue);
    expect(entries.first.displayName, '中文');
    expect(
      entries.skip(1).map((entry) => entry.displayName),
      ['cover.jpg', 'Zeta.mp3', '周杰伦 - 晴天.flac'],
    );
    expect(entries.last.uri.pathSegments.last, '周杰伦 - 晴天.flac');
    expect(entries.last.contentLength, 12345);
    expect(entries.last.contentType, 'audio/flac');
    expect(
      entries.map((entry) => entry.uri.host),
      isNot(contains('untrusted.example')),
    );
  });

  test('reports authentication failures with the status code', () async {
    server.listen((request) async {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
    });

    final client = WebDavClient(account);
    addTearDown(client.close);

    await expectLater(
      client.testConnection(),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.statusCode,
          'statusCode',
          HttpStatus.unauthorized,
        ),
      ),
    );
  });

  test('discovers the AList WebDAV endpoint when server root returns 405',
      () async {
    final rootAccount = account.copyWith(
      url: 'http://${server.address.host}:${server.port}/',
    );
    var requestCount = 0;

    server.listen((request) async {
      requestCount++;
      if (request.uri.path == '/') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      expect(request.uri.path, '/dav/');
      expect(request.headers.value('depth'), '0');
      await _sendMultiStatus(
        request,
        _emptyDirectoryResponse.replaceAll('/dav/Music/', '/dav/'),
      );
    });

    final client = WebDavClient(rootAccount);
    addTearDown(client.close);

    final connectedRoot = await client.testConnection();

    expect(connectedRoot.path, '/dav/');
    expect(requestCount, 2);
  });

  test('checks the selected folder after discovering the AList endpoint',
      () async {
    final rootAccount = account.copyWith(
      url: 'http://${server.address.host}:${server.port}/',
      rootPath: '/Music/无损 音乐/',
    );
    final requestedPaths = <List<String>>[];

    server.listen((request) async {
      requestedPaths.add(request.uri.pathSegments);
      if (request.uri.path == '/') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      expect(request.headers.value('depth'), '0');
      await _sendMultiStatus(
        request,
        _emptyDirectoryResponse.replaceAll(
          '/dav/Music/',
          request.uri.path,
        ),
      );
    });

    final client = WebDavClient(rootAccount);
    addTearDown(client.close);

    final connectedEndpoint = await client.testConnection();

    expect(connectedEndpoint.path, '/dav/');
    expect(requestedPaths, [
      <String>[],
      <String>['dav', ''],
      <String>['dav', 'Music', '无损 音乐', ''],
    ]);
  });

  test('recursively scans supported audio files below the library root',
      () async {
    server.listen((request) async {
      expect(request.headers.value('depth'), '1');
      switch (request.uri.path) {
        case '/dav/Music/':
          await _sendMultiStatus(request, _recursiveRootResponse);
        case '/dav/Music/Album/':
          await _sendMultiStatus(request, _recursiveAlbumResponse);
        default:
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
      }
    });

    final client = WebDavClient(account);
    addTearDown(client.close);

    final entries = await client.scanRecursively();

    expect(entries.map((entry) => entry.displayName), [
      'Song.flac',
      'Root.mp3',
    ]);
    expect(entries.every((entry) => entry.isSupportedAudio), isTrue);
  });
}

Future<void> _sendMultiStatus(HttpRequest request, String body) async {
  request.response
    ..statusCode = 207
    ..headers.contentType = ContentType('application', 'xml', charset: 'utf-8')
    ..write(body);
  await request.response.close();
}

const _emptyDirectoryResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Music/</d:href>
    <d:propstat>
      <d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _directoryListingResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Music/</d:href>
    <d:propstat>
      <d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/Zeta.mp3</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Zeta.mp3</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>audio/mpeg</d:getcontenttype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/%E4%B8%AD%E6%96%87/</d:href>
    <d:propstat>
      <d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/cover.jpg</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>cover.jpg</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>image/jpeg</d:getcontenttype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/%E5%91%A8%E6%9D%B0%E4%BC%A6%20-%20%E6%99%B4%E5%A4%A9.flac</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype />
        <d:getcontentlength>12345</d:getcontentlength>
        <d:getcontenttype>audio/flac</d:getcontenttype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>https://untrusted.example/stolen.mp3</d:href>
    <d:propstat>
      <d:prop><d:getcontenttype>audio/mpeg</d:getcontenttype></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _recursiveRootResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Music/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/Album/</d:href>
    <d:propstat><d:prop><d:displayname>Album</d:displayname><d:resourcetype><d:collection /></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/Root.mp3</d:href>
    <d:propstat><d:prop><d:displayname>Root.mp3</d:displayname><d:resourcetype /><d:getcontenttype>audio/mpeg</d:getcontenttype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>''';

const _recursiveAlbumResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Music/Album/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/Album/Song.flac</d:href>
    <d:propstat><d:prop><d:displayname>Song.flac</d:displayname><d:resourcetype /><d:getcontenttype>audio/flac</d:getcontenttype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/Album/cover.jpg</d:href>
    <d:propstat><d:prop><d:displayname>cover.jpg</d:displayname><d:resourcetype /><d:getcontenttype>image/jpeg</d:getcontenttype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>''';
