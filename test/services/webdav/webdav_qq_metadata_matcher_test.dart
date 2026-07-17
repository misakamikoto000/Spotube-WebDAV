import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/webdav/webdav_qq_metadata_matcher.dart';

void main() {
  late HttpServer server;
  late Directory cacheDirectory;
  late Uri baseUri;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    cacheDirectory = await Directory.systemTemp.createTemp('spotube-qq-');
    baseUri = Uri.parse('http://${server.address.host}:${server.port}/');
  });

  tearDown(() async {
    await server.close(force: true);
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  });

  test('matches QQ Music metadata and keeps its cover on the local device',
      () async {
    var searchRequests = 0;
    var coverRequests = 0;
    server.listen((request) async {
      if (request.uri.path == '/soso/fcgi-bin/client_search_cp') {
        searchRequests++;
        expect(request.uri.queryParameters['format'], 'json');
        expect(request.uri.queryParameters['w'], contains('周杰伦'));
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'code': 0,
          'data': {
            'song': {
              'list': [
                {
                  'songmid': 'wrong-song',
                  'songname': '我落泪情绪零碎',
                  'singer': [
                    {'mid': 'wrong-artist', 'name': '肖启伦'},
                  ],
                  'albumname': '太多',
                  'interval': 199,
                },
                {
                  'songmid': '0022b7OX2STU86',
                  'songname': '我落泪情绪零碎',
                  'singer': [
                    {'mid': '0025NhlN2yWrP4', 'name': '周杰伦'},
                  ],
                  'albummid': '000bviBl4FjTpO',
                  'albumname': '跨时代',
                  'interval': 258,
                  'pubtime': 1274131200,
                },
              ],
            },
          },
        }));
      } else if (request.uri.path == '/T002R500x500M000000bviBl4FjTpO.jpg') {
        coverRequests++;
        request.response
          ..headers.contentType = ContentType('image', 'jpeg')
          ..add([0xff, 0xd8, 0xff, 0xd9]);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final matcher = WebDavQqMetadataMatcher(
      dio: Dio(),
      searchBaseUri: baseUri,
      artworkBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
    );
    addTearDown(matcher.close);

    final result = await matcher.match(_sourceTrack());

    expect(result, isNotNull);
    expect(result!.recordingId, 'qq:0022b7OX2STU86');
    expect(result.track.name, '我落泪情绪零碎');
    expect(result.track.artists.single.name, '周杰伦');
    expect(result.track.artists.single.id, 'qq:artist:0025NhlN2yWrP4');
    expect(result.track.album.name, '跨时代');
    expect(result.track.album.id, 'qq:000bviBl4FjTpO');
    expect(result.track.durationMs, 258000);
    expect(result.track.album.releaseDate, '2010-05-18');
    expect(await File(result.track.album.images.single.url).exists(), isTrue);
    expect(searchRequests, 1);
    expect(coverRequests, 1);
  });

  test('prefers the original QQ Music edition over live variants', () async {
    server.listen((request) async {
      if (request.uri.path == '/soso/fcgi-bin/client_search_cp') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'code': 0,
          'data': {
            'song': {
              'list': [
                {
                  'songmid': 'live-song',
                  'songname': '不该 (Live)',
                  'singer': [
                    {'mid': 'jay', 'name': '周杰伦'},
                  ],
                  'interval': 301,
                },
                {
                  'songmid': '000sxzol11raSd',
                  'songname': '不该 (with aMEI)',
                  'singer': [
                    {'mid': 'jay', 'name': '周杰伦'},
                    {'mid': 'amei', 'name': '张惠妹'},
                  ],
                  'albumname': '周杰伦的床边故事',
                  'interval': 291,
                },
              ],
            },
          },
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final matcher = WebDavQqMetadataMatcher(
      dio: Dio(),
      searchBaseUri: baseUri,
      artworkBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
    );
    addTearDown(matcher.close);

    final result = await matcher.match(
      _sourceTrack().copyWith(name: '不该 (with aMEI)'),
    );

    expect(result, isNotNull);
    expect(result!.recordingId, 'qq:000sxzol11raSd');
    expect(result.track.artists.map((artist) => artist.name), ['周杰伦', '张惠妹']);
  });

  test('matches a romanized title only with first-result artist evidence',
      () async {
    String? firstQuery;
    server.listen((request) async {
      if (request.uri.path == '/soso/fcgi-bin/client_search_cp') {
        firstQuery ??= request.uri.queryParameters['w'];
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {
            'song': {
              'list': [
                {
                  'songmid': 'gong-zhuan',
                  'songname': '公转自转',
                  'singer': [
                    {'mid': 'leehom', 'name': '王力宏'},
                  ],
                  'albumname': '公转自转',
                },
              ],
            },
          },
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final matcher = WebDavQqMetadataMatcher(
      dio: Dio(),
      searchBaseUri: baseUri,
      artworkBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
    );
    addTearDown(matcher.close);

    final result = await matcher.match(
      _sourceTrack(
        title: 'Gong Zhuan Zi Zhuan (Album Version)',
        artistName: '王力宏',
        albumName: '王力宏20年精选',
      ),
    );

    expect(firstQuery, '王力宏 Gong Zhuan Zi Zhuan');
    expect(result, isNotNull);
    expect(result!.track.name, '公转自转');
    expect(result.track.artists.single.name, '王力宏');
  });

  test('does not guess a later cross-script result from title length alone',
      () async {
    server.listen((request) async {
      if (request.uri.path == '/soso/fcgi-bin/client_search_cp') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {
            'song': {
              'list': [
                {
                  'songmid': 'wrong-first',
                  'songname': '爱错',
                  'singer': [
                    {'mid': 'leehom', 'name': '王力宏'},
                  ],
                },
                {
                  'songmid': 'wrong-shaped',
                  'songname': '我们的歌',
                  'singer': [
                    {'mid': 'leehom', 'name': '王力宏'},
                  ],
                },
              ],
            },
          },
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final matcher = WebDavQqMetadataMatcher(
      dio: Dio(),
      searchBaseUri: baseUri,
      artworkBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
    );
    addTearDown(matcher.close);

    final result = await matcher.match(
      _sourceTrack(title: 'Luo Ye Gui Gen', artistName: '王力宏'),
    );

    expect(result, isNull);
  });

  test('uses the first result for the expected artist after other artists',
      () async {
    server.listen((request) async {
      if (request.uri.path == '/soso/fcgi-bin/client_search_cp') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {
            'song': {
              'list': [
                {
                  'songmid': 'other-artist',
                  'songname': 'Luò Yè Guī Gēn',
                  'singer': [
                    {'mid': 'other', 'name': '其他歌手'},
                  ],
                },
                {
                  'songmid': 'correct-song',
                  'songname': '落叶归根',
                  'singer': [
                    {'mid': 'leehom', 'name': '王力宏'},
                  ],
                },
              ],
            },
          },
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final matcher = WebDavQqMetadataMatcher(
      dio: Dio(),
      searchBaseUri: baseUri,
      artworkBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
    );
    addTearDown(matcher.close);

    final result = await matcher.match(
      _sourceTrack(title: 'Luo Ye Gui Gen', artistName: '王力宏'),
    );

    expect(result, isNotNull);
    expect(result!.track.name, '落叶归根');
  });

  test('matches a soundtrack cue with a catalog title prefix', () async {
    server.listen((request) async {
      if (request.uri.path == '/soso/fcgi-bin/client_search_cp') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {
            'song': {
              'list': [
                {
                  'songmid': 'soundtrack-cue',
                  'songname': 'Play - 吸引',
                  'singer': [
                    {'mid': 'david-tao', 'name': '陶喆'},
                    {'mid': 'guest', 'name': '杨谨华'},
                  ],
                  'albummid': 'soundtrack-album',
                  'albumname': '暗恋 电影原声带',
                },
              ],
            },
          },
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final matcher = WebDavQqMetadataMatcher(
      dio: Dio(),
      searchBaseUri: baseUri,
      artworkBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
    );
    addTearDown(matcher.close);

    final result = await matcher.match(
      _sourceTrack(
        title: '吸引',
        artistName: '陶喆',
        albumName: '暗恋 电影原声带',
      ),
    );

    expect(result, isNotNull);
    expect(result!.track.name, 'Play - 吸引');
    expect(result.track.album.name, '暗恋 电影原声带');
  });

  test('reconciles a numbered folder from two aligned album anchors', () async {
    server.listen((request) async {
      if (request.uri.path == '/v8/fcg-bin/fcg_v8_album_info_cp.fcg') {
        expect(request.uri.queryParameters['albummid'], 'collection-mid');
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {
            'name': '周年精选',
            'list': [
              {
                'songmid': 'song-1',
                'songname': '第一首',
                'albummid': 'collection-mid',
                'singer': [
                  {'mid': 'leehom', 'name': '王力宏'},
                ],
              },
              {
                'songmid': 'song-2',
                'songname': '第二首',
                'albummid': 'collection-mid',
                'singer': [
                  {'mid': 'leehom', 'name': '王力宏'},
                ],
              },
              {
                'songmid': 'song-3',
                'songname': '第三首',
                'albummid': 'collection-mid',
                'singer': [
                  {'mid': 'leehom', 'name': '王力宏'},
                ],
              },
            ],
          },
        }));
      } else if (request.uri.path == '/T002R500x500M000collection-mid.jpg') {
        request.response
          ..headers.contentType = ContentType('image', 'jpeg')
          ..add([0xff, 0xd8, 0xff, 0xd9]);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final matcher = WebDavQqMetadataMatcher(
      dio: Dio(),
      searchBaseUri: baseUri,
      artworkBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
    );
    addTearDown(matcher.close);
    final first = _sourceTrack(title: '第一首').copyWith(
      path: 'https://dav.example/Music/Album/01.First.flac',
      album: _sourceTrack().album.copyWith(id: 'qq:collection-mid'),
    );
    final second = _sourceTrack(title: '第二首').copyWith(
      path: 'https://dav.example/Music/Album/02.Second.flac',
      album: _sourceTrack().album.copyWith(id: 'qq:collection-mid'),
    );
    final third = _sourceTrack(title: 'Di San Shou').copyWith(
      path: 'https://dav.example/Music/Album/03.Third.flac',
    );

    final reconciled = await matcher.reconcileNumberedAlbum([
      first,
      second,
      third,
    ]);

    expect(reconciled, isNotNull);
    expect(reconciled!.map((track) => track.name), ['第一首', '第二首', '第三首']);
    expect(
      reconciled.map((track) => track.album.id).toSet(),
      {'qq:collection-mid'},
    );
    expect(reconciled.every((track) => track.album.images.isNotEmpty), isTrue);
  });
}

SpotubeLocalTrackObject _sourceTrack({
  String title = '我落泪情绪零碎',
  String artistName = '周杰伦',
  String albumName = 'Unknown Album',
}) {
  final artist = SpotubeSimpleArtistObject(
    id: 'webdav:artist:$artistName',
    name: artistName,
    externalUri: '',
  );
  return SpotubeLocalTrackObject(
    id: 'webdav:track-1',
    name: title,
    externalUri: 'https://dav.example/Music/$title.flac',
    artists: [artist],
    album: SpotubeSimpleAlbumObject(
      id: 'webdav:album-1',
      name: albumName,
      externalUri: '',
      artists: [artist],
      albumType: SpotubeAlbumType.album,
      releaseDate: '1970-01-01',
    ),
    durationMs: 0,
    path: 'https://dav.example/Music/$title.flac',
    webDavAccountId: 'account-1',
  );
}
