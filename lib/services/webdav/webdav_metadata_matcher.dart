import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/services/webdav/chinese_metadata_normalizer.dart';

class WebDavMetadataMatch {
  final SpotubeLocalTrackObject track;
  final double distance;
  final String recordingId;
  final String? releaseGroupId;

  const WebDavMetadataMatch({
    required this.track,
    required this.distance,
    required this.recordingId,
    required this.releaseGroupId,
  });
}

/// Enriches WebDAV tracks without downloading or modifying their audio files.
///
/// The matching model follows beets' proven approach: normalize the supplied
/// tags, calculate a weighted edit distance for each MusicBrainz candidate,
/// and reject candidates above a conservative distance threshold. Covers are
/// downloaded from Cover Art Archive into application support storage.
class WebDavMetadataMatcher {
  static const userAgent =
      'Spotube-WebDAV/1.0 (https://github.com/KRTirtho/spotube)';
  static const defaultMaximumDistance = 0.25;

  final Dio _dio;
  final bool _ownsDio;
  final Uri musicBrainzBaseUri;
  final Uri coverArtBaseUri;
  final Directory? cacheDirectory;
  final Duration requestInterval;
  final Future<void> Function(Duration duration) _delay;
  final double maximumDistance;
  final Map<String, Future<String?>> _coverCache = {};

  DateTime? _lastMusicBrainzRequest;
  Future<void> _rateLimitQueue = Future<void>.value();

  WebDavMetadataMatcher({
    Dio? dio,
    Uri? musicBrainzBaseUri,
    Uri? coverArtBaseUri,
    this.cacheDirectory,
    this.requestInterval = const Duration(milliseconds: 1100),
    Future<void> Function(Duration duration)? delay,
    this.maximumDistance = defaultMaximumDistance,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                sendTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
              ),
            ),
        _ownsDio = dio == null,
        musicBrainzBaseUri =
            musicBrainzBaseUri ?? Uri.parse('https://musicbrainz.org/'),
        coverArtBaseUri =
            coverArtBaseUri ?? Uri.parse('https://coverartarchive.org/'),
        _delay = delay ?? Future<void>.delayed;

  Future<WebDavMetadataMatch?> match(SpotubeLocalTrackObject source) async {
    final response = await _search(source);
    final recordings = response['recordings'];
    if (recordings is! List) return null;

    final candidates = recordings
        .whereType<Map>()
        .expand(
          (recording) => _candidatesFor(
            recording.cast<String, dynamic>(),
            source,
          ),
        )
        .toList(growable: false)
      ..sort(_compareCandidates);
    if (candidates.isEmpty) return null;

    final selected = candidates.first;
    if (selected.distance > maximumDistance ||
        selected.titleDistance > 0.35 ||
        (selected.artistComparable &&
            !_isUnknownArtist(source.artists.first.name) &&
            selected.artistDistance > 0.45)) {
      return null;
    }

    final coverPath = selected.releaseGroupId == null
        ? null
        : await _coverCache.putIfAbsent(
            selected.releaseGroupId!,
            () => _downloadCover(selected.releaseGroupId!),
          );
    final artists = selected.artists
        .map(
          (artist) => SpotubeSimpleArtistObject(
            id: artist.id == null
                ? 'musicbrainz:artist:${ChineseMetadataNormalizer.simplify(artist.name)}'
                : 'musicbrainz:${artist.id}',
            name: ChineseMetadataNormalizer.simplify(artist.name),
            externalUri: artist.id == null
                ? 'https://musicbrainz.org/search?query=${Uri.encodeQueryComponent(artist.name)}&type=artist'
                : 'https://musicbrainz.org/artist/${artist.id}',
          ),
        )
        .toList(growable: false);
    final resolvedArtists = artists.isEmpty ? source.artists : artists;
    final albumArtists = selected.albumArtists
        .map(
          (artist) => SpotubeSimpleArtistObject(
            id: artist.id == null
                ? 'musicbrainz:artist:${ChineseMetadataNormalizer.simplify(artist.name)}'
                : 'musicbrainz:${artist.id}',
            name: ChineseMetadataNormalizer.simplify(artist.name),
            externalUri: artist.id == null
                ? 'https://musicbrainz.org/search?query=${Uri.encodeQueryComponent(artist.name)}&type=artist'
                : 'https://musicbrainz.org/artist/${artist.id}',
          ),
        )
        .toList(growable: false);

    final enriched = source.copyWith(
      name: ChineseMetadataNormalizer.simplify(selected.title),
      artists: resolvedArtists,
      durationMs: selected.durationMs ?? source.durationMs,
      album: SpotubeSimpleAlbumObject(
        id: selected.releaseGroupId == null
            ? source.album.id
            : 'musicbrainz:${selected.releaseGroupId}',
        name: ChineseMetadataNormalizer.simplify(
          selected.albumTitle ?? source.album.name,
        ),
        externalUri: selected.releaseGroupId == null
            ? source.album.externalUri
            : 'https://musicbrainz.org/release-group/${selected.releaseGroupId}',
        artists: albumArtists.isEmpty ? resolvedArtists : albumArtists,
        images: coverPath == null
            ? source.album.images
            : [
                SpotubeImageObject(
                  url: coverPath,
                  width: 250,
                  height: 250,
                ),
              ],
        albumType: selected.albumType,
        releaseDate: selected.releaseDate ?? source.album.releaseDate,
      ),
    );

    return WebDavMetadataMatch(
      track: ChineseMetadataNormalizer.normalizeTrack(enriched),
      distance: selected.distance,
      recordingId: selected.recordingId,
      releaseGroupId: selected.releaseGroupId,
    );
  }

