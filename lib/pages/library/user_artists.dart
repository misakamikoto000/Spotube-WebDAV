import 'package:flutter/material.dart' as material;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:collection/collection.dart';
import 'package:flutter_undraw/flutter_undraw.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:spotube/collections/fake.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/fallbacks/error_box.dart';
import 'package:spotube/components/fallbacks/no_default_metadata_plugin.dart';
import 'package:spotube/components/windows/windows_collection_toolbar.dart';
import 'package:spotube/modules/artist/artist_card.dart';
import 'package:spotube/components/inter_scrollbar/inter_scrollbar.dart';
import 'package:spotube/components/waypoint.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/provider/local_library/local_library_catalog.dart';
import 'package:spotube/provider/webdav/webdav_library_provider.dart';
import 'package:auto_route/auto_route.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/utils/platform.dart';

@RoutePage()
class UserArtistsPage extends HookConsumerWidget {
  static const name = 'user_artists';
  const UserArtistsPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final artistQuery = ref.watch(metadataPluginSavedArtistsProvider);
    final artistQueryNotifier =
        ref.watch(metadataPluginSavedArtistsProvider.notifier);
    final localArtistCount = ref.watch(
      localLibraryCatalogProvider.select((catalog) => catalog.artists.length),
    );
    final matchingArtistImages = useState(false);

    final searchText = useState('');
    final windowsStage = useImmersiveUi(context);
    final isChinese = Localizations.localeOf(context).languageCode == 'zh';

    final filteredArtists = useMemoized(() {
      final artists = artistQuery.asData?.value.items ?? [];

      if (searchText.value.isEmpty) {
        return artists.toList();
      }
      return artists
          .map((e) => (
                weightedRatio(e.name, searchText.value),
                e,
              ))
          .sorted((a, b) => b.$1.compareTo(a.$1))
          .where((e) => e.$1 > 50)
          .map((e) => e.$2)
          .toList();
    }, [artistQuery.asData?.value.items, searchText.value]);

    final controller = useScrollController();

    void showMessage(String message) {
      showToast(
        context: context,
        location: ToastLocation.topRight,
        builder: (context, overlay) => SurfaceCard(
          child: Basic(title: Text(message)),
        ),
      );
    }

    Future<void> matchArtistImages() async {
      if (matchingArtistImages.value) return;
      matchingArtistImages.value = true;
      try {
        final summary =
            await ref.read(webDavLibraryProvider.notifier).matchArtistImages();
        ref.invalidate(metadataPluginSavedArtistsProvider);
        if (context.mounted) {
          showMessage(
            context.l10n.webdav_artist_images_complete(
              summary.matched,
              summary.unmatched,
              summary.failed,
            ),
          );
        }
      } catch (error) {
        if (context.mounted) showMessage(error.toString());
      } finally {
        if (context.mounted) matchingArtistImages.value = false;
      }
    }

    if (artistQuery.error
        case MetadataPluginException(
          errorCode: MetadataPluginErrorCode.noDefaultMetadataPlugin,
          message: _,
        )) {
      return const Center(child: NoDefaultMetadataPlugin());
    }

    if (artistQuery.hasError) {
      return ErrorBox(
        error: artistQuery.error!,
        onRetry: () {
          ref.invalidate(metadataPluginSavedArtistsProvider);
        },
      );
    }

