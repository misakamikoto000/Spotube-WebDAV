import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/local_library/local_library_catalog.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';

class MetadataPluginBrowseSectionsNotifier
    extends PaginatedAsyncNotifier<SpotubeBrowseSectionObject<Object>> {
  @override
  Future<SpotubePaginationResponseObject<SpotubeBrowseSectionObject<Object>>>
      fetch(
    int offset,
    int limit,
  ) async {
    return await (await metadataPlugin).browse.sections(
          limit: limit,
          offset: offset,
        );
  }

  @override
  build() async {
    final localCatalog = ref.watch(localLibraryCatalogProvider);
    final authenticated =
        await ref.watch(metadataPluginAuthenticatedProvider.future);
    if (!authenticated) {
      final sections = <SpotubeBrowseSectionObject<Object>>[
        if (localCatalog.playlists.isNotEmpty)
          SpotubeBrowseSectionObject<Object>(
            id: 'local:playlists',
            title: 'WebDAV',
            externalUri: '',
            browseMore: false,
            items: localCatalog.playlists
                .map<Object>((collection) => collection.item)
                .toList(growable: false),
          ),
        if (localCatalog.albums.isNotEmpty)
          SpotubeBrowseSectionObject<Object>(
            id: 'local:albums',
            title: 'Albums',
            externalUri: '',
            browseMore: false,
            items: localCatalog.albums
                .map<Object>((collection) => collection.item)
                .toList(growable: false),
          ),
        if (localCatalog.artists.isNotEmpty)
          SpotubeBrowseSectionObject<Object>(
            id: 'local:artists',
            title: 'Artists',
            externalUri: '',
            browseMore: false,
            items: localCatalog.artists
                .map<Object>((collection) => collection.item)
                .toList(growable: false),
          ),
      ];
      return SpotubePaginationResponseObject<
          SpotubeBrowseSectionObject<Object>>(
        limit: sections.length,
        nextOffset: null,
        total: sections.length,
        hasMore: false,
        items: sections,
      );
    }
    await metadataPlugin;
    return await fetch(0, 20);
  }
}

final metadataPluginBrowseSectionsProvider = AsyncNotifierProvider<
    MetadataPluginBrowseSectionsNotifier,
    SpotubePaginationResponseObject<SpotubeBrowseSectionObject<Object>>>(
  () => MetadataPluginBrowseSectionsNotifier(),
);
