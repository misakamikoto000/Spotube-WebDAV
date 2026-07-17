import 'package:auto_route/auto_route.dart';
import 'package:auto_size_text/auto_size_text.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';

import 'package:spotube/provider/blacklist_provider.dart';
import 'package:spotube/provider/local_library/local_library_catalog.dart';
import 'package:spotube/utils/platform.dart';

class ArtistCard extends HookConsumerWidget {
  final SpotubeFullArtistObject artist;
  const ArtistCard(this.artist, {super.key});

  @override
  Widget build(BuildContext context, ref) {
    final theme = Theme.of(context);
    final backgroundImage = UniversalImage.imageProvider(
      artist.images.asUrlString(
        placeholder: ImagePlaceholder.artist,
      ),
    );
    final isBlackListed = ref.watch(
      blacklistProvider.select(
        (blacklist) => blacklist.asData?.value.any(
          (element) => element.elementId == artist.id,
        ),
      ),
    );
    final localLocation = ref.watch(
      localLibraryCatalogProvider.select(
        (catalog) => catalog.artistLocationsById[artist.id],
      ),
    );
    final windowsStage = useImmersiveUi(context);

    final card = SizedBox(
      width: windowsStage ? 184 : 180,
      child: Button(
        style: windowsStage
            ? ButtonVariance.card.copyWith(
                padding: (context, states, value) => const EdgeInsets.all(12),
              )
            : ButtonVariance.card,
        onPressed: () {
          if (localLocation != null) {
            context.navigateTo(LocalLibraryRoute(location: localLocation));
          } else {
            context.navigateTo(ArtistRoute(artistId: artist.id));
          }
        },
        child: Column(
          children: [
            Avatar(
              initials: artist.name.trim()[0].toUpperCase(),
              provider: backgroundImage,
              size: windowsStage ? 142 : 130,
            ),
            const Gap(10),
            AutoSizeText(
              artist.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.bold,
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isBlackListed == true) ...[
                  DestructiveBadge(
                    child: Text(context.l10n.blacklisted.toUpperCase()),
                  ),
                  const Gap(5),
                ],
                SecondaryBadge(
                  child: Text(context.l10n.artist.toUpperCase()),
                )
              ],
            )
          ],
        ),
      ),
    );

    return windowsStage ? _WindowsArtistFrame(child: card) : card;
  }
}

class _WindowsArtistFrame extends StatefulWidget {
  final Widget child;

  const _WindowsArtistFrame({required this.child});

  @override
  State<_WindowsArtistFrame> createState() => _WindowsArtistFrameState();
}

class _WindowsArtistFrameState extends State<_WindowsArtistFrame> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: hovered ? primary.withAlpha(78) : const Color(0x1FFFFFFF),
          ),
          boxShadow: hovered
              ? [
                  BoxShadow(
                    color: primary.withAlpha(28),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ]
              : null,
        ),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          scale: hovered ? 1.015 : 1,
          child: widget.child,
        ),
      ),
    );
  }
}
