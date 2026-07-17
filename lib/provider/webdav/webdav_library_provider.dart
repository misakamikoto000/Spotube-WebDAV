import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/models/webdav/webdav_audio_quality.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/provider/lyrics/synced.dart';
import 'package:spotube/provider/webdav/webdav_audio_quality_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/webdav/webdav_account_store.dart';
import 'package:spotube/services/webdav/webdav_audio_quality_probe.dart';
import 'package:spotube/services/webdav/webdav_audio_quality_store.dart';
import 'package:spotube/services/webdav/webdav_alternative_metadata_matcher.dart';
import 'package:spotube/services/webdav/webdav_artist_image_matcher.dart';
import 'package:spotube/services/webdav/webdav_client.dart';
import 'package:spotube/services/webdav/chinese_metadata_normalizer.dart';
import 'package:spotube/services/webdav/webdav_library_store.dart';
import 'package:spotube/services/webdav/webdav_metadata_matcher.dart';
import 'package:spotube/services/webdav/webdav_metadata_status.dart';
import 'package:spotube/services/webdav/webdav_qq_metadata_matcher.dart';
import 'package:spotube/utils/platform.dart';

String webDavLibraryLocationKey(String accountId) => 'webdav://$accountId';

enum WebDavTrackRematchTarget { information, cover, lyrics }

class WebDavMetadataScrapeSummary {
  final int matched;
  final int unmatched;
  final int lyricsCached;
  final int failed;

  const WebDavMetadataScrapeSummary({
    required this.matched,
    required this.unmatched,
    required this.lyricsCached,
    required this.failed,
  });
}

class WebDavArtistImageMatchSummary {
  final int matched;
  final int unmatched;
  final int failed;

  const WebDavArtistImageMatchSummary({
    required this.matched,
    required this.unmatched,
    required this.failed,
  });
}

class _WebDavTrackScrapeResult {
  final int index;
  final SpotubeLocalTrackObject track;
  final int matched;
  final int unmatched;
  final int lyricsCached;
  final int failed;

  const _WebDavTrackScrapeResult({
    required this.index,
    required this.track,
    this.matched = 0,
    this.unmatched = 0,
    this.lyricsCached = 0,
    this.failed = 0,
  });
}

class _WebDavCatalogAttempt {
  final WebDavMetadataMatch? result;
  final bool allSourcesFailed;

  const _WebDavCatalogAttempt({
    required this.result,
    required this.allSourcesFailed,
  });
}

enum WebDavMetadataJobPhase { matching, completed, failed }

class WebDavMetadataJobState {
  final WebDavMetadataJobPhase phase;
  final int completed;
  final int total;
  final WebDavMetadataScrapeSummary? summary;
  final String? error;

  const WebDavMetadataJobState({
    required this.phase,
    required this.completed,
    required this.total,
    this.summary,
    this.error,
  });

  bool get isMatching => phase == WebDavMetadataJobPhase.matching;
}

final webDavMetadataJobProvider =
    StateProvider<Map<String, WebDavMetadataJobState>>((ref) => const {});

final webDavUnmatchedFilterRequestProvider =
    StateProvider<Set<String>>((ref) => const {});

