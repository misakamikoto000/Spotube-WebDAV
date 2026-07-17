import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lrc/lrc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/services/dio/dio.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/webdav/chinese_metadata_normalizer.dart';

class LrclibLyricsClient {
  final Dio dio;
  final Uri baseUri;
  final String userAgent;

  LrclibLyricsClient({
    required this.dio,
    required this.userAgent,
    Uri? baseUri,
  }) : baseUri = baseUri ?? Uri.parse('https://lrclib.net');

  Future<SubtitleSimple> getLyrics(SpotubeTrackObject track) async {
    final artist = track.artists.isEmpty
        ? ''
        : ChineseMetadataNormalizer.simplify(track.artists.first.name);
    final title = ChineseMetadataNormalizer.simplify(track.name);
    final album = ChineseMetadataNormalizer.simplify(track.album.name);
    final exactUri = baseUri.resolve('/api/get').replace(
      queryParameters: {
        'artist_name': artist,
        'track_name': title,
        if (_isKnownAlbum(album)) 'album_name': album,
        if (track.durationMs > 0)
          'duration': (track.durationMs / 1000).round().toString(),
      },
    );
    final exact = await _get(exactUri);
    if (exact.statusCode == 200 && exact.data is Map) {
      final parsed = _parseLyrics(
        (exact.data as Map).cast<String, dynamic>(),
        track,
        exact.realUri,
      );
      if (parsed != null) return parsed;
    }

    final titleAliases = <String>{title, _cleanTitle(title)}
      ..removeWhere((value) => value.isEmpty);
    Uri lastSearchUri = baseUri.resolve('/api/search');
    for (final searchTitle in titleAliases) {
      final searchUri = baseUri.resolve('/api/search').replace(
        queryParameters: {
          'track_name': searchTitle,
          if (_isKnownArtist(artist)) 'artist_name': artist,
        },
      );
      final search = await _get(searchUri);
      lastSearchUri = search.realUri;
      if (search.statusCode == 200 && search.data is List) {
        final candidates = (search.data as List)
            .whereType<Map>()
            .map((value) => value.cast<String, dynamic>())
            .map(
              (value) => (
                value: value,
                score: _score(value, track, titleAliases: titleAliases),
              ),
            )
            .where((candidate) => candidate.score >= 0)
            .toList(growable: false)
          ..sort((left, right) => right.score.compareTo(left.score));
        for (final candidate in candidates) {
          final parsed = _parseLyrics(
            candidate.value,
            track,
            search.realUri,
          );
          if (parsed != null) return parsed;
        }
      }
    }

    return SubtitleSimple(
      lyrics: const [],
      name: track.name,
      uri: lastSearchUri,
      rating: 0,
      provider: 'LRCLib',
    );
  }