    return SafeArea(
      bottom: false,
      child: Scaffold(
        backgroundColor: windowsStage ? Colors.transparent : null,
        child: material.RefreshIndicator.adaptive(
          onRefresh: () async {
            ref.invalidate(metadataPluginSavedArtistsProvider);
          },
          child: InterScrollbar(
            controller: controller,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: windowsStage && !kIsAndroid ? 24 : 8,
              ),
              child: CustomScrollView(
                controller: controller,
                slivers: [
                  if (windowsStage)
                    SliverPadding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      sliver: SliverToBoxAdapter(
                        child: WindowsCollectionToolbar(
                          icon: SpotubeIcons.artist,
                          title: context.l10n.artists,
                          subtitle: isChinese
                              ? '聚合简繁名称并展示本地匹配的歌手头像'
                              : 'Matched local artists and cached portraits',
                          countLabel: '${filteredArtists.length}',
                          searchPlaceholder: context.l10n.filter_artist,
                          onSearchChanged: (value) => searchText.value = value,
                          trailing: localArtistCount > 0
                              ? Button.secondary(
                                  leading: matchingArtistImages.value
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(),
                                        )
                                      : const Icon(SpotubeIcons.magic),
                                  enabled: !matchingArtistImages.value,
                                  onPressed: matchArtistImages,
                                  child: Text(
                                    matchingArtistImages.value
                                        ? context
                                            .l10n.webdav_matching_artist_images
                                        : context
                                            .l10n.webdav_match_artist_images,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    )
                  else
                    SliverAppBar(
                      automaticallyImplyLeading: false,
                      backgroundColor: Theme.of(context).colorScheme.background,
                      floating: true,
                      flexibleSpace: SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                onChanged: (value) => searchText.value = value,
                                features: const [
                                  InputFeature.leading(
                                    Icon(SpotubeIcons.filter),
                                  ),
                                ],
                                placeholder: Text(context.l10n.filter_artist),
                              ),
                            ),
                            if (localArtistCount > 0) ...[
                              const Gap(8),
                              Button.secondary(
                                leading: matchingArtistImages.value
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(),
                                      )
                                    : const Icon(SpotubeIcons.magic),
                                enabled: !matchingArtistImages.value,
                                onPressed: matchArtistImages,
                                child: Text(
                                  matchingArtistImages.value
                                      ? context
                                          .l10n.webdav_matching_artist_images
                                      : context.l10n.webdav_match_artist_images,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  SliverGap(windowsStage ? 8 : 10),
                  if (filteredArtists.isNotEmpty || artistQuery.isLoading)
                    SliverLayoutBuilder(builder: (context, constrains) {
                      return SliverGrid.builder(
                        itemCount: filteredArtists.length + 1,
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent:
                              windowsStage && !kIsAndroid ? 220 : 200,
                          mainAxisExtent: windowsStage && !kIsAndroid
                              ? 280
                              : constrains.smAndDown
                                  ? 225
                                  : 250,
                          crossAxisSpacing:
                              windowsStage && !kIsAndroid ? 16 : 8,
                          mainAxisSpacing: windowsStage && !kIsAndroid ? 16 : 8,
                        ),
                        itemBuilder: (context, index) {
                          if (filteredArtists.isNotEmpty &&
                              index == filteredArtists.length) {
                            if (artistQuery.asData?.value.hasMore != true) {
                              return const SizedBox.shrink();
                            }

                            return Waypoint(
                              controller: controller,
                              isGrid: true,
                              onTouchEdge: artistQueryNotifier.fetchMore,
                              child: Skeletonizer(
                                enabled: true,
                                child: ArtistCard(FakeData.artist),
                              ),
                            );
                          }

                          return Skeletonizer(
                            enabled: artistQuery.isLoading,
                            child: ArtistCard(
                              filteredArtists.elementAtOrNull(index) ??
                                  FakeData.artist,
                            ),
                          );
                        },
                      );
                    })
                  else if (filteredArtists.isEmpty &&
                      searchText.value.isEmpty &&
                      !artistQuery.isLoading)
                    SliverToBoxAdapter(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 10,
                        children: [
                          Undraw(
                            height: 200 * context.theme.scaling,
                            illustration: UndrawIllustration.followMeDrone,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          Text(
                            context.l10n.not_following_artists,
                            textAlign: TextAlign.center,
                          ).muted().small()
                        ],
                      ),
                    )
                  else
                    SliverToBoxAdapter(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 10,
                        children: [
                          Undraw(
                            height: 200 * context.theme.scaling,
                            illustration: UndrawIllustration.taken,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          Text(
                            context.l10n.nothing_found,
                            textAlign: TextAlign.center,
                          ).muted().small()
                        ],
                      ),
                    ),
                  const SliverSafeArea(sliver: SliverGap(10)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
