import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/services/webdav/webdav_metadata_matcher.dart';

void main() {
  late HttpServer server;
  late Directory cacheDirectory;
  late Uri baseUri;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    cacheDirectory = await Directory.systemTemp.createTemp('spotube-covers-');
    baseUri = Uri.parse('http://${server.address.host}:${server.port}/');
  });

  tearDown(() async {
    await server.close(force: true);
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  });

  test('selects an original official album and caches its cover locally',
      () async {
    var coverRequests = 0;
    var searchRequests = 0;
    server.listen((request) async {
      if (request.uri.path == '/ws/2/recording/') {
        searchRequests++;
        expect(request.headers.value(HttpHeaders.userAgentHeader),
            WebDavMetadataMatcher.userAgent);
        expect(request.uri.queryParameters['limit'], '25');
        expect(
          request.uri.queryParameters['query'],
          'recording:"东风破" AND artist:"周杰伦"',
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_musicBrainzResponse));
      } else if (request.uri.path ==
          '/release-group/release-group-original/front-250') {
        coverRequests++;
        request.response
          ..headers.contentType = ContentType('image', 'jpeg')
          ..add([0xff, 0xd8, 0xff, 0xd9]);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final source = _sourceTrack();
    final matcher = WebDavMetadataMatcher(
      dio: Dio(),
      musicBrainzBaseUri: baseUri,
      coverArtBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
      requestInterval: Duration.zero,
    );
    addTearDown(matcher.close);

    final matches = await Future.wait([
      matcher.match(source),
      matcher.match(source),
    ]);
    final first = matches.first;
    final second = matches.last;

    expect(first, isNotNull);
    expect(first!.track.id, source.id);
    expect(first.track.path, source.path);
    expect(first.track.name, '东风破');
    expect(first.track.artists.single.name, '周杰伦');
    expect(first.track.artists.single.id, 'musicbrainz:artist-jay');
    expect(first.track.album.name, '叶惠美');
    expect(first.track.album.id, 'musicbrainz:release-group-original');
    expect(first.track.album.releaseDate, '2003-07-31');
    expect(first.track.durationMs, 315413);
    expect(first.releaseGroupId, 'release-group-original');
    final cover = File(first.track.album.images.single.url);
    expect(await cover.exists(), isTrue);
    expect(await cover.readAsBytes(), [0xff, 0xd8, 0xff, 0xd9]);
    expect(second!.track.album.images.single.url, cover.path);
    expect(searchRequests, 2);
    expect(coverRequests, 1);
  });

  test('does not overwrite a track with a low-confidence candidate', () async {
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'recordings': [
            {
              'id': 'wrong-recording',
              'title': '完全不同的歌曲',
              'score': 20,
              'artist-credit': [
                {
                  'name': '其他歌手',
                  'artist': {'id': 'other', 'name': '其他歌手'},
                },
              ],
              'releases': [],
            },
          ],
        }),
      );
      await request.response.close();
    });
    final matcher = WebDavMetadataMatcher(
      dio: Dio(),
      musicBrainzBaseUri: baseUri,
      coverArtBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
      requestInterval: Duration.zero,
    );
    addTearDown(matcher.close);

    expect(await matcher.match(_sourceTrack()), isNull);
  });

  test('keeps concurrent MusicBrainz requests inside the rate limit', () async {
    final requestedAt = <DateTime>[];
    server.listen((request) async {
      requestedAt.add(DateTime.now());
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'recordings': const []}));
      await request.response.close();
    });
    final matcher = WebDavMetadataMatcher(
      dio: Dio(),
      musicBrainzBaseUri: baseUri,
      coverArtBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
      requestInterval: const Duration(milliseconds: 60),
    );
    addTearDown(matcher.close);

    await Future.wait([
      matcher.match(_sourceTrack()),
      matcher.match(_sourceTrack()),
      matcher.match(_sourceTrack()),
    ]);

    expect(requestedAt, hasLength(3));
    for (var index = 1; index < requestedAt.length; index++) {
      expect(
        requestedAt[index].difference(requestedAt[index - 1]),
        greaterThanOrEqualTo(const Duration(milliseconds: 40)),
      );
    }
  });
}

const _account = WebDavAccount(
  id: 'account-1',
  name: 'Music server',
  url: 'https://dav.example/dav/',
  rootPath: 'Music',
  username: 'listener',
  password: 'secret',
);

SpotubeLocalTrackObject _sourceTrack() => WebDavEntry(
      uri: Uri.parse(
        'https://dav.example/dav/Music/%E5%91%A8%E6%9D%B0%E4%BC%A6/%E5%91%A8%E6%9D%B0%E4%BC%A6-%E4%B8%9C%E9%A3%8E%E7%A0%B4.wav',
      ),
      displayName: '周杰伦-东风破.wav',
      isDirectory: false,
      contentType: 'audio/wav',
    ).toTrack(_account);

const _musicBrainzResponse = {
  'recordings': [
    {
      'id': 'recording-compilation-simplified',
      'title': '东风破',
      'score': 100,
      'length': 315413,
      'artist-credit': [
        {
          'name': '周杰倫',
          'artist': {'id': 'artist-jay', 'name': '周杰倫'},
        },
      ],
      'releases': [
        {
          'title': '曠世傑作',
          'status': 'Official',
          'date': '2022-12-02',
          'release-group': {
            'id': 'release-group-compilation-simplified',
            'primary-type': 'Album',
            'secondary-types': ['Compilation'],
          },
        },
      ],
    },
    {
      'id': 'recording-live',
      'title': '東風破',
      'score': 100,
      'length': 320000,
      'artist-credit': [
        {
          'name': '周杰倫',
          'artist': {'id': 'artist-jay', 'name': '周杰倫'},
        },
      ],
      'releases': [
        {
          'title': '2004 無與倫比演唱會',
          'status': 'Official',
          'date': '2005-01-21',
          'release-group': {
            'id': 'release-group-live',
            'primary-type': 'Album',
            'secondary-types': ['Live'],
          },
        },
      ],
    },
    {
      'id': 'recording-original',
      'title': '東風破',
      'score': 100,
      'length': 315413,
      'artist-credit': [
        {
          'name': '周杰倫',
          'artist': {'id': 'artist-jay', 'name': '周杰倫'},
        },
      ],
      'releases': [
        {
          'title': '周杰倫 2001-2020 玩樂時光',
          'status': 'Official',
          'date': '2021-01-01',
          'release-group': {
            'id': 'release-group-compilation',
            'primary-type': 'Album',
            'secondary-types': ['Compilation'],
          },
        },
        {
          'title': '葉惠美',
          'status': 'Official',
          'date': '2003-07-31',
          'artist-credit': [
            {
              'name': '周杰倫',
              'artist': {'id': 'artist-jay', 'name': '周杰倫'},
            },
          ],
          'release-group': {
            'id': 'release-group-original',
            'primary-type': 'Album',
            'secondary-types': [],
            'first-release-date': '2003-07-31',
          },
        },
      ],
    },
  ],
};