  Future<Map<String, dynamic>> _search(
    SpotubeLocalTrackObject track,
  ) async {
    await _respectMusicBrainzRateLimit();
    final knownArtists = track.artists
        .map((artist) => artist.name)
        .where((artist) => !_isUnknownArtist(artist))
        .toList(growable: false);
    final query = <String>[
      'recording:${_quoteQuery(track.name)}',
      if (knownArtists.isNotEmpty) 'artist:${_quoteQuery(knownArtists.first)}',
    ].join(' AND ');

    final uri = musicBrainzBaseUri.resolve('ws/2/recording/').replace(
      queryParameters: {
        'query': query,
        'fmt': 'json',
        'limit': '25',
      },
    );
    final response = await _dio.getUri<Map<String, dynamic>>(
      uri,
      options: Options(
        headers: const {'User-Agent': userAgent, 'Accept': 'application/json'},
        responseType: ResponseType.json,
      ),
    );
    return response.data ?? const {};
  }

  Iterable<_MetadataCandidate> _candidatesFor(
    Map<String, dynamic> recording,
    SpotubeLocalTrackObject source,
  ) sync* {
    final recordingId = recording['id'] as String?;
    final title = recording['title'] as String?;
    if (recordingId == null || title == null || title.trim().isEmpty) return;

    final recordingArtists = _parseArtistCredit(recording['artist-credit']);
    final releases = recording['releases'];
    final releaseMaps = releases is List
        ? releases.whereType<Map>().map((item) => item.cast<String, dynamic>())
        : const <Map<String, dynamic>>[];
    final normalizedReleases = releaseMaps.isEmpty
        ? const <Map<String, dynamic>?>[null]
        : releaseMaps.cast<Map<String, dynamic>?>();

    for (final release in normalizedReleases) {
      final releaseGroup = release?['release-group'] is Map
          ? (release!['release-group'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final albumArtists = _parseArtistCredit(
          release?['artist-credit'] ?? recording['artist-credit']);
      final primaryType =
          (releaseGroup['primary-type'] as String? ?? '').toLowerCase();
      final secondaryTypes = (releaseGroup['secondary-types'] is List
              ? releaseGroup['secondary-types'] as List
              : const [])
          .whereType<String>()
          .map((type) => type.toLowerCase())
          .toList(growable: false);
      final albumType = secondaryTypes.contains('compilation')
          ? SpotubeAlbumType.compilation
          : (primaryType == 'single' || primaryType == 'ep')
              ? SpotubeAlbumType.single
              : SpotubeAlbumType.album;

      final remoteScore = switch (recording['score']) {
        int value => value.toDouble(),
        double value => value,
        _ => 0.0,
      };
      final titleDistance = _searchResultDistance(
        source.name,
        title,
        remoteScore: remoteScore,
      );
      final artistDistance = _artistDistance(
        source.artists.map((artist) => artist.name),
        recordingArtists.map((artist) => artist.name),
        remoteScore: remoteScore,
      );
      final artistComparable =
          source.artists.where((artist) => !_isUnknownArtist(artist.name)).any(
                (expected) => recordingArtists.any(
                  (candidate) => webDavUsesComparableWritingSystem(
                    expected.name,
                    candidate.name,
                  ),
                ),
              );
      final albumTitle = release?['title'] as String?;
      final albumKnown = !_isUnknownAlbum(source.album.name);
      final albumDistance = albumKnown && albumTitle != null
          ? _stringDistance(source.album.name, albumTitle)
          : null;
      final durationMs = recording['length'] as int?;
      final durationDistance = source.durationMs > 0 && durationMs != null
          ? math.min(
              1.0,
              (source.durationMs - durationMs).abs() /
                  math.max(source.durationMs, durationMs),
            )
          : null;
      var weightedDistance = titleDistance * 0.45;
      var totalWeight = 0.45;
      if (artistComparable) {
        weightedDistance += artistDistance * 0.30;
        totalWeight += 0.30;
      }
      if (albumDistance != null) {
        weightedDistance += albumDistance * 0.10;
        totalWeight += 0.10;
      }
      if (durationDistance != null) {
        weightedDistance += durationDistance * 0.10;
        totalWeight += 0.10;
      }
      weightedDistance += (1 - remoteScore.clamp(0, 100) / 100) * 0.05;
      totalWeight += 0.05;

      var releasePenalty = 0.0;
      if (release == null) releasePenalty += 0.08;
      if ((release?['status'] as String? ?? '').toLowerCase() != 'official') {
        releasePenalty += 0.06;
      }
      if (secondaryTypes.contains('live')) releasePenalty += 0.08;
      if (secondaryTypes.contains('compilation')) releasePenalty += 0.06;
      if (primaryType == 'single') releasePenalty += 0.015;
      if (primaryType == 'ep') releasePenalty += 0.02;
      if (primaryType.isNotEmpty &&
          primaryType != 'album' &&
          primaryType != 'single' &&
          primaryType != 'ep') {
        releasePenalty += 0.03;
      }

      yield _MetadataCandidate(
        recordingId: recordingId,
        title: title,
        artists: recordingArtists,
        durationMs: durationMs,
        albumTitle: albumTitle,
        albumArtists: albumArtists,
        releaseGroupId: releaseGroup['id'] as String?,
        releaseDate: release?['date'] as String? ??
            releaseGroup['first-release-date'] as String?,
        albumType: albumType,
        titleDistance: titleDistance,
        artistDistance: artistDistance,
        artistComparable: artistComparable,
        distance: weightedDistance / totalWeight + releasePenalty,
      );
    }
  }

  Future<String?> _downloadCover(String releaseGroupId) async {
    final directory = cacheDirectory ??
        Directory(
          path.join(
            (await getApplicationSupportDirectory()).path,
            'webdav_metadata',
            'covers',
          ),
        );
    final cover = File(path.join(directory.path, '${releaseGroupId}_250.jpg'));
    if (await cover.exists() && await cover.length() > 0) {
      return cover.absolute.path;
    }

    final response = await _dio.getUri<List<int>>(
      coverArtBaseUri.resolve('release-group/$releaseGroupId/front-250'),
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

  Future<void> _respectMusicBrainzRateLimit() {
    final turn = _rateLimitQueue.then<void>((_) async {
      final previous = _lastMusicBrainzRequest;
      if (previous != null && requestInterval != Duration.zero) {
        final remaining = requestInterval - DateTime.now().difference(previous);
        if (remaining > Duration.zero) await _delay(remaining);
      }
      _lastMusicBrainzRequest = DateTime.now();
    });
    _rateLimitQueue = turn.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return turn;
  }

  void close() {
    if (_ownsDio) _dio.close();
  }

  static String _quoteQuery(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  static List<_ArtistCredit> _parseArtistCredit(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((value) {
          final credit = value.cast<String, dynamic>();
          final artist = credit['artist'] is Map
              ? (credit['artist'] as Map).cast<String, dynamic>()
              : const <String, dynamic>{};
          return _ArtistCredit(
            id: artist['id'] as String?,
            name: (credit['name'] as String? ?? artist['name'] as String? ?? '')
                .trim(),
          );
        })
        .where((artist) => artist.name.isNotEmpty)
        .toList(growable: false);
  }

  static int _compareCandidates(
    _MetadataCandidate left,
    _MetadataCandidate right,
  ) {
    final distance = left.distance.compareTo(right.distance);
    if (distance != 0) return distance;
    final leftDate = left.releaseDate ?? '9999';
    final rightDate = right.releaseDate ?? '9999';
    return leftDate.compareTo(rightDate);
  }

  static bool _isUnknownArtist(String value) =>
      value.trim().isEmpty ||
      value.toLowerCase() == webDavUnknownArtist.toLowerCase();

  static bool _isUnknownAlbum(String value) =>
      value.trim().isEmpty ||
      value.toLowerCase() == webDavUnknownAlbum.toLowerCase();

  static double _artistDistance(
    Iterable<String> expected,
    Iterable<String> candidate, {
    required double remoteScore,
  }) {
    final expectedArtists = expected
        .where((artist) => !_isUnknownArtist(artist))
        .toList(growable: false);
    final candidateArtists = candidate.toList(growable: false);
    if (expectedArtists.isEmpty) return 0;
    if (candidateArtists.isEmpty) return 1;
    final distances = expectedArtists
        .map(
          (artist) => candidateArtists
              .where(
                (other) => webDavUsesComparableWritingSystem(artist, other),
              )
              .map(
                (other) => _searchResultDistance(
                  artist,
                  other,
                  remoteScore: remoteScore,
                ),
              )
              .fold<double>(1, math.min),
        )
        .toList(growable: false);
    return distances.isEmpty
        ? 0
        : distances.reduce((left, right) => left + right) / distances.length;
  }

  static double _searchResultDistance(
    String left,
    String right, {
    required double remoteScore,
  }) {
    final distance = _stringDistance(left, right);
    if (distance == 0 || remoteScore < 95) return distance;

    final a = _normalize(left).runes.toList(growable: false);
    final b = _normalize(right).runes.toList(growable: false);
    if (a.length != b.length || a.isEmpty) return distance;
    final allHan = [...a, ...b].every(_isHanRune);
    // MusicBrainz indexes aliases, so a score near 100 plus equal-length Han
    // text is a strong simplified/traditional signal (东风破 ↔ 東風破). A small
    // non-zero cost still lets exact text win unless that release is a live or
    // compilation edition.
    return allHan ? math.min(distance, 0.05) : distance;
  }

  static bool _isHanRune(int rune) =>
      (rune >= 0x3400 && rune <= 0x4dbf) ||
      (rune >= 0x4e00 && rune <= 0x9fff) ||
      (rune >= 0xf900 && rune <= 0xfaff);

  static double _stringDistance(String left, String right) {
    final a = _normalize(left).runes.toList(growable: false);
    final b = _normalize(right).runes.toList(growable: false);
    if (a.isEmpty && b.isEmpty) return 0;
    if (a.isEmpty || b.isEmpty) return 1;

    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var row = 1; row <= a.length; row++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = row;
      for (var column = 1; column <= b.length; column++) {
        final substitution =
            previous[column - 1] + (a[row - 1] == b[column - 1] ? 0 : 1);
        current[column] = math.min(
          math.min(current[column - 1] + 1, previous[column] + 1),
          substitution,
        );
      }
      previous = current;
    }
    return previous.last / math.max(a.length, b.length);
  }

  static String _normalize(String value) =>
      ChineseMetadataNormalizer.key(value);
}

class _ArtistCredit {
  final String? id;
  final String name;

  const _ArtistCredit({required this.id, required this.name});
}

class _MetadataCandidate {
  final String recordingId;
  final String title;
  final List<_ArtistCredit> artists;
  final int? durationMs;
  final String? albumTitle;
  final List<_ArtistCredit> albumArtists;
  final String? releaseGroupId;
  final String? releaseDate;
  final SpotubeAlbumType albumType;
  final double titleDistance;
  final double artistDistance;
  final bool artistComparable;
  final double distance;

  const _MetadataCandidate({
    required this.recordingId,
    required this.title,
    required this.artists,
    required this.durationMs,
    required this.albumTitle,
    required this.albumArtists,
    required this.releaseGroupId,
    required this.releaseDate,
    required this.albumType,
    required this.titleDistance,
    required this.artistDistance,
    required this.artistComparable,
    required this.distance,
  });
}
