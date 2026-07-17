import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/services/webdav/chinese_metadata_normalizer.dart';
import 'package:spotube/services/webdav/webdav_metadata_matcher.dart';

/// A second-pass matcher backed by Apple's public iTunes Search API.
///
/// It is intentionally separate from MusicBrainz so tracks missed by the
/// first pass are retried against a different catalog and search engine.
class WebDavAlternativeMetadataMatcher {
  static const userAgent =
      'Spotube-WebDAV/1.0 (https://github.com/KRTirtho/spotube)';

  final Dio _dio;
  final bool _ownsDio;
  final Uri searchBaseUri;
  final Directory? cacheDirectory;
  final double maximumDistance;
  final Map<String, Future<String?>> _coverCache = {};

  WebDavAlternativeMetadataMatcher({
    Dio? dio,
    Uri? searchBaseUri,
    this.cacheDirectory,
    this.maximumDistance = 0.35,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                sendTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
              ),
            ),
        _ownsDio = dio == null,
        searchBaseUri = searchBaseUri ?? Uri.parse('https://itunes.apple.com/');

  Future<WebDavMetadataMatch?> match(SpotubeLocalTrackObject source) async {
    final knownArtist = source.artists
        .map((artist) => artist.name)
        .where(_isKnownArtist)
        .firstOrNull;
    final title = _cleanSearchTerm(source.name);
    final romanizedWithHanArtist = knownArtist != null &&
        RegExp(r'[a-z]+(?:\s+[a-z]+)+', caseSensitive: false).hasMatch(title) &&
        !RegExp(r'[\u3400-\u9fff]').hasMatch(title) &&
        RegExp(r'[\u3400-\u9fff]').hasMatch(knownArtist);
    final terms = <String>{};
    if (romanizedWithHanArtist) {
      terms.add('$knownArtist $title'.trim());
    }
    terms
      ..add([title, if (knownArtist != null) knownArtist].join(' ').trim())
      ..add(title)
      ..removeWhere((term) => term.isEmpty);

    for (final term in terms) {
      final response = await _search(term);
      final results = response['results'];
      if (results is! List) continue;
      final candidates = results
          .whereType<Map>()
          .map((value) => value.cast<String, dynamic>())
          .map((value) => _AlternativeCandidate.fromJson(value, source))
          .whereType<_AlternativeCandidate>()
          .toList(growable: false)
        ..sort((left, right) => left.distance.compareTo(right.distance));
      if (candidates.isEmpty) continue;

      final selected = candidates.first;
      if (selected.distance > maximumDistance ||
          selected.titleDistance > 0.32 ||
          (selected.artistComparable && selected.artistDistance > 0.45)) {
        continue;
      }

      final coverPath = selected.artworkUrl == null
          ? null
          : await _coverCache.putIfAbsent(
              (selected.collectionId ?? selected.trackId).toString(),
              () => _downloadCover(
                selected.collectionId ?? selected.trackId,
                selected.artworkUrl!,
              ),
            );
      final artistName =
          ChineseMetadataNormalizer.simplify(selected.artistName);
      final artist = SpotubeSimpleArtistObject(
        id: 'itunes:artist:${selected.artistId ?? artistName}',
        name: artistName,
        externalUri: selected.artistViewUrl ?? '',
      );
      final albumName = ChineseMetadataNormalizer.simplify(
        selected.collectionName ?? source.album.name,
      );
      final matchedTitle = ChineseMetadataNormalizer.simplify(
        selected.trackName,
      );
      final displayTitle = ChineseMetadataNormalizer.key(matchedTitle) ==
              ChineseMetadataNormalizer.key(source.name)
          ? source.name
          : matchedTitle;
      final enriched = source.copyWith(
        name: displayTitle,
        artists: [artist],
        durationMs: selected.durationMs ?? source.durationMs,
        album: SpotubeSimpleAlbumObject(
          id: 'itunes:${selected.collectionId ?? selected.trackId}',
          name: albumName,
          externalUri: selected.collectionViewUrl ?? '',
          artists: [artist],
          images: coverPath == null
              ? source.album.images
              : [
                  SpotubeImageObject(
                    url: coverPath,
                    width: 600,
                    height: 600,
                  ),
                ],
          albumType: SpotubeAlbumType.album,
          releaseDate: selected.releaseDate ?? source.album.releaseDate,
        ),
      );
      return WebDavMetadataMatch(
        track: ChineseMetadataNormalizer.normalizeTrack(enriched),
        distance: selected.distance,
        recordingId: 'itunes:${selected.trackId}',
        releaseGroupId: selected.collectionId == null
            ? null
            : 'itunes:${selected.collectionId}',
      );
    }
    return null;
  }

