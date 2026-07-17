import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/history/top.dart';
import 'package:spotube/provider/history/history_utils.dart';
import 'package:spotube/provider/metadata_plugin/artist/artist.dart';
import 'package:spotube/provider/metadata_plugin/utils/family_paginated.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/webdav/chinese_metadata_normalizer.dart';

typedef PlaybackHistoryTrack = ({int count, SpotubeTrackObject track});
typedef PlaybackHistoryArtist = ({int count, SpotubeSimpleArtistObject artist});

class HistoryTopTracksNotifier extends FamilyPaginatedAsyncNotifier<
    PlaybackHistoryTrack, HistoryDuration> {
  HistoryTopTracksNotifier() : super();

  List<PlaybackHistoryTrack> _allTrackCounts = const [];

  SimpleSelectStatement<$HistoryTableTable, HistoryTableData>
      createTracksQuery() {
    final database = ref.read(databaseProvider);

    return database.select(database.historyTable)
      ..where(
        (tbl) =>
            tbl.type.equalsValue(HistoryEntryType.track) &
            tbl.createdAt.isBiggerOrEqualValue(switch (arg) {
              HistoryDuration.allTime => DateTime(1970),
              // from start of the week
              HistoryDuration.days7 => DateTime.now()
                  .subtract(Duration(days: DateTime.now().weekday - 1)),
              // from start of the month
              HistoryDuration.days30 =>
                DateTime.now().subtract(Duration(days: DateTime.now().day - 1)),
              // from start of the 6th month
              HistoryDuration.months6 => DateTime.now()
                  .subtract(Duration(days: DateTime.now().day - 1))
                  .subtract(const Duration(days: 30 * 6)),
              // from start of the year
              HistoryDuration.year => DateTime.now()
                  .subtract(Duration(days: DateTime.now().day - 1))
                  .subtract(const Duration(days: 30 * 12)),
              HistoryDuration.years2 => DateTime.now()
                  .subtract(Duration(days: DateTime.now().day - 1))
                  .subtract(const Duration(days: 30 * 12 * 2)),
            }),
      );
  }

  Future<void> fixImageNotLoadingForArtistIssue(
    List<HistoryTableData> entries,
  ) async {
    try {
      final nonImageArtistTracks = entries
          .where((entry) =>
              entry.track!.artists.any((artist) => artist.images == null))
          .toList(growable: false);
      if (nonImageArtistTracks.isEmpty) return;

      // Never consult the online plugin for local/WebDAV entries. For remote
      // entries it is best-effort; album artwork remains a safe fallback.
      final remoteArtistIds = nonImageArtistTracks
          .where((entry) => entry.track is! SpotubeLocalTrackObject)
          .expand((entry) => entry.track!.artists)
          .where((artist) => artist.images == null)
          .map((artist) => artist.id)
          .toSet();
      final artistsById = <String, SpotubeFullArtistObject>{};
      for (final id in remoteArtistIds) {
        try {
          final artist =
              await ref.read(metadataPluginArtistProvider(id).future);
          artistsById[id] = artist;
        } catch (error, stack) {
          AppLogger.reportError(error, stack);
        }
      }

      final imagedArtistTracks = nonImageArtistTracks.map((entry) {
        var track = entry.track!;
        track = track.copyWith(
          artists: track.artists.map((artist) {
            if (artist.images != null) return artist;
            final remoteArtist = artistsById[artist.id];
            return artist.copyWith(
              images: remoteArtist?.images ?? track.album.images,
            );
          }).toList(growable: false),
        );
        return entry.copyWith(data: track.toJson());
      }).toList(growable: false);

      final database = ref.read(databaseProvider);
      await database.batch((batch) {
        batch.insertAllOnConflictUpdate(
          database.historyTable,
          imagedArtistTracks,
        );
      });
    } catch (error, stack) {
      AppLogger.reportError(error, stack);
    }
  }

  @override
  fetch(offset, limit) async {
    final entries = await createTracksQuery().get();
    final allItems = getTracksWithCount(entries);
    _allTrackCounts = allItems;
    final items = allItems.skip(offset).take(limit).toList(growable: false);

    return SpotubePaginationResponseObject<PlaybackHistoryTrack>(
      items: items,
      nextOffset: offset + limit,
      total: allItems.length,
      limit: limit,
      hasMore: offset + items.length < allItems.length,
    );
  }

  @override
  build(arg) async {
    final subscription = createTracksQuery().watch().listen((event) {
      if (state.asData == null) return;
      final allItems = getTracksWithCount(event);
      _allTrackCounts = allItems;
      final visibleCount = state.asData!.value.items.length;
      final items = allItems.take(visibleCount).toList(growable: false);
      state = AsyncData(state.asData!.value.copyWith(
        items: items,
        total: allItems.length,
        nextOffset: items.length,
        hasMore: items.length < allItems.length,
      ));
    });

    ref.onDispose(() {
      subscription.cancel();
    });

    return await fetch(0, 20);
  }

  List<PlaybackHistoryArtist> get artists {
    final counts = <String, int>{};
    final representatives = <String, SpotubeSimpleArtistObject>{};
    for (final historyTrack in _allTrackCounts) {
      for (final artist in historyTrack.track.artists) {
        final key = playbackHistoryArtistKey(artist);
        counts[key] = (counts[key] ?? 0) + historyTrack.count;
        final normalizedArtist = artist.copyWith(
          name: ChineseMetadataNormalizer.simplify(artist.name),
        );
        final current = representatives[key];
        if (current == null ||
            (current.images == null && normalizedArtist.images != null)) {
          representatives[key] = normalizedArtist;
        }
      }
    }
    return counts.entries
        .map((entry) => (
              count: entry.value,
              artist: representatives[entry.key]!,
            ))
        .sorted((a, b) => b.count.compareTo(a.count))
        .toList(growable: false);
  }

  List<PlaybackHistoryArtist> getArtistsWithCount(
    Iterable<SpotubeSimpleArtistObject> artists,
  ) {
    return groupBy(artists, playbackHistoryArtistKey)
        .entries
        .map((entry) {
          return (
            count: entry.value.length,

            /// Previously, due to a bug, artist images were not being saved.
            /// Now it's fixed, but we need to handle the case where images are null.
            /// So we take the first artist with images if available, otherwise the first one.
            artist: entry.value.firstWhereOrNull((a) => a.images != null) ??
                entry.value.first,
          );
        })
        .sorted((a, b) => b.count.compareTo(a.count))
        .toList();
  }

  List<PlaybackHistoryTrack> getTracksWithCount(List<HistoryTableData> tracks) {
    fixImageNotLoadingForArtistIssue(tracks);

    return groupBy(
      tracks,
      (track) => playbackHistoryTrackKey(track.track!),
    )
        .entries
        .map((entry) {
          return (
            count: entry.value.length,

            /// Previously, due to a bug, artist images were not being saved.
            /// Now it's fixed, but we need to handle the case where images are null.
            /// So we take the first artist with images if available, otherwise the first one.
            track: entry.value
                    .firstWhereOrNull(
                        (t) => t.track!.artists.every((a) => a.images != null))
                    ?.track! ??
                entry.value.first.track!,
          );
        })
        .sorted((a, b) => b.count.compareTo(a.count))
        .toList();
  }
}

final historyTopTracksProvider = AsyncNotifierProviderFamily<
    HistoryTopTracksNotifier,
    SpotubePaginationResponseObject<PlaybackHistoryTrack>,
    HistoryDuration>(
  () => HistoryTopTracksNotifier(),
);