  Future<Response<dynamic>> _get(Uri uri) => dio.getUri<dynamic>(
        uri,
        options: Options(
          headers: {'User-Agent': userAgent},
          responseType: ResponseType.json,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

  static SubtitleSimple? _parseLyrics(
    Map<String, dynamic> json,
    SpotubeTrackObject track,
    Uri uri,
  ) {
    final syncedRaw = json['syncedLyrics'];
    if (syncedRaw is String && syncedRaw.trim().isNotEmpty) {
      try {
        final lyrics = Lrc.parse(syncedRaw)
            .lyrics
            .map(LyricSlice.fromLrcLine)
            .where((line) => line.text.trim().isNotEmpty)
            .map(
              (line) => LyricSlice(
                time: line.time,
                text: ChineseMetadataNormalizer.simplify(line.text),
              ),
            )
            .toList(growable: false);
        if (lyrics.isNotEmpty) {
          return SubtitleSimple(
            lyrics: lyrics,
            name: track.name,
            uri: uri,
            rating: 100,
            provider: 'LRCLib',
          );
        }
      } catch (_) {
        // A malformed synchronized payload can still have valid plain lyrics.
      }
    }

    final plainRaw = json['plainLyrics'];
    if (plainRaw is! String || plainRaw.trim().isEmpty) return null;
    final lyrics = plainRaw
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .map(
          (line) => LyricSlice(
            text: ChineseMetadataNormalizer.simplify(line),
            time: Duration.zero,
          ),
        )
        .toList(growable: false);
    if (lyrics.isEmpty) return null;
    return SubtitleSimple(
      lyrics: lyrics,
      name: track.name,
      uri: uri,
      rating: 50,
      provider: 'LRCLib',
    );
  }

  static double _score(
    Map<String, dynamic> candidate,
    SpotubeTrackObject track, {
    required Set<String> titleAliases,
  }) {
    final candidateTitle = candidate['trackName'] ?? candidate['name'];
    if (candidateTitle is! String) return -1;
    final candidateAliases = <String>{
      candidateTitle,
      _cleanTitle(candidateTitle),
    }..removeWhere((value) => value.isEmpty);
    final titleSimilarity = titleAliases
        .expand(
          (expected) => candidateAliases.map(
            (actual) => _similarity(expected, actual),
          ),
        )
        .reduce(math.max);
    if (titleSimilarity < 0.55) return -1;

    final expectedArtist =
        track.artists.isEmpty ? '' : track.artists.first.name;
    final candidateArtist = candidate['artistName'];
    final artistSimilarity = candidateArtist is String
        ? _similarity(expectedArtist, candidateArtist)
        : 0.0;
    if (_isKnownArtist(expectedArtist) && artistSimilarity < 0.40) return -1;

    var score = titleSimilarity * 60 + artistSimilarity * 25;
    final candidateAlbum = candidate['albumName'];
    if (_isKnownAlbum(track.album.name) && candidateAlbum is String) {
      score += _similarity(track.album.name, candidateAlbum) * 10;
    }
    final duration = candidate['duration'];
    if (track.durationMs > 0 && duration is num) {
      final difference = (track.durationMs / 1000 - duration.toDouble()).abs();
      if (difference <= 3) {
        score += 15;
      } else if (difference <= 10) {
        score += 5;
      }
    }
    return score;
  }

  static String _cleanTitle(String value) => value
      .replaceAll(
        RegExp(
          r'\s*[\[(（【]\s*(?:(?:with|feat\.?|ft\.?|featuring)\s+|(?:live|remix|remaster|伴奏|翻唱|现场|演唱会|版)\b).*?[\])）】]',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static double _similarity(String left, String right) {
    final a = ChineseMetadataNormalizer.key(left).runes.toList(growable: false);
    final b =
        ChineseMetadataNormalizer.key(right).runes.toList(growable: false);
    if (a.isEmpty && b.isEmpty) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    if (a.length <= b.length && _containsRunes(b, a)) {
      return a.length / b.length;
    }
    if (b.length <= a.length && _containsRunes(a, b)) {
      return b.length / a.length;
    }

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
    final maximum = a.length > b.length ? a.length : b.length;
    return 1 - previous.last / maximum;
  }

  static bool _containsRunes(List<int> haystack, List<int> needle) {
    for (var start = 0; start <= haystack.length - needle.length; start++) {
      var matches = true;
      for (var index = 0; index < needle.length; index++) {
        if (haystack[start + index] != needle[index]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }

  static bool _isKnownArtist(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isNotEmpty && normalized != 'unknown artist';
  }

  static bool _isKnownAlbum(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isNotEmpty && normalized != 'unknown album';
  }
}

class SyncedLyricsNotifier
    extends FamilyAsyncNotifier<SubtitleSimple, SpotubeTrackObject?> {
  SpotubeTrackObject get _track => arg!;

  /// Lyrics credits: [lrclib.net](https://lrclib.net) and their contributors
  /// Thanks for their generous public API
  Future<SubtitleSimple> getLRCLibLyrics() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return LrclibLyricsClient(
      dio: globalDio,
      userAgent:
          'Spotube v${packageInfo.version} (https://github.com/KRTirtho/spotube)',
    ).getLyrics(_track);
  }

  /// Ignores the current cache, fetches again, and only replaces the cached
  /// lyrics after a valid result has been found.
  Future<SubtitleSimple> refreshLyrics() async {
    state = const AsyncLoading();
    try {
      final lyrics = await getLRCLibLyrics();
      if (lyrics.lyrics.isEmpty) {
        throw Exception('Unable to find lyrics');
      }
      await _replaceCache(lyrics);
      state = AsyncData(lyrics);
      return lyrics;
    } catch (error, stackTrace) {
      AppLogger.reportError(error, stackTrace);
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  @override
  FutureOr<SubtitleSimple> build(track) async {
    try {
      final database = ref.watch(databaseProvider);

      if (track == null) {
        throw "No track currently";
      }

      final cachedRows = await (database.select(database.lyricsTable)
            ..where((tbl) => tbl.trackId.equals(track.id))
            ..orderBy([(tbl) => OrderingTerm.desc(tbl.id)]))
          .get();
      final cachedLyrics = cachedRows.firstOrNull?.data;
      final normalizedCache =
          cachedLyrics == null ? null : _simplifyCachedLyrics(cachedLyrics);
      SubtitleSimple? lyrics = normalizedCache?.lyrics;
      var shouldReplaceCache =
          cachedRows.length > 1 || (normalizedCache?.changed ?? false);

      if (lyrics == null || lyrics.lyrics.isEmpty) {
        lyrics = await getLRCLibLyrics();
        shouldReplaceCache = true;
      }

      if (lyrics.lyrics.isEmpty) {
        throw Exception("Unable to find lyrics");
      }

      if (cachedLyrics == null || shouldReplaceCache) {
        await _replaceCache(lyrics);
      }

      return lyrics;
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace);
      rethrow;
    }
  }

  Future<void> _replaceCache(SubtitleSimple lyrics) async {
    final database = ref.read(databaseProvider);
    await database.transaction(() async {
      await (database.delete(database.lyricsTable)
            ..where((tbl) => tbl.trackId.equals(_track.id)))
          .go();
      await database.into(database.lyricsTable).insert(
            LyricsTableCompanion.insert(
              trackId: _track.id,
              data: lyrics,
            ),
          );
    });
  }

  ({SubtitleSimple lyrics, bool changed}) _simplifyCachedLyrics(
    SubtitleSimple source,
  ) {
    final name = ChineseMetadataNormalizer.simplify(source.name);
    var changed = name != source.name;
    final lines = source.lyrics.map((line) {
      final text = ChineseMetadataNormalizer.simplify(line.text);
      if (text != line.text) changed = true;
      return LyricSlice(time: line.time, text: text);
    }).toList(growable: false);
    return (
      lyrics: SubtitleSimple(
        uri: source.uri,
        name: name,
        lyrics: lines,
        rating: source.rating,
        provider: source.provider,
      ),
      changed: changed,
    );
  }
}

final syncedLyricsDelayProvider = StateProvider<int>((ref) => 0);

final syncedLyricsProvider = AsyncNotifierProviderFamily<SyncedLyricsNotifier,
    SubtitleSimple, SpotubeTrackObject?>(
  () => SyncedLyricsNotifier(),
);

final syncedLyricsMapProvider =
    FutureProvider.family((ref, SpotubeTrackObject? track) async {
  final syncedLyrics = await ref.watch(syncedLyricsProvider(track).future);

  final isStaticLyrics =
      syncedLyrics.lyrics.every((l) => l.time == Duration.zero);

  final lyricsMap = syncedLyrics.lyrics
      .map((lyric) => {lyric.time.inSeconds: lyric.text})
      .reduce((accumulator, lyricSlice) => {...accumulator, ...lyricSlice});

  return (static: isStaticLyrics, lyricsMap: lyricsMap);
});