  Future<Map<String, dynamic>> _search(String term) async {
    final uri = searchBaseUri.resolve('search').replace(
      queryParameters: {
        'term': term,
        'media': 'music',
        'entity': 'song',
        'country': 'CN',
        'limit': '50',
      },
    );
    // The iTunes endpoint currently responds with `text/javascript`, so Dio
    // intentionally leaves the JSON as a String on desktop. Parse the body
    // ourselves instead of asking Dio to cast it to a Map.
    final response = await _dio.getUri<dynamic>(
      uri,
      options: Options(
        headers: const {'User-Agent': userAgent, 'Accept': 'application/json'},
        responseType: ResponseType.plain,
      ),
    );
    final raw = response.data;
    final decoded = raw is String ? jsonDecode(raw) : raw;
    return decoded is Map
        ? decoded.cast<String, dynamic>()
        : const <String, dynamic>{};
  }

  Future<String?> _downloadCover(Object id, String sourceUrl) async {
    final directory = cacheDirectory ??
        Directory(
          path.join(
            (await getApplicationSupportDirectory()).path,
            'webdav_metadata',
            'covers',
          ),
        );
    final cover = File(path.join(directory.path, 'itunes_${id}_600.jpg'));
    if (await cover.exists() && await cover.length() > 0) {
      return cover.absolute.path;
    }

    final artworkUri = Uri.parse(sourceUrl.replaceFirst(
      RegExp(r'\d+x\d+bb'),
      '600x600bb',
    ));
    final response = await _dio.getUri<List<int>>(
      artworkUri,
      options: Options(
        headers: const {'User-Agent': userAgent, 'Accept': 'image/*'},
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
    await cover.writeAsBytes(response.data!, flush: true);
    return cover.absolute.path;
  }

  void close() {
    if (_ownsDio) _dio.close();
  }

  static String _cleanSearchTerm(String value) =>
      WebDavTrackIdentity.cleanSearchTitle(
        ChineseMetadataNormalizer.simplify(value),
      )
          .replaceAll(
            RegExp(
              r'[\[(（【].*?(?:album\s+version|version|live|remix|remaster|伴奏|翻唱|现场|版).*?[\])）】]',
              caseSensitive: false,
            ),
            ' ',
          )
          .replaceAll(RegExp(r'[·・‧•]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  static bool _isKnownArtist(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isNotEmpty &&
        normalized != webDavUnknownArtist.toLowerCase();
  }
}

class _AlternativeCandidate {
  final int trackId;
  final int? collectionId;
  final int? artistId;
  final String trackName;
  final String artistName;
  final String? collectionName;
  final String? artworkUrl;
  final String? artistViewUrl;
  final String? collectionViewUrl;
  final String? releaseDate;
  final int? durationMs;
  final double titleDistance;
  final double artistDistance;
  final bool artistComparable;
  final double distance;

  const _AlternativeCandidate({
    required this.trackId,
    required this.collectionId,
    required this.artistId,
    required this.trackName,
    required this.artistName,
    required this.collectionName,
    required this.artworkUrl,
    required this.artistViewUrl,
    required this.collectionViewUrl,
    required this.releaseDate,
    required this.durationMs,
    required this.titleDistance,
    required this.artistDistance,
    required this.artistComparable,
    required this.distance,
  });

  static _AlternativeCandidate? fromJson(
    Map<String, dynamic> json,
    SpotubeLocalTrackObject source,
  ) {
    final trackId = _intValue(json['trackId']);
    final trackName = json['trackName'];
    final artistName = json['artistName'];
    if (trackId == null || trackName is! String || artistName is! String) {
      return null;
    }
    final titleDistance = _stringDistance(source.name, trackName);
    final expectedArtists = source.artists
        .map((artist) => artist.name)
        .where(WebDavAlternativeMetadataMatcher._isKnownArtist)
        .toList(growable: false);
    final comparableArtists = expectedArtists
        .where(
          (artist) => webDavUsesComparableWritingSystem(artist, artistName),
        )
        .toList(growable: false);
    final artistComparable = comparableArtists.isNotEmpty;
    final artistDistance = !artistComparable
        ? 0.0
        : comparableArtists
            .map((artist) => _stringDistance(artist, artistName))
            .reduce(math.min);
    var weighted = titleDistance * 0.65;
    var totalWeight = 0.65;
    if (artistComparable) {
      weighted += artistDistance * 0.25;
      totalWeight += 0.25;
    }
    final durationMs = _intValue(json['trackTimeMillis']);
    if (source.durationMs > 0 && durationMs != null) {
      weighted +=
          math.min(1.0, (source.durationMs - durationMs).abs() / 15000) * 0.10;
      totalWeight += 0.10;
    }
    final sourceHasEdition = _hasEditionMarker(source.name);
    final candidateHasEdition = _hasEditionMarker(trackName);
    final editionPenalty = !sourceHasEdition && candidateHasEdition ? 0.18 : 0;
    final rawReleaseDate = json['releaseDate'];
    final releaseDate = rawReleaseDate is String && rawReleaseDate.length >= 10
        ? rawReleaseDate.substring(0, 10)
        : null;
    return _AlternativeCandidate(
      trackId: trackId,
      collectionId: _intValue(json['collectionId']),
      artistId: _intValue(json['artistId']),
      trackName: trackName,
      artistName: artistName,
      collectionName: json['collectionName'] as String?,
      artworkUrl: json['artworkUrl100'] as String?,
      artistViewUrl: json['artistViewUrl'] as String?,
      collectionViewUrl: json['collectionViewUrl'] as String?,
      releaseDate: releaseDate,
      durationMs: durationMs,
      titleDistance: titleDistance,
      artistDistance: artistDistance,
      artistComparable: artistComparable,
      distance: weighted / totalWeight + editionPenalty,
    );
  }

  static bool _hasEditionMarker(String value) => RegExp(
        r'\b(?:live|remix|remaster|instrumental|cover)\b|伴奏|翻唱|现场|演唱会',
        caseSensitive: false,
      ).hasMatch(value);

  static int? _intValue(Object? value) => switch (value) {
        num number => number.toInt(),
        String text => int.tryParse(text),
        _ => null,
      };

  static double _stringDistance(String left, String right) {
    final a = _comparisonKey(left).runes.toList(growable: false);
    final b = _comparisonKey(right).runes.toList(growable: false);
    if (a.isEmpty && b.isEmpty) return 0;
    if (a.isEmpty || b.isEmpty) return 1;
    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var row = 1; row <= a.length; row++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = row;
      for (var column = 1; column <= b.length; column++) {
        final substitution =
            previous[column - 1] + (a[row - 1] == b[column - 1] ? 0 : 1);
        final insertion = current[column - 1] + 1;
        final deletion = previous[column] + 1;
        current[column] = insertion < deletion ? insertion : deletion;
        if (substitution < current[column]) current[column] = substitution;
      }
      previous = current;
    }
    return previous.last / math.max(a.length, b.length);
  }

  static String _comparisonKey(String value) => ChineseMetadataNormalizer.key(
        value.replaceAll(
          RegExp(
            r'[\[(（【]\s*(?:with|feat\.?|ft\.?|featuring)\s+.*?[\])）】]',
            caseSensitive: false,
          ),
          '',
        ),
      );
}
