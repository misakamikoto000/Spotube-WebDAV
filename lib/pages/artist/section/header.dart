import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:spotube/collections/fake.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/blacklist_provider.dart';
import 'package:spotube/provider/metadata_plugin/artist/artist.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/utils/primitive_utils.dart';
import 'package:spotube/utils/platform.dart';

class ArtistPageHeader extends HookConsumerWidget {
  final String artistId;
  const ArtistPageHeader({super.key, required this.artistId});

  @override
  Widget build(BuildContext context, ref) {
    final artistQuery = ref.watch(metadataPluginArtistProvider(artistId));
    final artist = artistQuery.asData?.value ?? FakeData.artist;

    final theme = Theme.of(context);
    final ThemeData(:typography) = theme;

    final authenticated = ref.watch(metadataPluginAuthenticatedProvider);
    ref.watch(blacklistProvider);
    final blacklistNotifier = ref.watch(blacklistProvider.notifier);
    final isBlackListed = blacklistNotifier.containsArtist(artist.id);

    final image = artist.images.asUrlString(
      placeholder: ImagePlaceholder.artist,
    );

    final actions = Skeleton.keep(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (authenticated.asData?.value == true)
            Consumer(
              builder: (context, ref, _) {
                final isFollowingQuery = ref.watch(
                  metadataPluginIsSavedArtistProvider(artist.id),
                );
                final followingArtistNotifier =
                    ref.watch(metadataPluginSavedArtistsProvider.notifier);

                return switch (isFollowingQuery) {
                  AsyncData(value: final following) => Builder(
                      builder: (context) {
                        if (following) {
                          return Button.outline(
                            onPressed: () async {
                              await followingArtistNotifier
                                  .removeFavorite([artist]);
                            },
                            child: Text(context.l10n.following),
                          );
                        }

                        return Button.primary(
                          onPressed: () async {
                            await followingArtistNotifier.addFavorite([artist]);
                          },
                          child: Text(context.l10n.follow),
                        );
                      },
                    ),
                  AsyncError() => const SizedBox(),
                  _ => const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(),
                    )
                };
              },
            ),
          const SizedBox(width: 5),
          Tooltip(
            tooltip: TooltipContainer(
              child: Text(context.l10n.add_artist_to_blacklist),
            ).call,
            child: IconButton(
              icon: Icon(
                SpotubeIcons.userRemove,
                color: !isBlackListed ? Colors.red[400] : null,
              ),
              variance: isBlackListed
                  ? ButtonVariance.destructive
                  : ButtonVariance.ghost,
              onPressed: () async {
                if (isBlackListed) {
                  await ref.read(blacklistProvider.notifier).remove(artist.id);
                } else {
                  await ref.read(blacklistProvider.notifier).add(
                        BlacklistTableCompanion.insert(
                          name: artist.name,
                          elementId: artist.id,
                          elementType: BlacklistedType.artist,
                        ),
                      );
                }
              },
            ),
          ),
          IconButton.ghost(
            icon: const Icon(SpotubeIcons.share),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text: artist.externalUri,
                ),
              );

              if (!context.mounted) return;

              showToast(
                context: context,
                location: ToastLocation.topRight,
                dismissible: true,
                builder: (context, overlay) {
                  return SurfaceCard(
                    child: Text(
                      context.l10n.artist_url_copied,
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              );
            },
          )
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constrains) {
        final windowsStage = useImmersiveUi(context);
        final desktopStage = useImmersiveDesktopUi(context);
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: windowsStage ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: windowsStage
                        ? null
                        : BorderRadius.circular(theme.radiusXl),
                    border: windowsStage
                        ? Border.all(color: const Color(0x44FFFFFF), width: 2)
                        : null,
                    boxShadow: windowsStage
                        ? [
                            BoxShadow(
                              color: theme.colorScheme.primary.withAlpha(60),
                              blurRadius: 36,
                              offset: const Offset(0, 16),
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      windowsStage ? 999 : theme.radiusXl,
                    ),
                    child: UniversalImage(
                      path: image,
                      width: desktopStage
                          ? 230
                          : constrains.mdAndUp
                              ? 200
                              : 120,
                      height: desktopStage
                          ? 230
                          : constrains.mdAndUp
                              ? 200
                              : 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Gap(desktopStage ? 28 : 20),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlineBadge(
                            child: Text(context.l10n.artist).small().muted(),
                          ),
                          if (isBlackListed) ...[
                            const Gap(5),
                            DestructiveBadge(
                              child: Text(context.l10n.blacklisted).small(),
                            ),
                          ]
                        ],
                      ),
                      const Gap(10),
                      Flexible(
                        child: AutoSizeText(
                          artist.name,
                          style: desktopStage
                              ? typography.h2.copyWith(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w700,
                                )
                              : constrains.smAndDown
                                  ? typography.h4
                                  : typography.h3,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          minFontSize: 14,
                        ),
                      ),
                      const Gap(5),
                      Flexible(
                        child: AutoSizeText(
                          context.l10n.followers(
                            artist.followers == null
                                ? double.infinity
                                : PrimitiveUtils.toReadableNumber(
                                    artist.followers!.toDouble(),
                                  ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          minFontSize: 12,
                        ).muted(),
                      ),
                      if (constrains.mdAndUp) ...[
                        Gap(desktopStage ? 28 : 20),
                        actions,
                      ]
                    ],
                  ),
                ),
              ],
            ),
            if (constrains.smAndDown) ...[
              const Gap(20),
              actions,
            ]
          ],
        );

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: desktopStage ? 24 : 8),
          child: windowsStage
              ? SurfaceCard(
                  padding: EdgeInsets.all(kIsAndroid ? 16 : 28),
                  borderRadius: BorderRadius.circular(28),
                  borderColor: const Color(0x3AFFFFFF),
                  borderWidth: 1,
                  fillColor: const Color(0xCC0A0D16),
                  surfaceOpacity: 0.72,
                  surfaceBlur: 28,
                  child: content,
                )
              : Card(child: content),
        );
      },
    );
  }
}
