import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/webdav/webdav_artist_image_matcher.dart';

void main() {
  late HttpServer server;
  late Directory cacheDirectory;
  late Uri baseUri;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    cacheDirectory = await Directory.systemTemp.createTemp('spotube-artist-');
    baseUri = Uri.parse('http://${server.address.host}:${server.port}/');
  });

  tearDown(() async {
    await server.close(force: true);
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  });

  test('finds an exact QQ artist portrait and caches it locally', () async {
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
                    {'mid': 'wrong-artist', 'name': '林俊杰'},
                  ],
                },
                {
                  'singer': [
                    {'mid': '0025NhlN2yWrP4', 'name': '周杰倫'},
                  ],
                },
                {
                  'singer': [
                    {'mid': '0025NhlN2yWrP4', 'name': '周杰伦'},
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

    final matcher = WebDavArtistImageMatcher(
      dio: Dio(),
      searchBaseUri: baseUri,
      artworkBaseUri: baseUri,
      cacheDirectory: cacheDirectory,
    );
    addTearDown(matcher.close);

    final first = await matcher.enrich(_track('track-1'));
    final second = await matcher.enrich(_track('track-2'));

    final imagePath = first.artists.single.images!.single.url;
    expect(await File(imagePath).exists(), isTrue);
    expect(first.album.artists.single.images!.single.url, imagePath);
    expect(second.artists.single.images!.single.url, imagePath);
    expect(searchRequests, 1);
    expect(imageRequests, 1);
  });
}

SpotubeLocalTrackObject _track(String id) {
  final artist = SpotubeSimpleArtistObject(
    id: 'musicbrainz:artist-1',
    name: '周杰伦',
    externalUri: 'https://musicbrainz.org/artist/artist-1',
  );
  return SpotubeLocalTrackObject(
    id: id,
    name: 'Song',
    externalUri: 'https://dav.example/$id.flac',
    artists: [artist],
    album: SpotubeSimpleAlbumObject(
      id: 'musicbrainz:album-1',
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
