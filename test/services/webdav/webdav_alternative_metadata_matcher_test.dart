import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/webdav/webdav_alternative_metadata_matcher.dart';

void main() {
  late HttpServer server;
  late Directory cacheDirectory;
  late Uri baseUri;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    cacheDirectory = await Directory.systemTemp.createTemp('spotube-itunes-');
    baseUri = Uri.parse('http://${server.address.host}:${server.port}/');
  });

  tearDown(() async {
    await server.close(force: true);
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  });

  test('matches an unmatched track with the alternate iTunes catalog',
      () async {
    var searchRequests = 0;
    var coverRequests = 0;
    server.listen((request) async {
      if (request.uri.path == '/search') {
        searchRequests++;
        expect(request.uri.queryParameters['country'], 'CN');
        expect(request.uri.queryParameters['entity'], 'song');
        expect(request.uri.queryParameters['term'], contains('周杰伦'));
        // Apple's live endpoint uses text/javascript even though the body is
        // JSON. Keep the regression test aligned with that response.
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/javascript; charset=utf-8',
        );
        request.response.write(jsonEncode({
          'resultCount': 2,
          'results': [
            {
              'trackId': 1,
              'collectionId': 2,
              'artistId': 3,
              'trackName': '我落泪情绪零碎',
              'artistName': '肖启伦',
              'collectionName': '太多',
              'trackTimeMillis': 199652,
            },
            {
              'trackId': 536248201.0,
              'collectionId': 536247746.0,
              'artistId': 300117743.0,
              'trackName': '我落泪 . 情绪零碎',
              'artistName': '周杰伦',
              'collectionName': '跨时代',
              'trackTimeMillis': 258147.0,
              'releaseDate': '2010-05-18T07:00:00Z',
              'artistViewUrl': 'https://music.apple.com/cn/artist/300117743',
              'collectionViewUrl': 'https://music.apple.com/cn/album/536247746',
              'artworkUrl100': '${baseUri}artwork/100x100bb.jpg',
            },
          ],
        }));
      } else if (request.uri.path == '/artwork/600x600bb.jpg') {
        coverRequests++;
        request.response
          ..headers.contentType = ContentType('image', 'jpeg')
          ..add([0xff, 0xd8, 0xff, 0xd9]);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final matcher = WebDavAlternativeMetadataMatcher(
      dio: Dio(),
      searchBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
    );
    addTearDown(matcher.close);

    final result = await matcher.match(_sourceTrack());

    expect(result, isNotNull);
    expect(result!.track.name, '我落泪情绪零碎');
    expect(result.track.artists.single.name, '周杰伦');
    expect(result.track.artists.single.id, 'itunes:artist:300117743');
    expect(result.track.album.name, '跨时代');
    expect(result.track.album.id, 'itunes:536247746');
    expect(result.track.durationMs, 258147);
    expect(result.track.album.releaseDate, '2010-05-18');
    expect(await File(result.track.album.images.single.url).exists(), isTrue);
    expect(searchRequests, 1);
    expect(coverRequests, 1);
  });

  test('matches featured artists even when aliases use different spelling',
      () async {
    server.listen((request) async {
      if (request.uri.path == '/search') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'resultCount': 1,
          'results': [
            {
              'trackId': 1162250314,
              'collectionId': 1162249965,
              'artistId': 300117743,
              'trackName': '不该 (with 张惠妹)',
              'artistName': '周杰伦',
              'collectionName': '周杰伦的床边故事',
              'trackTimeMillis': 290000,
            },
          ],
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final matcher = WebDavAlternativeMetadataMatcher(
      dio: Dio(),
      searchBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
    );
    addTearDown(matcher.close);

    final result = await matcher.match(
      _sourceTrack().copyWith(name: '不该 (with aMEI)'),
    );

    expect(result, isNotNull);
    expect(result!.track.name, '不该 (with 张惠妹)');
    expect(result.track.album.name, '周杰伦的床边故事');
  });

  test('matches romanized titles when folder artist uses Chinese spelling',
      () async {
    server.listen((request) async {
      if (request.uri.path == '/search') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'resultCount': 1,
          'results': [
            {
              'trackId': 14446378,
              'collectionId': 14446370,
              'artistId': 150015,
              'trackName': 'Wei Yi',
              'artistName': 'Leehom Wang',
              'collectionName': 'The One and Only',
              'trackTimeMillis': 261000,
            },
          ],
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final matcher = WebDavAlternativeMetadataMatcher(
      dio: Dio(),
      searchBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
    );
    addTearDown(matcher.close);
    final wang = SpotubeSimpleArtistObject(
      id: 'webdav:artist:王力宏',
      name: '王力宏',
      externalUri: '',
    );
    final source = _sourceTrack().copyWith(
      name: 'Wei Yi',
      artists: [wang],
      album: _sourceTrack().album.copyWith(artists: [wang]),
    );

    final result = await matcher.match(source);

    expect(result, isNotNull);
    expect(result!.track.name, 'Wei Yi');
    expect(result.track.artists.single.name, 'Leehom Wang');
    expect(result.track.album.name, 'The One and Only');
  });
}

SpotubeLocalTrackObject _sourceTrack() {
  final artist = SpotubeSimpleArtistObject(
    id: 'webdav:artist:周杰伦',
    name: '周杰伦',
    externalUri: '',
  );
  return SpotubeLocalTrackObject(
    id: 'webdav:track-1',
    name: '我落泪情绪零碎',
    externalUri: 'https://dav.example/Music/我落泪情绪零碎.wav',
    artists: [artist],
    album: SpotubeSimpleAlbumObject(
      id: 'webdav:album-1',
      name: 'Unknown Album',
      externalUri: '',
      artists: [artist],
      albumType: SpotubeAlbumType.album,
      releaseDate: '1970-01-01',
    ),
    durationMs: 0,
    path: 'https://dav.example/Music/我落泪情绪零碎.wav',
    webDavAccountId: 'account-1',
  );
}
