import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/webdav/chinese_metadata_normalizer.dart';

/// Finds artist portraits through QQ Music and stores them in the local
/// metadata cache. No image or metadata is written back to WebDAV.
class WebDavArtistImageMatcher {
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Spotube-WebDAV/1.0';

  final Dio _dio;
  final bool _ownsDio;
  final Uri searchBaseUri;
  final Uri artworkBaseUri;
  final Directory? cacheDirectory;
  final Map<String, Future<String?>> _imageCache = {};

  WebDavArtistImageMatcher({
    Dio? dio,
    Uri? searchBaseUri,
    Uri? artworkBaseUri,
    this.cacheDirectory,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                sendTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
              ),
            ),
        _ownsDio = dio == null,
        searchBaseUri = searchBaseUri ?? Uri.parse('https://c.y.qq.com/'),
        artworkBaseUri =
            artworkBaseUri ?? Uri.parse('https://y.gtimg.cn/music/photo_new/');

  Future<SpotubeLocalTrackObject> enrich(
    SpotubeLocalTrackObject track,
  ) async {
    final artists = await Future.wait(
      track.artists.map(enrichArtist),
    );
    final artistsByName = {
      for (final artist in artists)
        ChineseMetadataNormalizer.key(artist.name): artist,
    };
    final albumArtists = await Future.wait(
      track.album.artists.map((artist) async {
        final resolved =
            artistsByName[ChineseMetadataNormalizer.key(artist.name)];
        if (resolved != null) return resolved;
        return await enrichArtist(artist);
      }),
    );

    return track.copyWith(
      artists: artists,
      album: track.album.copyWith(artists: albumArtists),
    );
  }

  Future<SpotubeSimpleArtistObject> enrichArtist(
    SpotubeSimpleArtistObject artist,
  ) async {
    if (artist.images?.isNotEmpty == true || artist.name.trim().isEmpty) {
      return artist;
    }
    final key = ChineseMetadataNormalizer.key(artist.name);
    if (key.isEmpty) return artist;
    final imagePath = await _imageCache.putIfAbsent(
      key,
      () => _findAndCacheImage(artist),
    );
    if (imagePath == null) return artist;
    return artist.copyWith(
      images: [
        SpotubeImageObject(
          url: imagePath,
          width: 500,
          height: 500,
        ),
      ],
    );
  }

  Future<String?> _findAndCacheImage(
    SpotubeSimpleArtistObject artist,
  ) async {
    final artistMid =
        _qqArtistMid(artist) ?? await _searchArtistMid(artist.name);
    if (artistMid == null) return null;
    return _downloadArtistImage(artistMid);
  }

  String? _qqArtistMid(SpotubeSimpleArtistObject artist) {
    const prefix = 'qq:artist:';
    if (!artist.id.startsWith(prefix)) return null;
    final value = artist.id.substring(prefix.length);
    return RegExp(r'^[A-Za-z0-9]{8,}$').hasMatch(value) ? value : null;
  }

  Future<String?> _searchArtistMid(String artistName) async {
    final uri = searchBaseUri.resolve('soso/fcgi-bin/client_search_cp').replace(
      queryParameters: {
        'p': '1',
        'n': '30',
        'w': artistName,
        'format': 'json',
      },
    );
    final response = await _dio.getUri<dynamic>(
      uri,
      options: Options(
        headers: const {
          'User-Agent': userAgent,
          'Referer': 'https://y.qq.com/',
          'Accept': 'application/json',
        },
        responseType: ResponseType.plain,
      ),
    );
    final raw = response.data;
    final decoded = raw is String ? jsonDecode(raw) : raw;
    final data = decoded is Map ? decoded['data'] : null;
    final song = data is Map ? data['song'] : null;
    final results = song is Map ? song['list'] : null;
    if (results is! List) return null;

    final expected = ChineseMetadataNormalizer.key(artistName);
    final counts = <String, int>{};
    for (final result in results.whereType<Map>()) {
      final singers = result['singer'];
      if (singers is! List) continue;
      for (final singer in singers.whereType<Map>()) {
        final name = singer['name']?.toString() ?? '';
        final mid = singer['mid']?.toString() ?? '';
        if (mid.isEmpty || ChineseMetadataNormalizer.key(name) != expected) {
          continue;
        }
        counts[mid] = (counts[mid] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    final matches = counts.entries.toList(growable: false)
      ..sort((left, right) => right.value.compareTo(left.value));
    return matches.first.key;
  }

  Future<String?> _downloadArtistImage(String artistMid) async {
    final directory = cacheDirectory ??
        Directory(
          path.join(
            (await getApplicationSupportDirectory()).path,
            'webdav_metadata',
            'artists',
          ),
        );
    final image = File(
      path.join(directory.path, 'qq_artist_${artistMid}_500.jpg'),
    );
    if (await image.exists() && await image.length() > 0) {
      return image.absolute.path;
    }

    final response = await _dio.getUri<List<int>>(
      artworkBaseUri.resolve('T001R500x500M000$artistMid.jpg'),
      options: Options(
        headers: const {
          'User-Agent': userAgent,
          'Referer': 'https://y.qq.com/',
          'Accept': 'image/*',
        },
        responseType: ResponseType.bytes,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    if (response.statusCode != HttpStatus.ok ||
        response.data == null ||
        response.data!.isEmpty) {
      return null;
    }
    if (!await directory.exists()) await directory.create(recursive: true);
    await image.writeAsBytes(response.data!, flush: true);
    return image.absolute.path;
  }

  void close() {
    if (_ownsDio) _dio.close();
  }
}
