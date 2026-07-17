import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/services/webdav/webdav_audio_quality_probe.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() => server.close(force: true));

  test('probes only a small authenticated byte range from WebDAV', () async {
    final header = _flacHeader();
    final account = WebDavAccount(
      id: 'quality-account',
      name: 'Quality server',
      url: 'http://${server.address.host}:${server.port}/',
      rootPath: 'Music',
      username: 'listener',
      password: 'secret',
    );
    final entry = WebDavEntry(
      uri: account.rootUri.resolve('track.flac'),
      displayName: 'track.flac',
      isDirectory: false,
      contentLength: 100000000,
      lastModified: DateTime.utc(2026, 7, 17),
    );
    var requests = 0;
    server.listen((request) async {
      requests++;
      expect(request.method, 'GET');
      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=0-131071');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Basic ${base64Encode(utf8.encode('listener:secret'))}',
      );
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-${header.length - 1}/100000000',
        )
        ..add(header);
      await request.response.close();
    });

    final probe = WebDavAudioQualityProbe(account);
    addTearDown(probe.close);
    final quality = await probe.probe(entry);

    expect(requests, 1);
    expect(quality, isNotNull);
    expect(quality!.bitDepth, 24);
    expect(quality.sampleRate, 96000);
  });
}

Uint8List _flacHeader() {
  const sampleRate = 96000;
  const bitDepth = 24;
  const channels = 2;
  const totalSamples = sampleRate * 180;
  final bytes = Uint8List(42);
  bytes.setRange(0, 4, 'fLaC'.codeUnits);
  bytes[4] = 0x80;
  bytes[7] = 34;
  final packed = (sampleRate << 44) |
      ((channels - 1) << 41) |
      ((bitDepth - 1) << 36) |
      totalSamples;
  for (var index = 0; index < 8; index++) {
    bytes[18 + index] = (packed >> ((7 - index) * 8)) & 0xff;
  }
  return bytes;
}
