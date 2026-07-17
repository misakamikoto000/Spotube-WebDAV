import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/provider/webdav/webdav_library_provider.dart';
import 'package:spotube/provider/webdav/webdav_audio_quality_provider.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/webdav/webdav_audio_quality_store.dart';
import 'package:spotube/services/webdav/webdav_library_store.dart';
import 'package:spotube/services/webdav/webdav_artist_image_matcher.dart';

void main() {
  late HttpServer server;
  late WebDavAccount account;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
    await WebDavLibraryStore.initialize();
    await WebDavAudioQualityStore.initialize();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    account = WebDavAccount(
      id: 'account-1',
      name: 'Music server',
      url: 'http://${server.address.host}:${server.port}/dav/',
      rootPath: 'Music',
      username: '',
      password: '',
    );
  });

  tearDown(() => server.close(force: true));

  test('a new scan preserves metadata already matched on the device', () async {
    final remoteUri = account.rootUri.resolve(
      '%E5%91%A8%E6%9D%B0%E4%BC%A6-%E4%B8%9C%E9%A3%8E%E7%A0%B4.wav',
    );
    final scanned = WebDavEntry(
      uri: remoteUri,
      displayName: '周杰伦-东风破.wav',
      isDirectory: false,
    ).toTrack(account);
    final matched = scanned.copyWith(
      name: '東風破',
      album: SpotubeSimpleAlbumObject(
        id: 'musicbrainz:release-group-original',
        name: '葉惠美',
        externalUri:
            'https://musicbrainz.org/release-group/release-group-original',
        artists: scanned.artists,
        images: [
          SpotubeImageObject(
            url: r'C:\Spotube\webdav_metadata\covers\cover.jpg',
            width: 250,
            height: 250,
          ),
        ],
        albumType: SpotubeAlbumType.album,
        releaseDate: '2003-07-31',
      ),
    );
    await WebDavLibraryStore.save(account.id, [matched]);

    server.listen((request) async {
      request.response
        ..statusCode = 207
        ..headers.contentType = ContentType('application', 'xml')
        ..add(utf8.encode(_listingResponse(remoteUri, '周杰伦-东风破.wav')));
      await request.response.close();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final tracks =
        await container.read(webDavLibraryProvider.notifier).scan(account);

    expect(tracks, hasLength(1));
    expect(tracks.single.name, '东风破');
    expect(tracks.single.album.name, '叶惠美');
    expect(
      tracks.single.album.id,
      'musicbrainz:release-group-original',
    );
    expect(
      tracks.single.album.images.single.url,
      matched.album.images.single.url,
    );
  });

  test('a new scan repairs stale folder-derived artist metadata', () async {
    final remoteUri = account.rootUri.resolve(
      '2021-08-31%20%E8%8B%8F%E6%A0%BC%E6%8B%89%E6%B2%A1%E6%9C%89%E5%BA%95/01.%E6%83%B3%E8%B1%A1%E4%B9%8B%E4%B8%AD.flac',
    );
    final staleArtist = SpotubeSimpleArtistObject(
      id: 'webdav:${account.id}:artist:2021-08-31 苏格拉没有底',
      name: '2021-08-31 苏格拉没有底',
      externalUri: remoteUri.toString(),
    );
    final stale = SpotubeLocalTrackObject(
      id: 'webdav:${account.id}:$remoteUri',
      name: '想象之中',
      externalUri: remoteUri.toString(),
      artists: [staleArtist],
      album: SpotubeSimpleAlbumObject(
        id: 'webdav:${account.id}:${remoteUri.resolve('.').path}',
        name: webDavUnknownAlbum,
        externalUri: remoteUri.resolve('.').toString(),
        artists: [staleArtist],
        albumType: SpotubeAlbumType.album,
      ),
      durationMs: 0,
      path: remoteUri.toString(),
      webDavAccountId: account.id,
    );
    await WebDavLibraryStore.save(account.id, [stale]);

    server.listen((request) async {
      request.response
        ..statusCode = 207
        ..headers.contentType = ContentType('application', 'xml')
        ..add(utf8.encode(_listingResponse(remoteUri, '01.想象之中.flac')));
      await request.response.close();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final tracks =
        await container.read(webDavLibraryProvider.notifier).scan(account);

    expect(tracks, hasLength(1));
    expect(tracks.single.name, '想象之中');
    expect(tracks.single.artists.single.name, webDavUnknownArtist);
    expect(tracks.single.album.name, '苏格拉没有底');
  });

  test('a scan probes and publishes real WebDAV audio quality', () async {
    final remoteUri = account.rootUri.resolve('HiRes.flac');
    final flac = _flacHeader();
    server.listen((request) async {
      if (request.method == 'PROPFIND') {
        request.response
          ..statusCode = 207
          ..headers.contentType = ContentType('application', 'xml')
          ..add(utf8.encode(_qualityListingResponse(remoteUri)));
      } else if (request.method == 'GET') {
        expect(request.headers.value(HttpHeaders.rangeHeader), isNotNull);
        request.response
          ..statusCode = HttpStatus.partialContent
          ..add(flac);
      } else {
        request.response.statusCode = HttpStatus.methodNotAllowed;
      }
      await request.response.close();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(webDavLibraryProvider.notifier).scan(account);

    final quality =
        container.read(webDavAudioQualityProvider)[remoteUri.toString()];
    expect(quality, isNotNull);
    expect(quality!.bitDepth, 24);
    expect(quality.sampleRate, 96000);
  });

  test('matches artist portraits for every track from the artists page action',
      () async {
    final cacheDirectory =
        await Directory.systemTemp.createTemp('spotube-provider-artist-');
    addTearDown(() async {
      if (await cacheDirectory.exists()) {
        await cacheDirectory.delete(recursive: true);
      }
    });
    var searchRequests = 0;
    var imageRequests = 0;
    server.listen((request) async {
      if (request.uri.path == '/soso/fcgi-bin/client_search_cp') {
        searchRequests++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {
            'song': {
              'list': [
                {
                  'singer': [
                    {'mid': '0025NhlN2yWrP4', 'name': 'Jay Chou'},
                  ],
                },
              ],
            },
          },
        }));
      } else if (request.uri.path == '/T001R500x500M0000025NhlN2yWrP4.jpg') {
        imageRequests++;
        request.response
          ..headers.contentType = ContentType('image', 'jpeg')
          ..add([0xff, 0xd8, 0xff, 0xd9]);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    await WebDavLibraryStore.save(account.id, [
      _artistTrack('track-1'),
      _artistTrack('track-2'),
    ]);
    final matcher = WebDavArtistImageMatcher(
      dio: Dio(),
      searchBaseUri: Uri.parse(
        'http://${server.address.host}:${server.port}/',
      ),
      artworkBaseUri: Uri.parse(
        'http://${server.address.host}:${server.port}/',
      ),
      cacheDirectory: cacheDirectory,
    );
    addTearDown(matcher.close);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final summary = await container
        .read(webDavLibraryProvider.notifier)
        .matchArtistImages(imageMatcher: matcher);
    final tracks = container.read(webDavLibraryProvider)[account.id]!;

    expect(summary.matched, 1);
    expect(summary.unmatched, 0);
    expect(summary.failed, 0);
    expect(
      tracks.every(
        (track) => track.artists.single.images?.isNotEmpty == true,
      ),
      isTrue,
    );
    expect(searchRequests, 1);
    expect(imageRequests, 1);
  });
}

SpotubeLocalTrackObject _artistTrack(String id) {
  final artist = SpotubeSimpleArtistObject(
    id: 'musicbrainz:artist-jay-chou',
    name: 'Jay Chou',
    externalUri: '',
  );
  return SpotubeLocalTrackObject(
    id: id,
    name: 'Song $id',
    externalUri: 'https://dav.example/$id.flac',
    artists: [artist],
    album: SpotubeSimpleAlbumObject(
      id: 'album-1',
      name: 'Album',
      externalUri: '',
      artists: [artist],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 240000,
    path: 'https://dav.example/$id.flac',
    webDavAccountId: 'account-1',
  );
}

String _listingResponse(Uri remoteUri, String displayName) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Music/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>${remoteUri.path}</d:href>
    <d:propstat>
      <d:prop><d:displayname>$displayName</d:displayname><d:resourcetype /><d:getcontenttype>audio/flac</d:getcontenttype></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

String _qualityListingResponse(Uri remoteUri) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Music/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>${remoteUri.path}</d:href>
    <d:propstat>
      <d:prop><d:displayname>HiRes.flac</d:displayname><d:resourcetype /><d:getcontenttype>audio/flac</d:getcontenttype><d:getcontentlength>100000000</d:getcontentlength><d:getlastmodified>Fri, 17 Jul 2026 00:00:00 GMT</d:getlastmodified></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

List<int> _flacHeader() {
  const sampleRate = 96000;
  const bitDepth = 24;
  const channels = 2;
  const totalSamples = sampleRate * 180;
  final bytes = List<int>.filled(42, 0);
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
