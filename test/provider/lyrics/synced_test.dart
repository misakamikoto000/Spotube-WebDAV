import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/lyrics/synced.dart';

void main() {
  late HttpServer server;
  late Uri baseUri;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://${server.address.host}:${server.port}');
  });

  tearDown(() => server.close(force: true));

  test('falls back to search and selects matching synchronized lyrics',
      () async {
    final requestedPaths = <String>[];
    server.listen((request) async {
      requestedPaths.add(request.uri.path);
      if (request.uri.path == '/api/get') {
        expect(request.uri.queryParameters['track_name'], '兰亭序');
        expect(request.uri.queryParameters['artist_name'], '周杰伦');
        expect(request.uri.queryParameters['album_name'], '跨时代');
        request.response.statusCode = HttpStatus.notFound;
      } else if (request.uri.path == '/api/search') {
        expect(request.uri.queryParameters['track_name'], '兰亭序');
        expect(request.uri.queryParameters['artist_name'], '周杰伦');
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode([
          {
            'trackName': '兰亭序',
            'artistName': '其他歌手',
            'albumName': '错误专辑',
            'duration': 253,
            'syncedLyrics': '[00:00.00]错误歌词',
          },
          {
            'trackName': '蘭亭序',
            'artistName': '周杰倫',
            'albumName': '跨時代',
            'duration': 253.2,
            'plainLyrics': '兰亭临帖 行书如行云流水',
            'syncedLyrics': '[00:00.00]兰亭临帖\n[00:05.00]行书如行云流水',
          },
        ]));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final lyrics = await LrclibLyricsClient(
      dio: Dio(),
      baseUri: baseUri,
      userAgent: 'Spotube test',
    ).getLyrics(_track());

    expect(requestedPaths, ['/api/get', '/api/search']);
    expect(lyrics.provider, 'LRCLib');
    expect(lyrics.rating, 100);
    expect(lyrics.lyrics, hasLength(2));
    expect(lyrics.lyrics.first.text, '兰亭临帖');
  });

  test('safely uses plain lyrics when synced lyrics are missing', () async {
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'trackName': '蘭亭序',
        'artistName': '周杰倫',
        'plainLyrics': '第一行\n第二行',
        'syncedLyrics': null,
      }));
      await request.response.close();
    });

    final lyrics = await LrclibLyricsClient(
      dio: Dio(),
      baseUri: baseUri,
      userAgent: 'Spotube test',
    ).getLyrics(_track());

    expect(lyrics.rating, 50);
    expect(lyrics.lyrics.map((line) => line.text), ['第一行', '第二行']);
  });

  test('retries a featured track with the collaboration suffix removed',
      () async {
    final searchedTitles = <String>[];
    server.listen((request) async {
      if (request.uri.path == '/api/get') {
        request.response.statusCode = HttpStatus.notFound;
      } else if (request.uri.path == '/api/search') {
        final title = request.uri.queryParameters['track_name']!;
        searchedTitles.add(title);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(
          title == '不该'
              ? [
                  {
                    'trackName': '不该 (with aMEI)',
                    'artistName': '周杰伦',
                    'albumName': '周杰伦的床边故事',
                    'duration': 291.4,
                    'syncedLyrics':
                        '[00:00.00]假如把犯得起的错\n[00:05.00]能错的都错过',
                  },
                ]
              : const [],
        ));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final lyrics = await LrclibLyricsClient(
      dio: Dio(),
      baseUri: baseUri,
      userAgent: 'Spotube test',
    ).getLyrics(
      _track().copyWith(
        name: '不该 (with 张惠妹)',
        album: _track().album.copyWith(name: '周杰伦的床边故事'),
        durationMs: 291407,
      ),
    );

    expect(searchedTitles, ['不该 (with 张惠妹)', '不该']);
    expect(lyrics.lyrics.first.text, '假如把犯得起的错');
  });
}

SpotubeLocalTrackObject _track() {
  final artist = SpotubeSimpleArtistObject(
    id: 'musicbrainz:artist-1',
    name: '周杰倫',
    externalUri: '',
  );
  return SpotubeLocalTrackObject(
    id: 'track-1',
    name: '蘭亭序',
    externalUri: 'https://dav.example/Music/蘭亭序.flac',
    artists: [artist],
    album: SpotubeSimpleAlbumObject(
      id: 'musicbrainz:album-1',
      name: '跨時代',
      externalUri: '',
      artists: [artist],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 253000,
    path: 'https://dav.example/Music/蘭亭序.flac',
    webDavAccountId: 'account-1',
  );
}
