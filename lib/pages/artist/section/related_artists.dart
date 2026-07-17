import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/modules/artist/artist_card.dart';
import 'package:spotube/provider/metadata_plugin/artist/related.dart';
import 'package:spotube/utils/platform.dart';

class ArtistPageRelatedArtists extends ConsumerWidget {
  final String artistId;
  const ArtistPageRelatedArtists({
    super.key,
    required this.artistId,
  });

  @override
  Widget build(BuildContext context, ref) {
    final windowsStage = useImmersiveUi(context);
    final relatedArtists =
        ref.watch(metadataPluginArtistRelatedArtistsProvider(artistId));

    return switch (relatedArtists) {
      AsyncData(value: final artists) => SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: windowsStage && !kIsAndroid ? 24 : 8,
          ),
          sliver: SliverGrid.builder(
            itemCount: artists.items.length,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: windowsStage && !kIsAndroid ? 220 : 200,
              mainAxisExtent: windowsStage && !kIsAndroid ? 280 : 250,
              mainAxisSpacing: windowsStage && !kIsAndroid ? 16 : 10,
              crossAxisSpacing: windowsStage && !kIsAndroid ? 16 : 10,
              childAspectRatio: 0.8,
            ),
            itemBuilder: (context, index) {
              final artist = artists.items.elementAt(index);
              return SizedBox(
                width: 180,
                child: ArtistCard(artist),
              );
            },
          ),
        ),
      AsyncError(:final error) => SliverToBoxAdapter(
          child: Center(
            child: Text(error.toString()),
          ),
        ),
      _ => const SliverToBoxAdapter(
          child: Center(child: CircularProgressIndicator()),
        ),
    };
  }
}
