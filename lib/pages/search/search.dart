import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/collections/routes.gr.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/fallbacks/error_box.dart';
import 'package:spotube/components/fallbacks/no_default_metadata_plugin.dart';
import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/extensions/string.dart';
import 'package:spotube/hooks/controllers/use_shadcn_text_editing_controller.dart';
import 'package:spotube/pages/search/tabs/albums.dart';
import 'package:spotube/pages/search/tabs/all.dart';
import 'package:spotube/pages/search/tabs/artists.dart';
import 'package:spotube/pages/search/tabs/playlists.dart';
import 'package:spotube/pages/search/tabs/tracks.dart';
import 'package:spotube/provider/metadata_plugin/search/all.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:auto_route/auto_route.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/utils/platform.dart';

final searchTermStateProvider = StateProvider<String>((ref) {
  return "";
});

@RoutePage()
class SearchPage extends HookConsumerWidget {
  static const name = "search";

  const SearchPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final controller = useShadcnTextEditingController();
    final focusNode = useFocusNode();

    final searchTerm = ref.watch(searchTermStateProvider);
    final searchChipSnapshot = ref.watch(metadataPluginSearchChipsProvider);
    final selectedChip = useState<String?>(
      searchChipSnapshot.asData?.value.first ?? "all",
    );
    final windowsStage = useImmersiveUi(context);
    final isChinese = Localizations.localeOf(context).languageCode == 'zh';

    ref.listen(
      metadataPluginSearchChipsProvider,
      (previous, next) {
        selectedChip.value = next.asData?.value.first ?? "all";
      },
    );

    useEffect(() {
      controller.text = searchTerm;

      return null;
    }, []);

    void onSubmitted(String value) {
      ref.read(searchTermStateProvider.notifier).state = value;
      focusNode.unfocus();
      if (value.trim().isEmpty) {
        return;
      }
      KVStoreService.setRecentSearches(
        {
          value,
          ...KVStoreService.recentSearches,
        }.toList(),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        context.navigateTo(const HomeRoute());
      },
      child: SafeArea(
        bottom: false,
        child: Scaffold(
          backgroundColor: windowsStage ? Colors.transparent : null,
          headers: [
            if (kTitlebarVisible)
              TitleBar(
                automaticallyImplyLeading: false,
                height: 30,
                backgroundColor: windowsStage ? Colors.transparent : null,
                surfaceBlur: windowsStage ? 0 : null,
              )
          ],
          child: Builder(builder: (context) {
            if (searchChipSnapshot.error
                case MetadataPluginException(
                  errorCode: MetadataPluginErrorCode.noDefaultMetadataPlugin,
                  message: _
                )) {
              return const NoDefaultMetadataPlugin();
            }

            if (searchChipSnapshot.hasError) {
              return ErrorBox(
                error: searchChipSnapshot.error!,
                onRetry: () {
                  ref.invalidate(metadataPluginSearchChipsProvider);
                },
              );
            }

            final searchInput = ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final suggestions = controller.text.isEmpty
                    ? KVStoreService.recentSearches
                    : KVStoreService.recentSearches
                        .where(
                          (suggestion) =>
                              weightedRatio(
                                suggestion.toLowerCase(),
                                controller.text.toLowerCase(),
                              ) >
                              50,
                        )
                        .toList();

                return AutoComplete(
                  suggestions: suggestions.length <= 2
                      ? [
                          ...suggestions,
                          'Twenty One Pilots',
                          'Linkin Park',
                        ]
                      : suggestions,
                  completer: (suggestion) => suggestion,
                  mode: AutoCompleteMode.replaceAll,
                  child: TextField(
                    autofocus: true,
                    controller: controller,
                    focusNode: focusNode,
                    features: [
                      const InputFeature.leading(
                        Icon(SpotubeIcons.search),
                      ),
                      InputFeature.trailing(
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 300),
                          crossFadeState: controller.text.isNotEmpty
                              ? CrossFadeState.showFirst
                              : CrossFadeState.showSecond,
                          firstChild: IconButton.ghost(
                            size: ButtonSize.small,
                            icon: const Icon(SpotubeIcons.close),
                            onPressed: controller.clear,
                          ),
                          secondChild: const SizedBox.square(dimension: 28),
                        ),
                      ),
                    ],
                    textInputAction: TextInputAction.search,
                    placeholder: Text(context.l10n.search),
                    onSubmitted: onSubmitted,
                  ),
                );
              },
            );

            final chips = SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  if (searchChipSnapshot.asData?.value != null)
                    for (final chip in searchChipSnapshot.asData!.value)
                      Chip(
                        style: selectedChip.value == chip
                            ? ButtonVariance.primary.copyWith(
                                decoration: (context, states, value) {
                                  return ButtonVariance.primary
                                      .decoration(context, states)
                                      .copyWithIfBoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(100),
                                      );
                                },
                              )
                            : ButtonVariance.secondary.copyWith(
                                decoration: (context, states, value) {
                                  return ButtonVariance.secondary
                                      .decoration(context, states)
                                      .copyWithIfBoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(100),
                                      );
                                },
                              ),
                        child: Text(chip.capitalize()),
                        onPressed: () => selectedChip.value = chip,
                      ),
                ],
              ),
            );

            final results = AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: switch (selectedChip.value) {
                'tracks' => const SearchPageTracksTab(),
                'albums' => const SearchPageAlbumsTab(),
                'artists' => const SearchPageArtistsTab(),
                'playlists' => const SearchPagePlaylistsTab(),
                _ => const SearchPageAllTab(),
              },
            );

            return Column(
              children: [
                if (windowsStage)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      kIsAndroid ? 8 : 12,
                      8,
                      kIsAndroid ? 8 : 24,
                      0,
                    ),
                    child: SurfaceCard(
                      padding: const EdgeInsets.all(18),
                      borderRadius: BorderRadius.circular(22),
                      borderColor: const Color(0x30FFFFFF),
                      borderWidth: 1,
                      fillColor: const Color(0xD00A0E18),
                      surfaceOpacity: 0.7,
                      surfaceBlur: 26,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 620;
                              final heading = Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF745CFF),
                                          Color(0xFF288FEF),
                                        ],
                                      ),
                                    ),
                                    child: const Icon(
                                      SpotubeIcons.search,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  const Gap(12),
                                  Flexible(
                                    child: Text(
                                      isChinese
                                          ? '搜索音乐宇宙'
                                          : 'Search your music',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .typography
                                          .h4
                                          .copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              );
                              if (compact) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    heading,
                                    const Gap(12),
                                    searchInput,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: heading),
                                  const Gap(20),
                                  Expanded(child: searchInput),
                                ],
                              );
                            },
                          ),
                          const Gap(12),
                          chips,
                        ],
                      ),
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: searchInput,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: chips,
                  ),
                ],
                Expanded(
                  child: windowsStage
                      ? Padding(
                          padding: EdgeInsets.fromLTRB(
                            kIsAndroid ? 8 : 12,
                            10,
                            kIsAndroid ? 8 : 24,
                            MediaQuery.paddingOf(context).bottom + 14,
                          ),
                          child: SurfaceCard(
                            padding: EdgeInsets.zero,
                            borderRadius: BorderRadius.circular(22),
                            borderColor: const Color(0x24FFFFFF),
                            borderWidth: 1,
                            fillColor: const Color(0xA80A0E18),
                            surfaceOpacity: 0.55,
                            surfaceBlur: 20,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: results,
                            ),
                          ),
                        )
                      : results,
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