class WebDavLibraryNotifier
    extends Notifier<Map<String, List<SpotubeLocalTrackObject>>> {
  // Mobile networks spend most of their time waiting on remote catalogs.
  // A small worker pool keeps the pipeline full without flooding providers.
  // Desktop has more CPU, memory and connection headroom than Android. Keep
  // mobile at the proven values while letting Windows fill network idle time
  // and perform fewer full-library SharedPreferences writes.
  static int get _metadataConcurrency => kIsWindows ? 8 : 6;
  static int get _metadataCheckpointSize => kIsWindows ? 48 : 24;
  static int get _metadataProgressStep => kIsWindows ? 4 : 2;
  static int get _qualityProbeConcurrency => kIsWindows ? 10 : 4;
  static final _cjkPattern = RegExp(r'[\u3400-\u9fff]');

  @override
  Map<String, List<SpotubeLocalTrackObject>> build() {
    return WebDavLibraryStore.tracksByAccount;
  }

  Future<List<SpotubeLocalTrackObject>> scan(WebDavAccount account) async {
    final client = WebDavClient(account);
    try {
      final entries = await client.scanRecursively();
      final existingByPath = {
        for (final track
            in state[account.id] ?? const <SpotubeLocalTrackObject>[])
          track.path: track,
      };
      final tracks = entries.map((entry) {
        final scanned = entry.toTrack(account);
        final existing = existingByPath[scanned.path];
        return existing != null && webDavTrackHasMatchedMetadata(existing)
            ? existing
            : scanned;
      }).toList(growable: false);
      await WebDavLibraryStore.save(account.id, tracks);
      state = WebDavLibraryStore.tracksByAccount;
      await _refreshAudioQualities(account, entries);
      return tracks;
    } finally {
      client.close();
    }
  }

  Future<void> _refreshAudioQualities(
    WebDavAccount account,
    List<WebDavEntry> entries,
  ) async {
    final activePaths = entries.map((entry) => entry.uri.toString()).toSet();
    final pending = entries
        .where(
          (entry) => !(WebDavAudioQualityStore.get(entry.uri.toString())
                  ?.matches(entry) ??
              false),
        )
        .toList(growable: false);

    if (pending.isNotEmpty) {
      final probe = WebDavAudioQualityProbe(account);
      final results = List<WebDavAudioQualityCacheEntry?>.filled(
        pending.length,
        null,
      );
      var nextIndex = 0;

      Future<void> runWorker() async {
        while (true) {
          final index = nextIndex++;
          if (index >= pending.length) return;
          final entry = pending[index];
          try {
            final quality = await probe.probe(entry);
            results[index] = WebDavAudioQualityCacheEntry.fromProbe(
              accountId: account.id,
              entry: entry,
              quality: quality,
            );
          } catch (error, stackTrace) {
            // A transient download error should be retried on the next scan,
            // so do not create a negative cache entry for exceptions.
            AppLogger.reportError(error, stackTrace);
          }
        }
      }

      try {
        final workers = pending.length < _qualityProbeConcurrency
            ? pending.length
            : _qualityProbeConcurrency;
        await Future.wait([
          for (var worker = 0; worker < workers; worker++) runWorker(),
        ]);
      } finally {
        probe.close();
      }
      await WebDavAudioQualityStore.upsertAll(results.whereType());
    }

    await WebDavAudioQualityStore.pruneAccount(account.id, activePaths);
    ref.read(webDavAudioQualityProvider.notifier).state =
        WebDavAudioQualityStore.qualitiesByPath;
  }

  Future<WebDavArtistImageMatchSummary> matchArtistImages({
    WebDavArtistImageMatcher? imageMatcher,
  }) async {
    final matcher = imageMatcher ?? WebDavArtistImageMatcher();
    final ownsMatcher = imageMatcher == null;
    final knownImages = <String, List<SpotubeImageObject>>{};
    final pendingArtists = <String, SpotubeSimpleArtistObject>{};
    final requested = <String>{};
    final matched = <String>{};
    final failed = <String>{};

    for (final tracks in state.values) {
      for (final track in tracks) {
        for (final artist in [...track.artists, ...track.album.artists]) {
          final key = _artistKey(artist);
          if (key == null) continue;
          if (artist.images?.isNotEmpty == true) {
            knownImages[key] = artist.images!;
          } else {
            requested.add(key);
            pendingArtists.putIfAbsent(key, () => artist);
          }
        }
      }
    }

    try {
      for (final key in knownImages.keys.where(requested.contains)) {
        pendingArtists.remove(key);
        matched.add(key);
      }
      final artists = pendingArtists.entries.toList(growable: false);
      var nextArtist = 0;

      Future<void> runArtistWorker() async {
        while (true) {
          final index = nextArtist++;
          if (index >= artists.length) return;
          final entry = artists[index];
          try {
            final enriched = await matcher.enrichArtist(entry.value);
            if (enriched.images?.isNotEmpty == true) {
              knownImages[entry.key] = enriched.images!;
              matched.add(entry.key);
            }
          } catch (error, stackTrace) {
            failed.add(entry.key);
            AppLogger.reportError(error, stackTrace);
          }
        }
      }

      final workerCount = artists.length < _metadataConcurrency
          ? artists.length
          : _metadataConcurrency;
      await Future.wait([
        for (var worker = 0; worker < workerCount; worker++) runArtistWorker(),
      ]);

      for (final entry in state.entries) {
        final tracks = entry.value.toList(growable: true);
        var changed = false;
        for (var index = 0; index < tracks.length; index++) {
          final original = tracks[index];
          final updated = _applyKnownArtistImages(
            original,
            knownImages,
          );
          if (updated != original) {
            tracks[index] = updated;
            changed = true;
          }
        }
        if (changed) await WebDavLibraryStore.save(entry.key, tracks);
      }
      state = WebDavLibraryStore.tracksByAccount;
    } finally {
      if (ownsMatcher) matcher.close();
    }

    return WebDavArtistImageMatchSummary(
      matched: matched.length,
      unmatched: requested.difference(matched).difference(failed).length,
      failed: failed.difference(matched).length,
    );
  }

  Future<WebDavMetadataScrapeSummary> matchMetadata(
    WebDavAccount account, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final storedTracks = state[account.id];
    if (storedTracks == null || storedTracks.isEmpty) {
      throw StateError('Scan this WebDAV library before matching metadata.');
    }

    final tracks = storedTracks.toList(growable: true);
    final musicBrainzMatcher = WebDavMetadataMatcher();
    final alternativeMatcher = WebDavAlternativeMetadataMatcher();
    final qqMatcher = WebDavQqMetadataMatcher();
    final artistImageMatcher = WebDavArtistImageMatcher();
    var matched = 0;
    var unmatched = 0;
    var lyricsCached = 0;
    var failed = 0;
    var processed = 0;

    void reportProgress(int completed) {
      processed = completed;
      _setMetadataJob(
        account.id,
        WebDavMetadataJobState(
          phase: WebDavMetadataJobPhase.matching,
          completed: completed,
          total: tracks.length,
        ),
      );
      onProgress?.call(completed, tracks.length);
    }

    reportProgress(0);

    try {
      try {
        var nextIndex = 0;
        var completed = 0;

        Future<void> runWorker() async {
          while (true) {
            final index = nextIndex++;
            if (index >= tracks.length) return;
            final result = await _scrapeTrack(
              index: index,
              sourceTrack: tracks[index],
              account: account,
              musicBrainzMatcher: musicBrainzMatcher,
              alternativeMatcher: alternativeMatcher,
              qqMatcher: qqMatcher,
              artistImageMatcher: artistImageMatcher,
            );
            tracks[result.index] = result.track;
            matched += result.matched;
            unmatched += result.unmatched;
            lyricsCached += result.lyricsCached;
            failed += result.failed;

            completed++;
            if (completed == tracks.length ||
                completed % _metadataProgressStep == 0) {
              reportProgress(completed);
            }

            // SharedPreferences serializes the complete WebDAV library on
            // every write. Sparse checkpoints retain interrupted progress
            // without repeatedly encoding a large Android library.
            if (completed < tracks.length &&
                completed % _metadataCheckpointSize == 0) {
              await _persistWorkingTracks(
                account.id,
                tracks,
                publish: false,
              );
            }
          }
        }

        final workerCount = tracks.length < _metadataConcurrency
            ? tracks.length
            : _metadataConcurrency;
        await Future.wait([
          for (var worker = 0; worker < workerCount; worker++) runWorker(),
        ]);
        final reconciled = await _reconcileNumberedQqAlbums(
          tracks,
          qqMatcher,
        );
        matched += reconciled;
        unmatched -= reconciled;
        if (unmatched < 0) unmatched = 0;
      } finally {
        musicBrainzMatcher.close();
        alternativeMatcher.close();
        qqMatcher.close();
        artistImageMatcher.close();
      }

      await _persistWorkingTracks(account.id, tracks);
      final summary = WebDavMetadataScrapeSummary(
        matched: matched,
        unmatched: unmatched,
        lyricsCached: lyricsCached,
        failed: failed,
      );
      _setMetadataJob(
        account.id,
        WebDavMetadataJobState(
          phase: WebDavMetadataJobPhase.completed,
          completed: tracks.length,
          total: tracks.length,
          summary: summary,
        ),
      );
      return summary;
    } catch (error) {
      _setMetadataJob(
        account.id,
        WebDavMetadataJobState(
          phase: WebDavMetadataJobPhase.failed,
          completed: processed,
          total: tracks.length,
          error: error.toString(),
        ),
      );
      rethrow;
    }
  }

  Future<WebDavMetadataScrapeSummary> rematchUnmatchedMetadata(
    WebDavAccount account, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final storedTracks = state[account.id];
    if (storedTracks == null || storedTracks.isEmpty) {
      throw StateError('Scan this WebDAV library before matching metadata.');
    }

    final tracks = storedTracks.toList(growable: true);
    final targetIndexes = <int>[
      for (var index = 0; index < tracks.length; index++)
        if (!webDavTrackHasMatchedMetadata(tracks[index])) index,
    ];
    final matcher = WebDavAlternativeMetadataMatcher();
    final qqMatcher = WebDavQqMetadataMatcher();
    final artistImageMatcher = WebDavArtistImageMatcher();
    var matched = 0;
    var unmatched = 0;
    var lyricsCached = 0;
    var failed = 0;
    var processed = 0;

    void reportProgress(int completed) {
      processed = completed;
      _setMetadataJob(
        account.id,
        WebDavMetadataJobState(
          phase: WebDavMetadataJobPhase.matching,
          completed: completed,
          total: targetIndexes.length,
        ),
      );
      onProgress?.call(completed, targetIndexes.length);
    }

    reportProgress(0);
    try {
      try {
        var nextPosition = 0;
        var completed = 0;

        Future<void> runWorker() async {
          while (true) {
            final position = nextPosition++;
            if (position >= targetIndexes.length) return;
            final index = targetIndexes[position];
            final result = await _scrapeTrack(
              index: index,
              sourceTrack: tracks[index],
              account: account,
              alternativeMatcher: matcher,
              qqMatcher: qqMatcher,
              artistImageMatcher: artistImageMatcher,
            );
            tracks[result.index] = result.track;
            matched += result.matched;
            unmatched += result.unmatched;
            lyricsCached += result.lyricsCached;
            failed += result.failed;

            completed++;
            if (completed == targetIndexes.length ||
                completed % _metadataProgressStep == 0) {
              reportProgress(completed);
            }
            if (completed < targetIndexes.length &&
                completed % _metadataCheckpointSize == 0) {
              await _persistWorkingTracks(
                account.id,
                tracks,
                publish: false,
              );
            }
          }
        }

        final workerCount = targetIndexes.length < _metadataConcurrency
            ? targetIndexes.length
            : _metadataConcurrency;
        await Future.wait([
          for (var worker = 0; worker < workerCount; worker++) runWorker(),
        ]);
        final reconciled = await _reconcileNumberedQqAlbums(
          tracks,
          qqMatcher,
        );
        matched += reconciled;
        unmatched -= reconciled;
        if (unmatched < 0) unmatched = 0;
      } finally {
        matcher.close();
        qqMatcher.close();
        artistImageMatcher.close();
      }

      await _persistWorkingTracks(account.id, tracks);
      final summary = WebDavMetadataScrapeSummary(
        matched: matched,
        unmatched: unmatched,
        lyricsCached: lyricsCached,
        failed: failed,
      );
      _setMetadataJob(
        account.id,
        WebDavMetadataJobState(
          phase: WebDavMetadataJobPhase.completed,
          completed: targetIndexes.length,
          total: targetIndexes.length,
          summary: summary,
        ),
      );
      return summary;
    } catch (error) {
      _setMetadataJob(
        account.id,
        WebDavMetadataJobState(
          phase: WebDavMetadataJobPhase.failed,
          completed: processed,
          total: targetIndexes.length,
          error: error.toString(),
        ),
      );
      rethrow;
    }
  }

  Future<_WebDavTrackScrapeResult> _scrapeTrack({
    required int index,
    required SpotubeLocalTrackObject sourceTrack,
    required WebDavAccount account,
    required WebDavAlternativeMetadataMatcher alternativeMatcher,
    required WebDavQqMetadataMatcher qqMatcher,
    required WebDavArtistImageMatcher artistImageMatcher,
    WebDavMetadataMatcher? musicBrainzMatcher,
  }) async {
    var source = sourceTrack;
    final metadataWasAlreadyMatched = webDavTrackHasMatchedMetadata(source);
    if (!metadataWasAlreadyMatched) {
      source = _refreshInferredMetadata(source, account);
    }

    try {
      WebDavMetadataMatch? metadataMatch;
      if (!metadataWasAlreadyMatched) {
        final attempt = await _matchFromCatalogs(
          source,
          alternativeMatcher: alternativeMatcher,
          qqMatcher: qqMatcher,
          musicBrainzMatcher: musicBrainzMatcher,
        );
        metadataMatch = attempt.result;
        if (metadataMatch == null) {
          return _WebDavTrackScrapeResult(
            index: index,
            track: source,
            unmatched: attempt.allSourcesFailed ? 0 : 1,
            failed: attempt.allSourcesFailed ? 1 : 0,
          );
        }
      }

      final matchedTrack = metadataMatch?.track ?? source;
      SpotubeLocalTrackObject? lyricsFallbackTrack;
      if (metadataMatch != null &&
          (matchedTrack.name != source.name ||
              matchedTrack.artists.map((artist) => artist.name).join() !=
                  source.artists.map((artist) => artist.name).join())) {
        // Catalogs can use a different Chinese spelling than the filename.
        // Keep the selected metadata but let LRCLIB retry the source spelling.
        lyricsFallbackTrack = matchedTrack.copyWith(
          name: source.name,
          artists: source.artists,
        );
      }

      // Artist artwork and lyrics are independent network operations. Starting
      // both before awaiting either removes a full round trip from every track.
      final artistFuture = _enrichArtistSafely(
        artistImageMatcher,
        matchedTrack,
      );
      final lyricsFuture = _cacheLyricsWithFallback(
        matchedTrack,
        lyricsFallbackTrack,
      );
      final enrichedTrack = await artistFuture;
      final hasLyrics = await lyricsFuture;

      return _WebDavTrackScrapeResult(
        index: index,
        track: enrichedTrack,
        matched: metadataMatch != null || enrichedTrack != source ? 1 : 0,
        lyricsCached: hasLyrics ? 1 : 0,
      );
    } catch (error, stackTrace) {
      AppLogger.reportError(error, stackTrace);
      return _WebDavTrackScrapeResult(
        index: index,
        track: source,
        failed: 1,
      );
    }
  }

  Future<_WebDavCatalogAttempt> _matchFromCatalogs(
    SpotubeLocalTrackObject source, {
    required WebDavAlternativeMetadataMatcher alternativeMatcher,
    required WebDavQqMetadataMatcher qqMatcher,
    WebDavMetadataMatcher? musicBrainzMatcher,
  }) async {
    final calls = <Future<WebDavMetadataMatch?> Function()>[];
    if (_prefersQq(source)) {
      calls
        ..add(() => qqMatcher.match(source))
        ..add(() => alternativeMatcher.match(source));
    } else {
      calls
        ..add(() => alternativeMatcher.match(source))
        ..add(() => qqMatcher.match(source));
    }
    if (musicBrainzMatcher != null) {
      calls.add(() => musicBrainzMatcher.match(source));
    }

    var completedSources = 0;
    for (final call in calls) {
      try {
        final result = await call();
        completedSources++;
        if (result != null) {
          return _WebDavCatalogAttempt(
            result: result,
            allSourcesFailed: false,
          );
        }
      } catch (error, stackTrace) {
        // One unreachable catalog should not block the remaining fallbacks.
        AppLogger.reportError(error, stackTrace);
      }
    }
    return _WebDavCatalogAttempt(
      result: null,
      allSourcesFailed: completedSources == 0,
    );
  }

  Future<SpotubeLocalTrackObject> _enrichArtistSafely(
    WebDavArtistImageMatcher matcher,
    SpotubeLocalTrackObject track,
  ) async {
    try {
      return await matcher.enrich(track);
    } catch (error, stackTrace) {
      // Artist portraits are optional and must not discard song metadata.
      AppLogger.reportError(error, stackTrace);
      return track;
    }
  }

  Future<bool> _cacheLyricsWithFallback(
    SpotubeLocalTrackObject track,
    SpotubeLocalTrackObject? fallback,
  ) async {
    if (await _cacheLyrics(track)) return true;
    return fallback != null && await _cacheLyrics(fallback);
  }

  Future<void> _persistWorkingTracks(
    String accountId,
    List<SpotubeLocalTrackObject> tracks, {
    bool publish = true,
  }) async {
    await WebDavLibraryStore.save(accountId, tracks);
    if (publish) state = WebDavLibraryStore.tracksByAccount;
  }

  Future<int> _reconcileNumberedQqAlbums(
    List<SpotubeLocalTrackObject> tracks,
    WebDavQqMetadataMatcher matcher,
  ) async {
    final indexesByDirectory = <String, List<int>>{};
    for (var index = 0; index < tracks.length; index++) {
      final uri = Uri.tryParse(tracks[index].path);
      if (uri == null || uri.pathSegments.isEmpty) continue;
      final directory = uri.resolve('.').toString();
      indexesByDirectory.putIfAbsent(directory, () => []).add(index);
    }

    var newlyMatched = 0;
    for (final indexes in indexesByDirectory.values) {
      if (indexes.length < 2) continue;
      final sourceTracks = [for (final index in indexes) tracks[index]];
      try {
        final reconciled = await matcher.reconcileNumberedAlbum(sourceTracks);
        if (reconciled == null) continue;
        for (var position = 0; position < indexes.length; position++) {
          final index = indexes[position];
          final wasMatched = webDavTrackHasMatchedMetadata(tracks[index]);
          final updated = reconciled[position];
          if (!wasMatched && webDavTrackHasMatchedMetadata(updated)) {
            newlyMatched++;
          }
          tracks[index] = updated;
        }
      } catch (error, stackTrace) {
        // Album-order reconciliation is a high-confidence fallback. A
        // transient album endpoint failure must not discard per-track matches.
        AppLogger.reportError(error, stackTrace);
      }
    }
    return newlyMatched;
  }

  static bool _prefersQq(SpotubeLocalTrackObject track) {
    final searchable = [
      track.name,
      ...track.artists.map((artist) => artist.name),
    ].join(' ');
    return _cjkPattern.hasMatch(searchable);
  }

  Future<bool> rematchTrack(
    SpotubeLocalTrackObject requestedTrack,
    WebDavTrackRematchTarget target,
  ) async {
    if (target == WebDavTrackRematchTarget.lyrics) {
      final lyrics = await ref
          .read(syncedLyricsProvider(requestedTrack).notifier)
          .refreshLyrics();
      return lyrics.lyrics.isNotEmpty;
    }

    final accountId = requestedTrack.webDavAccountId;
    if (accountId == null) return false;
    final account = WebDavAccountStore.getById(accountId);
    if (account == null) {
      throw StateError('This WebDAV account no longer exists.');
    }
    final tracks = state[accountId]?.toList(growable: true);
    if (tracks == null) return false;
    final index = tracks.indexWhere(
      (track) => track.path == requestedTrack.path,
    );
    if (index == -1) return false;

    final current = tracks[index];
    final coverOnly = target == WebDavTrackRematchTarget.cover;
    final source = coverOnly
        ? current.copyWith(
            album: current.album.copyWith(images: const []),
          )
        : _refreshInferredMetadata(current, account);
    final matched = await _matchSingleTrack(
      source,
      requireCover: coverOnly,
    );
    if (matched == null) return false;

    tracks[index] = coverOnly
        ? current.copyWith(
            album: current.album.copyWith(images: matched.track.album.images),
          )
        : matched.track;
    await WebDavLibraryStore.save(accountId, tracks);
    state = WebDavLibraryStore.tracksByAccount;
    return true;
  }

  Future<void> remove(String accountId) async {
    await WebDavLibraryStore.remove(accountId);
    await WebDavAudioQualityStore.removeAccount(accountId);
    state = WebDavLibraryStore.tracksByAccount;
    ref.read(webDavAudioQualityProvider.notifier).state =
        WebDavAudioQualityStore.qualitiesByPath;
    final jobs = ref.read(webDavMetadataJobProvider.notifier);
    jobs.state = Map.of(jobs.state)..remove(accountId);
  }

  Future<bool> _cacheLyrics(SpotubeLocalTrackObject track) async {
    try {
      ref.invalidate(syncedLyricsProvider(track));
      await ref.read(syncedLyricsProvider(track).future);
      return true;
    } catch (_) {
      // Missing lyrics are common and should not discard valid metadata.
      return false;
    }
  }

  Future<WebDavMetadataMatch?> _matchSingleTrack(
    SpotubeLocalTrackObject source, {
    required bool requireCover,
  }) async {
    final itunes = WebDavAlternativeMetadataMatcher();
    final qq = WebDavQqMetadataMatcher();
    final musicBrainz = WebDavMetadataMatcher();
    final sources = <Future<WebDavMetadataMatch?> Function()>[
      () => itunes.match(source),
      () => qq.match(source),
      () => musicBrainz.match(source),
    ];
    try {
      for (final match in sources) {
        try {
          final result = await match();
          if (result != null &&
              (!requireCover || result.track.album.images.isNotEmpty)) {
            return result;
          }
        } catch (error, stackTrace) {
          AppLogger.reportError(error, stackTrace);
        }
      }
      return null;
    } finally {
      itunes.close();
      qq.close();
      musicBrainz.close();
    }
  }

  void _setMetadataJob(String accountId, WebDavMetadataJobState job) {
    final notifier = ref.read(webDavMetadataJobProvider.notifier);
    notifier.state = {...notifier.state, accountId: job};
  }

  static SpotubeLocalTrackObject _refreshInferredMetadata(
    SpotubeLocalTrackObject track,
    WebDavAccount account,
  ) {
    final uri = Uri.tryParse(track.path);
    if (uri == null || !account.contains(uri)) return track;
    final pathSegments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (pathSegments.isEmpty) return track;

    final inferred = WebDavEntry(
      uri: uri,
      displayName: pathSegments.last,
      isDirectory: false,
    ).toTrack(account);
    return inferred.copyWith(
      durationMs: track.durationMs > 0 ? track.durationMs : inferred.durationMs,
    );
  }

  static String? _artistKey(SpotubeSimpleArtistObject artist) {
    if (artist.name.trim().isEmpty || artist.name == webDavUnknownArtist) {
      return null;
    }
    final key = ChineseMetadataNormalizer.key(artist.name);
    return key.isEmpty ? null : key;
  }

  static SpotubeLocalTrackObject _applyKnownArtistImages(
    SpotubeLocalTrackObject track,
    Map<String, List<SpotubeImageObject>> knownImages,
  ) {
    SpotubeSimpleArtistObject apply(SpotubeSimpleArtistObject artist) {
      if (artist.images?.isNotEmpty == true) return artist;
      final key = _artistKey(artist);
      final images = key == null ? null : knownImages[key];
      return images == null ? artist : artist.copyWith(images: images);
    }

    return track.copyWith(
      artists: track.artists.map(apply).toList(growable: false),
      album: track.album.copyWith(
        artists: track.album.artists.map(apply).toList(growable: false),
      ),
    );
  }
}

final webDavLibraryProvider = NotifierProvider<WebDavLibraryNotifier,
    Map<String, List<SpotubeLocalTrackObject>>>(
  WebDavLibraryNotifier.new,
);
