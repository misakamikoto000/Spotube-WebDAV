import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/services/webdav/webdav_stream_proxy.dart';

void main() {
  late HttpServer server;
  late WebDavAccount account;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    account = WebDavAccount(
      id: 'account-1',
      name: 'Music server',
      url: 'http://${server.address.host}:${server.port}/dav/',
      rootPath: 'Music',
      username: 'listener',
      password: 'secret',
    );
  });

  tearDown(() => server.close(force: true));

  test('encodes and decodes remote playback URLs', () {
    final remote = Uri.parse(
      'https://dav.example/dav/Music/%E4%B8%AD%E6%96%87%20Song.flac',
    );

    final encoded = WebDavStreamProxy.encodeRemoteUri(remote);

    expect(encoded, isNot(contains('/')));
    expect(WebDavStreamProxy.decodeRemoteUri(encoded), remote);
  });

  test('forwards Basic authentication and byte ranges to WebDAV', () async {
    final requestReceived = Completer<void>();
    server.listen((request) async {
      expect(request.method, 'GET');
      expect(request.uri.path, '/dav/Music/Song.wav');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Basic ${base64Encode(utf8.encode('listener:secret'))}',
      );
      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=10-13');
      expect(
          request.headers.value(HttpHeaders.acceptEncodingHeader), 'identity');

      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 10-13/100')
        ..headers.set(
          'content-disposition',
          'attachment; filename="Song.wav"',
        )
        ..headers.contentType = ContentType('audio', 'wav')
        ..add([10, 11, 12, 13]);
      await request.response.close();
      requestReceived.complete();
    });

    final proxy = WebDavStreamProxy();
    addTearDown(proxy.close);
    final response = await proxy.open(
      account: account,
      remoteUri: account.rootUri.resolve('Song.wav'),
      method: 'GET',
      range: 'bytes=10-13',
    );
    final bytes = await response.body!.expand((chunk) => chunk).toList();

    expect(response.statusCode, HttpStatus.partialContent);
    expect(response.headers['content-range'], ['bytes 10-13/100']);
    expect(response.headers, isNot(contains('content-disposition')));
    expect(bytes, [10, 11, 12, 13]);
    await requestReceived.future;
  });

  test('rejects URLs outside the selected library folder', () async {
    final proxy = WebDavStreamProxy();
    addTearDown(proxy.close);

    await expectLater(
      proxy.open(
        account: account,
        remoteUri: Uri.parse(
          'http://${server.address.host}:${server.port}/dav/Private/Song.wav',
        ),
        method: 'GET',
      ),
      throwsFormatException,
    );
  });

  test('uses the user agent required by Baidu Netdisk signed links', () {
    expect(
      WebDavStreamProxy.userAgentForUri(
        Uri.parse('https://bjbgp01.baidupcs.com/file/music.wav?sign=hidden'),
      ),
      'pan.baidu.com',
    );
    expect(
      WebDavStreamProxy.userAgentForUri(
        Uri.parse('https://d.pcs.baidu.com/file/music.wav?sign=hidden'),
      ),
      'pan.baidu.com',
    );
    expect(
      WebDavStreamProxy.userAgentForUri(
        Uri.parse('https://dav.example/Music/Song.wav'),
      ),
      isNull,
    );
  });

  test('preserves authentication across same-origin AList redirects', () async {
    var requestCount = 0;
    server.listen((request) async {
      requestCount++;
      if (request.uri.path == '/dav/Music/Redirect.wav') {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            '/signed/Song.wav?sign=do-not-normalize',
          );
      } else {
        expect(request.uri.path, '/signed/Song.wav');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Basic ${base64Encode(utf8.encode('listener:secret'))}',
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('audio', 'wav')
          ..add([1, 2, 3]);
      }
      await request.response.close();
    });

    final proxy = WebDavStreamProxy();
    addTearDown(proxy.close);
    final response = await proxy.open(
      account: account,
      remoteUri: account.rootUri.resolve('Redirect.wav'),
      method: 'GET',
    );

    final bytes = await response.body!.expand((chunk) => chunk).toList();
    expect(response.statusCode, HttpStatus.ok);
    expect(bytes, [1, 2, 3]);
    expect(requestCount, 2);
  });
}
