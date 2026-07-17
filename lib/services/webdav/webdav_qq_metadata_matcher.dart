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

/// Final metadata fallback backed by QQ Music's public web search endpoint.
///
/// Search results and downloaded artwork are used only to enrich the local
/// WebDAV index; nothing is written back to the remote library.
class WebDavQqMetadataMatcher {
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Spotube-WebDAV/1.0';

  final Dio _dio;
  final bool _ownsDio;
  final Uri searchBaseUri;
  final Uri artworkBaseUri;
  final Directory? cacheDirectory;
  final double maximumDistance;
  final Map<String, Future<String?>> _coverCache = {};
  final Map<String, Future<Map<String, dynamic>>> _albumCache = {};

  WebDavQqMetadataMatcher({
    Dio? dio,
    Uri? searchBaseUri,
    Uri? artworkBaseUri,
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
        searchBaseUri = searchBaseUri ?? Uri.parse('https://c.y.qq.com/'),
        artworkBaseUri =
            artworkBaseUri ?? Uri.parse('https://y.gtimg.cn/music/photo_new/');

  Future<WebDavMetadataMatch?> match(SpotubeLocalTrackObject source) async {
    final knownArtists = source.artists
        .map((artist) => artist.name)
        .where(_isKnownArtist)
        .toList(growable: false);
    final title = _cleanSearchTerm(source.name);
    final romanizedTitle = _looksRomanized(title);
    final hasHanArtist = knownArtists.any(_containsHan);
    final compactTitle = title.replaceAll(RegExp(r'\s+'), '');
    final primaryTitle = _primaryTitleSegment(title);
    final compactPrimaryTitle = primaryTitle.replaceAll(RegExp(r'\s+'), '');
    final terms = <String>{};
    if (romanizedTitle && hasHanArtist) {
      terms.add([...knownArtists, title].join(' ').trim());
      if (compactTitle != title) {
        terms.add([...knownArtists, compactTitle].join(' ').trim());
      }
      if (primaryTitle != title) {
        terms.add([...knownArtists, primaryTitle].join(' ').trim());
        terms.add([...knownArtists, compactPrimaryTitle].join(' ').trim());
      }
      terms.add([title, ...knownArtists].join(' ').trim());
    } else {
      terms.add([title, ...knownArtists].join(' ').trim());
    }
    if (source.album.name != webDavUnknownAlbum &&
        !_looksLikeCollectionAlbum(source.album.name)) {
      if (knownArtists.isEmpty) {
        terms.add('$title ${source.album.name}'.trim());
      } else {
        terms.add('${source.album.name} ${knownArtists.join(' ')}'.trim());
      }
    }
    terms.add(title);
    terms.removeWhere((term) => term.isEmpty);

    for (final term in terms) {
      final response = await _search(term);
      final data = response['data'];
      final song = data is Map ? data['song'] : null;
      final results = song is Map ? song['list'] : null;
      if (results is! List) continue;

      final candidates = <_QqCandidate>[];
      var hasEarlierExactArtist = false;
      for (var index = 0; index < results.length; index++) {
        final value = results[index];
        if (value is! Map) continue;
        final candidate = _QqCandidate.fromJson(
          value.cast<String, dynamic>(),
          source,
          allowCrossScriptTitle: !hasEarlierExactArtist,
        );
        if (candidate != null) {
          candidates.add(candidate);
          if (candidate.exactArtist) hasEarlierExactArtist = true;
        }
      }
      candidates.sort((left, right) => left.distance.compareTo(right.distance));
      if (candidates.isEmpty) continue;

      final selected = candidates.first;
      if (selected.distance > maximumDistance ||
          selected.titleDistance > 0.32 ||
          (selected.artistComparable && selected.artistDistance > 0.45)) {
        continue;
      }

      return _buildMatch(source, selected);
    }
    return null;
  }

  Future<WebDavMetadataMatch> _buildMatch(
    SpotubeLocalTrackObject source,
    _QqCandidate selected, {
    String? forcedAlbumMid,
    String? forcedAlbumName,
    Map<String, List<SpotubeImageObject>> knownArtistImages = const {},
  }) async {
    final albumMid = forcedAlbumMid ?? selected.albumMid;
    final coverPath = albumMid == null
        ? null
        : await _coverCache.putIfAbsent(
            albumMid,
            () => _downloadCover(albumMid),
          );
    final artists = selected.artists.map(
      (artist) {
        final name = ChineseMetadataNormalizer.simplify(artist.name);
        return SpotubeSimpleArtistObject(
          id: 'qq:artist:${artist.mid ?? artist.name}',
          name: name,
          externalUri: artist.mid == null
              ? ''
              : 'https://y.qq.com/n/ryqq/singer/${artist.mid}',
          images: knownArtistImages[_artistIdentityKey(name)],
        );
      },
    ).toList(growable: false);
    final matchedTitle = ChineseMetadataNormalizer.simplify(selected.trackName);
    final displayTitle =
        _comparisonKey(matchedTitle) == _comparisonKey(source.name)
            ? source.name
            : matchedTitle;
    final albumName = ChineseMetadataNormalizer.simplify(
      forcedAlbumName?.trim().isNotEmpty == true
          ? forcedAlbumName!
          : selected.albumName?.trim().isNotEmpty == true
              ? selected.albumName!
              : source.album.name,
    );
    final albumId = albumMid ?? selected.songMid;
    final enriched = source.copyWith(
      name: displayTitle,
      artists: artists,
      durationMs: selected.durationMs ?? source.durationMs,
      album: SpotubeSimpleAlbumObject(
        id: 'qq:$albumId',
        name: albumName,
        externalUri: albumMid == null
            ? ''
            : 'https://y.qq.com/n/ryqq/albumDetail/$albumMid',
        artists: artists,
        images: coverPath == null
            ? source.album.images
            : [
                SpotubeImageObject(
                  url: coverPath,
                  width: 500,
                  height: 500,
                ),
              ],
        albumType: SpotubeAlbumType.album,
        releaseDate: selected.releaseDate ?? source.album.releaseDate,
      ),
    );
    return WebDavMetadataMatch(
      track: ChineseMetadataNormalizer.normalizeTrack(enriched),
      distance: selected.distance,
      recordingId: 'qq:${selected.songMid}',
      releaseGroupId: albumMid == null ? null : 'qq:$albumMid',
    );
  }

  /// Reconciles a numbered physical folder with a QQ album track list.
  ///
  /// This is intentionally conservative: at least two already matched anchor
  /// tracks must share the album id, every file needs a unique 1..N track
  /// number, the remote album must contain exactly N songs, and the anchors
  /// must occur at the same positions. These constraints make track order a
  /// strong fallback for romanized, foreign-language and medley titles.
  Future<List<SpotubeLocalTrackObject>?> reconcileNumberedAlbum(
    List<SpotubeLocalTrackObject> tracks,
  ) async {
    if (tracks.length < 2) return null;
    final positions = <int, SpotubeLocalTrackObject>{};
    for (final track in tracks) {
      final position = _trackNumber(track.path);
      if (position == null || positions.containsKey(position)) return null;
      positions[position] = track;
    }
    if (positions.length != tracks.length ||
        positions.keys.reduce(math.min) != 1 ||
        positions.keys.reduce(math.max) != tracks.length) {
      return null;
    }

    final albumIdCounts = <String, int>{};
    for (final track in tracks) {
      if (!track.album.id.startsWith('qq:')) continue;
      final albumMid = track.album.id.substring('qq:'.length);
      if (albumMid.isEmpty) continue;
      albumIdCounts[albumMid] = (albumIdCounts[albumMid] ?? 0) + 1;
    }
    final albumCandidates = albumIdCounts.entries
        .where((entry) => entry.value >= 2)
        .toList(growable: false)
      ..sort((left, right) => right.value.compareTo(left.value));
    if (albumCandidates.isEmpty) return null;

    final knownArtistImages = <String, List<SpotubeImageObject>>{};
    for (final track in tracks) {
      for (final artist in [...track.artists, ...track.album.artists]) {
        if (artist.images?.isNotEmpty == true) {
          knownArtistImages[_artistIdentityKey(artist.name)] = artist.images!;
        }
      }
    }

    for (final albumEntry in albumCandidates) {
      final albumMid = albumEntry.key;
      final response = await _albumCache.putIfAbsent(
        albumMid,
        () => _fetchAlbum(albumMid),
      );
      final data = response['data'];
      final songs = data is Map ? data['list'] : null;
      if (songs is! List || songs.length != tracks.length) continue;

      final candidatesByPosition = <int, _QqCandidate>{};
      var valid = true;
      for (var position = 1; position <= tracks.length; position++) {
        final song = songs[position - 1];
        if (song is! Map) {
          valid = false;
          break;
        }
        final candidate = _QqCandidate.fromJson(
          song.cast<String, dynamic>(),
          positions[position]!,
          allowCrossScriptTitle: true,
        );
        if (candidate == null) {
          valid = false;
          break;
        }
        candidatesByPosition[position] = candidate;
      }
      if (!valid) continue;

      var alignedAnchors = 0;
      for (final entry in positions.entries) {
        if (entry.value.album.id != 'qq:$albumMid') continue;
        if (_titleDistance(
              entry.value.name,
              candidatesByPosition[entry.key]!.trackName,
            ) <=
            0.32) {
          alignedAnchors++;
        }
      }
      if (alignedAnchors < 2) continue;

      final albumName = data is Map ? data['name'] as String? : null;
      final reconciledByPath = <String, SpotubeLocalTrackObject>{};
      for (final entry in positions.entries) {
        final match = await _buildMatch(
          entry.value,
          candidatesByPosition[entry.key]!,
          forcedAlbumMid: albumMid,
          forcedAlbumName: albumName,
          knownArtistImages: knownArtistImages,
        );
        reconciledByPath[entry.value.path] = match.track;
      }
      return [for (final track in tracks) reconciledByPath[track.path]!];
    }
    return null;
  }

  Future<Map<String, dynamic>> _fetchAlbum(String albumMid) async {
    final uri = searchBaseUri
        .resolve('v8/fcg-bin/fcg_v8_album_info_cp.fcg')
        .replace(queryParameters: {'albummid': albumMid, 'format': 'json'});
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
    return decoded is Map
        ? decoded.cast<String, dynamic>()
        : const <String, dynamic>{};
  }

  static int? _trackNumber(String trackPath) {
    final uri = Uri.tryParse(trackPath);
    final filename = uri != null && uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : path.basename(trackPath);
    final basename = path.basenameWithoutExtension(filename);
    final match = RegExp(r'^\s*\[?(\d{1,3})\]?\s*[.、)_-]+').firstMatch(
      basename,
    );
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Future<Map<String, dynamic>> _search(String term) async {
    final uri = searchBaseUri.resolve('soso/fcgi-bin/client_search_cp').replace(
      queryParameters: {
        'p': '1',
        'n': '50',
        'w': term,
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
    return decoded is Map
        ? decoded.cast<String, dynamic>()
        : const <String, dynamic>{};
  }

  Future<String?> _downloadCover(String albumMid) async {
    final directory = cacheDirectory ??
        Directory(
          path.join(
            (await getApplicationSupportDirectory()).path,
            'webdav_metadata',
            'covers',
          ),
        );
    final cover = File(path.join(directory.path, 'qq_${albumMid}_500.jpg'));
    if (await cover.exists() && await cover.length() > 0) {
      return cover.absolute.path;
    }

    final response = await _dio.getUri<List<int>>(
      artworkBaseUri.resolve('T002R500x500M000$albumMid.jpg'),
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
              r'[\[(（【].*?(?:album\s+version|bonus\s+track|version|live|remix|remaster|伴奏|翻唱|现场|版).*?[\])）】]',
              caseSensitive: false,
            ),
            ' ',
          )
          .replaceAll(RegExp(r'[·・‧•]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  static String _primaryTitleSegment(String value) {
    final parenthesis = RegExp(r'[\[(（【]').firstMatch(value)?.start;
    final plus = value.indexOf('+');
    final cutPositions = [
      if (parenthesis != null) parenthesis,
      if (plus >= 0) plus,
    ];
    if (cutPositions.isEmpty) return value;
    cutPositions.sort();
    final segment = value.substring(0, cutPositions.first).trim();
    return segment.isEmpty ? value : segment;
  }

  static bool _isKnownArtist(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isNotEmpty &&
        normalized != webDavUnknownArtist.toLowerCase();
  }

  static bool _containsHan(String value) =>
      RegExp(r'[\u3400-\u9fff]').hasMatch(value);

  static bool _looksRomanized(String value) =>
      !_containsHan(value) &&
      RegExp(r'[a-z]', caseSensitive: false).hasMatch(value) &&
      RegExp(r'[a-z]+(?:\s+[a-z]+){1,}', caseSensitive: false).hasMatch(value);

  static bool _looksLikeCollectionAlbum(String value) => RegExp(
        r'精选|合集|作品集|单曲集|best\s+of|greatest\s+hits|collection',
        caseSensitive: false,
      ).hasMatch(value);

  static int _romanizedSyllableCount(String value) => RegExp(
        r'[a-z]+',
        caseSensitive: false,
      )
          .allMatches(_cleanSearchTerm(value))
          .map((match) => match.group(0)!.toLowerCase())
          .where(
            (word) => !const {
              'album',
              'version',
              'live',
              'remix',
              'remaster',
              'remastered',
              'edit',
            }.contains(word),
          )
          .length;

  static int _hanTitleLength(String value) => value.runes
      .where(
        (rune) =>
            (rune >= 0x3400 && rune <= 0x4dbf) ||
            (rune >= 0x4e00 && rune <= 0x9fff),
      )
      .length;

  static String _artistIdentityKey(String value) =>
      ChineseMetadataNormalizer.key(
        value.replaceAll(
          RegExp(r'[\[(（【].*?[\])）】]'),
          '',
        ),
      );

  static bool _hasEditionMarker(String value) => RegExp(
        r'\b(?:live|remix|remaster|instrumental|cover|dj)\b|伴奏|翻唱|现场|演唱会|网友改编|片段|降调',
        caseSensitive: false,
      ).hasMatch(value);

  static String _comparisonKey(String value) => ChineseMetadataNormalizer.key(
        value.replaceAll(
          RegExp(
            r'[\[(（【]\s*(?:with|feat\.?|ft\.?|featuring)\s+.*?[\])）】]',
            caseSensitive: false,
          ),
          '',
        ),
      );

  static Iterable<String> _titleVariants(String value) sync* {
    final cleaned = _cleanSearchTerm(value);
    if (cleaned.isNotEmpty) yield cleaned;
    for (final part in cleaned.split(RegExp(r'\s+(?:[-–—]|/|：|:)\s+'))) {
      final candidate = part.trim();
      if (candidate.isNotEmpty && candidate != cleaned) yield candidate;
    }
  }

  static double _titleDistance(String left, String right) {
    var best = 1.0;
    for (final leftVariant in _titleVariants(left)) {
      for (final rightVariant in _titleVariants(right)) {
        best = math.min(best, _stringDistance(leftVariant, rightVariant));
      }
    }
    return best;
  }

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
        current[column] = math.min(
          math.min(current[column - 1] + 1, previous[column] + 1),
          substitution,
        );
      }
      previous = current;
    }
    return previous.last / math.max(a.length, b.length);
  }
}

class _QqArtist {
  final String? mid;
  final String name;

  const _QqArtist({required this.mid, required this.name});
}

class _QqCandidate {
  final String songMid;
  final String trackName;
  final List<_QqArtist> artists;
  final String? albumMid;
  final String? albumName;
  final String? releaseDate;
  final int? durationMs;
  final double titleDistance;
  final double artistDistance;
  final bool artistComparable;
  final bool exactArtist;
  final double distance;

  const _QqCandidate({
    required this.songMid,
    required this.trackName,
    required this.artists,
    required this.albumMid,
    required this.albumName,
    required this.releaseDate,
    required this.durationMs,
    required this.titleDistance,
    required this.artistDistance,
    required this.artistComparable,
    required this.exactArtist,
    required this.distance,
  });

  static _QqCandidate? fromJson(
    Map<String, dynamic> json,
    SpotubeLocalTrackObject source, {
    required bool allowCrossScriptTitle,
  }) {
    final songMid = json['songmid'];
    final trackName = json['songname'];
    if (songMid is! String ||
        songMid.isEmpty ||
        trackName is! String ||
        trackName.isEmpty) {
      return null;
    }
    final artists =
        (json['singer'] is List ? json['singer'] as List : const <dynamic>[])
            .whereType<Map>()
            .map((value) => value.cast<String, dynamic>())
            .map(
              (value) => _QqArtist(
                mid: value['mid'] as String?,
                name: value['name'] as String? ?? '',
              ),
            )
            .where((artist) => artist.name.trim().isNotEmpty)
            .toList(growable: false);
    if (artists.isEmpty) return null;

    final expectedArtists = source.artists
        .map((artist) => artist.name)
        .where(WebDavQqMetadataMatcher._isKnownArtist)
        .toList(growable: false);
    final comparableArtists = expectedArtists
        .where(
          (expected) => artists.any(
            (candidate) => webDavUsesComparableWritingSystem(
              expected,
              candidate.name,
            ),
          ),
        )
        .toList(growable: false);
    final artistComparable = comparableArtists.isNotEmpty;
    final artistDistance = !artistComparable
        ? 0.0
        : comparableArtists
                .map(
                  (expected) => artists
                      .where(
                        (candidate) => webDavUsesComparableWritingSystem(
                          expected,
                          candidate.name,
                        ),
                      )
                      .map(
                        (candidate) => WebDavQqMetadataMatcher._stringDistance(
                          expected,
                          candidate.name,
                        ),
                      )
                      .reduce(math.min),
                )
                .reduce((left, right) => left + right) /
            comparableArtists.length;
    final exactArtist = expectedArtists.any(
      (expected) => artists.any(
        (candidate) =>
            WebDavQqMetadataMatcher._artistIdentityKey(expected) ==
            WebDavQqMetadataMatcher._artistIdentityKey(candidate.name),
      ),
    );
    final comparableTitle = webDavUsesComparableWritingSystem(
      source.name,
      trackName,
    );
    final crossScriptTitleMatch = allowCrossScriptTitle &&
        !comparableTitle &&
        exactArtist &&
        WebDavQqMetadataMatcher._looksRomanized(source.name) &&
        WebDavQqMetadataMatcher._romanizedSyllableCount(source.name) ==
            WebDavQqMetadataMatcher._hanTitleLength(trackName);
    final titleDistance = crossScriptTitleMatch
        ? 0.12
        : WebDavQqMetadataMatcher._titleDistance(source.name, trackName);
    var weighted = titleDistance * 0.65;
    var totalWeight = 0.65;
    if (artistComparable) {
      weighted += artistDistance * 0.25;
      totalWeight += 0.25;
    }
    final interval = _intValue(json['interval']);
    final durationMs = interval == null ? null : interval * 1000;
    if (source.durationMs > 0 && durationMs != null) {
      weighted +=
          math.min(1.0, (source.durationMs - durationMs).abs() / 15000) * 0.10;
      totalWeight += 0.10;
    }
    final albumName = json['albumname'] as String?;
    if (albumName != null &&
        albumName.trim().isNotEmpty &&
        source.album.name != webDavUnknownAlbum &&
        !WebDavQqMetadataMatcher._looksLikeCollectionAlbum(
          source.album.name,
        ) &&
        webDavUsesComparableWritingSystem(source.album.name, albumName)) {
      final albumDistance =
          WebDavQqMetadataMatcher._stringDistance(source.album.name, albumName);
      weighted += albumDistance * 0.12;
      totalWeight += 0.12;
    }
    final editionPenalty =
        !WebDavQqMetadataMatcher._hasEditionMarker(source.name) &&
                WebDavQqMetadataMatcher._hasEditionMarker(trackName)
            ? 0.18
            : 0.0;
    final pubtime = _intValue(json['pubtime']);
    final releaseDate = pubtime == null || pubtime <= 0
        ? null
        : _formatDate(
            // QQ stores release timestamps at midnight in China Standard
            // Time. Convert from the Unix instant before taking the date.
            DateTime.fromMillisecondsSinceEpoch(pubtime * 1000, isUtc: true)
                .add(const Duration(hours: 8)),
          );
    final albumMid = json['albummid'] as String?;
    return _QqCandidate(
      songMid: songMid,
      trackName: trackName,
      artists: artists,
      albumMid: albumMid?.isEmpty == true ? null : albumMid,
      albumName: albumName,
      releaseDate: releaseDate,
      durationMs: durationMs,
      titleDistance: titleDistance,
      artistDistance: artistDistance,
      artistComparable: artistComparable,
      exactArtist: exactArtist,
      distance: weighted / totalWeight + editionPenalty,
    );
  }

  static int? _intValue(Object? value) => switch (value) {
        num number => number.toInt(),
        String text => int.tryParse(text),
        _ => null,
      };

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
