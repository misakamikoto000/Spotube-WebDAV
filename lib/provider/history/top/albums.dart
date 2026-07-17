import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/history/history_utils.dart';
import 'package:spotube/provider/history/top.dart';
import 'package:spotube/provider/metadata_plugin/utils/family_paginated.dart';

typedef PlaybackHistoryAlbum = ({int count, SpotubeSimpleAlbumObject album});

class HistoryTopAlbumsNotifier extends FamilyPaginatedAsyncNotifier<
    PlaybackHistoryAlbum, HistoryDuration> {
  HistoryTopAlbumsNotifier() : super();

  Selectable<SpotubeSimpleAlbumObject> createAlbumsQuery() {
    final database = ref.read(databaseProvider);

    final duration = switch (arg) {
      HistoryDuration.allTime => '0',
      HistoryDuration.days7 => "strftime('%s', 'now', 'weekday 0', '-7 days')",
      HistoryDuration.days30 => "strftime('%s', 'now', 'start of month')",
      HistoryDuration.months6 =>
        "strftime('%s', date('now', '-5 months', 'start of month'))",
      HistoryDuration.year => "strftime('%s', date('now', 'start of year'))",
      HistoryDuration.years2 =>
        "strftime('%s', date('now', '-1 years', 'start of year'))",
    };

    return database.customSelect(
      """
        SELECT 
            history_table.created_at,
      """
      r"""
            json_extract(history_table.data, '$.album') as data,
            json_extract(history_table.data, '$.album.id') as item_id,
            'album' as type
        """
      """
        FROM history_table 
        WHERE type = 'track' AND
              created_at >= $duration
        UNION ALL
        SELECT
            history_table.created_at,
            history_table.data,
            history_table.item_id,
            history_table.type
        FROM history_table
        WHERE type = 'album' AND
              created_at >= $duration
        ORDER BY created_at desc
      """,
      readsFrom: {database.historyTable},
    ).map((row) {
      final data = row.read<String>('data');
      final album = SpotubeSimpleAlbumObject.fromJson(jsonDecode(data));
      return album;
    });
  }

  @override
  fetch(offset, limit) async {
    final allItems = getAlbumsWithCount(await createAlbumsQuery().get());
    final items = allItems.skip(offset).take(limit).toList(growable: false);

    return SpotubePaginationResponseObject(
      items: items,
      limit: limit,
      hasMore: offset + items.length < allItems.length,
      nextOffset: (offset + limit).toInt(),
      total: allItems.length,
    );
  }

  @override
  build(arg) async {
    final subscription = createAlbumsQuery().watch().listen((event) {
      if (state.asData == null) return;
      final allItems = getAlbumsWithCount(event);
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

  List<PlaybackHistoryAlbum> getAlbumsWithCount(
    List<SpotubeSimpleAlbumObject> albumsWithTrackAlbums,
  ) {
    return groupBy(albumsWithTrackAlbums, playbackHistoryAlbumKey)
        .entries
        .map((entry) {
          return (count: entry.value.length, album: entry.value.first);
        })
        .sorted((a, b) => b.count.compareTo(a.count))
        .toList();
  }
}

final historyTopAlbumsProvider = AsyncNotifierProviderFamily<
    HistoryTopAlbumsNotifier,
    SpotubePaginationResponseObject<PlaybackHistoryAlbum>,
    HistoryDuration>(
  () => HistoryTopAlbumsNotifier(),
);
