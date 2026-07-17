import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/local_library/local_library_catalog.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/utils/family_paginated.dart';

class MetadataPluginBrowseSectionItemsNotifier
    extends FamilyPaginatedAsyncNotifier<Object, String> {
  @override
  Future<SpotubePaginationResponseObject<Object>> fetch(
    int offset,
    int limit,
  ) async {
    return await (await metadataPlugin).browse.sectionItems(
          arg,
          limit: limit,
          offset: offset,
        );
  }

  @override
  build(arg) async {
    final localCatalog = ref.watch(localLibraryCatalogProvider);
    final authenticated =
        await ref.watch(metadataPluginAuthenticatedProvider.future);
    if (!authenticated) {
      final items = switch (arg) {
        'local:playlists' => localCatalog.playlists
            .map<Object>((collection) => collection.item)
            .toList(growable: false),
        'local:albums' => localCatalog.albums
            .map<Object>((collection) => collection.item)
            .toList(growable: false),
        'local:artists' => localCatalog.artists
            .map<Object>((collection) => collection.item)
            .toList(growable: false),
        _ => const <Object>[],
      };
      return SpotubePaginationResponseObject<Object>(
        limit: items.length,
        nextOffset: null,
        total: items.length,
        hasMore: false,
        items: items,
      );
    }
    await metadataPlugin;
    return await fetch(0, 20);
  }
}

final metadataPluginBrowseSectionItemsProvider = AsyncNotifierProviderFamily<
    MetadataPluginBrowseSectionItemsNotifier,
    SpotubePaginationResponseObject<Object>,
    String>(
  () => MetadataPluginBrowseSectionItemsNotifier(),
);
