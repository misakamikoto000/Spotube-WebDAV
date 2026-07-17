import 'dart:ui';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/collections/assets.gen.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/hooks/utils/use_palette_color.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/player/player_actions.dart';
import 'package:spotube/modules/player/player_controls.dart';
import 'package:spotube/modules/player/volume_slider.dart';
import 'package:spotube/pages/lyrics/plain_lyrics.dart';
import 'package:spotube/pages/lyrics/synced_lyrics.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/lyrics/synced.dart';
import 'package:spotube/provider/volume_provider.dart';
import 'package:spotube/utils/platform.dart';
import 'package:auto_route/auto_route.dart';

@RoutePage()
class LyricsPage extends HookConsumerWidget {
  static const name = "lyrics";

  const LyricsPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    if (kIsWindows && MediaQuery.of(context).lgAndUp) {
      return const _WindowsLyricsStage();
    }

    final playlist = ref.watch(audioPlayerProvider);
    String albumArt = useMemoized(
      () => (playlist.activeTrack?.album.images).asUrlString(
        index: (playlist.activeTrack?.album.images.length ?? 1) - 1,
        placeholder: ImagePlaceholder.albumArt,
      ),
      [playlist.activeTrack?.album.images],
    );
    final palette = usePaletteColor(albumArt, ref);
    final selectedIndex = useState(0);
    final androidStage = kIsAndroid;

    Widget tabbar = Padding(
      padding: const EdgeInsets.all(10),
      child: Tabs(
        index: selectedIndex.value,
        onChanged: (index) => selectedIndex.value = index,
        children: [
          TabItem(child: Text(context.l10n.synced)),
          TabItem(child: Text(context.l10n.plain)),
        ],
      ),
    );

    tabbar = Row(
      children: [
        tabbar,
        const Spacer(),
        if (!androidStage || MediaQuery.sizeOf(context).width >= 520)
          Consumer(
            builder: (context, ref, child) {
              final playback = ref.watch(audioPlayerProvider);
              final lyric =
                  ref.watch(syncedLyricsProvider(playback.activeTrack));
              final providerName = lyric.asData?.value.provider;

              if (providerName == null) {
                return const SizedBox.shrink();
              }

              return Align(
                alignment: Alignment.bottomRight,
                child: Text(context.l10n.powered_by_provider(providerName)),
              );
            },
          ),
        const Gap(5),
      ],
    );

    return SafeArea(
      bottom: false,
      child: Scaffold(
        backgroundColor: androidStage ? Colors.transparent : null,
        floatingHeader: true,
        headers: [
          !kIsMacOS
              ? TitleBar(
                  backgroundColor: Colors.transparent,
                  title: tabbar,
                  height: 58 * context.theme.scaling,
                  surfaceBlur: 0,
                  automaticallyImplyLeading: false,
                )
              : tabbar
        ],
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            image: DecorationImage(
              image: UniversalImage.imageProvider(albumArt),
              fit: BoxFit.cover,
              opacity: androidStage ? 0.22 : 1,
            ),
          ),
          margin: EdgeInsets.fromLTRB(
            androidStage ? 8 : 0,
            androidStage ? 6 : 0,
            androidStage ? 8 : 0,
            10,
          ),
          child: SurfaceCard(
            surfaceBlur: androidStage ? 28 : context.theme.surfaceBlur,
            surfaceOpacity: androidStage ? 0.68 : context.theme.surfaceOpacity,
            padding: EdgeInsets.zero,
            borderRadius:
                androidStage ? BorderRadius.circular(24) : BorderRadius.zero,
            borderColor: androidStage ? const Color(0x38FFFFFF) : null,
            borderWidth: androidStage ? 1 : 0,
            fillColor: androidStage ? const Color(0xC20A0D16) : null,
            child: ColoredBox(
              color: palette.color.withValues(alpha: androidStage ? .28 : .7),
              child: SafeArea(
                child: IndexedStack(
                  index: selectedIndex.value,
                  children: [
                    SyncedLyrics(palette: palette, isModal: false),
                    PlainLyrics(palette: palette, isModal: false),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowsLyricsStage extends HookConsumerWidget {
  const _WindowsLyricsStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final playlist = ref.watch(audioPlayerProvider);
    final activeTrack = playlist.activeTrack;
    final albumArt = useMemoized(
      () => (activeTrack?.album.images).asUrlString(
        index: (activeTrack?.album.images.length ?? 1) - 1,
        placeholder: ImagePlaceholder.albumArt,
      ),
      [activeTrack?.album.images],
    );
    final palette = usePaletteColor(albumArt, ref);
    final selectedIndex = useState(0);
    final isChinese = Localizations.localeOf(context).languageCode == 'zh';
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      bottom: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        headers: const [
          TitleBar(
            automaticallyImplyLeading: false,
            backgroundColor: Colors.transparent,
            surfaceBlur: 0,
            height: 32,
          ),
        ],
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                child: Transform.scale(
                  scale: 1.12,
                  child: Opacity(
                    opacity: 0.24,
                    child: UniversalImage(
                      path: albumArt,
                      placeholder: Assets.images.albumPlaceholder.path,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xE605070D),
                      palette.color.withAlpha(72),
                      const Color(0xF205070D),
                    ],
                    stops: const [0.05, 0.48, 1],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                24,
                bottomInset + 16,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 4,
                    child: SurfaceCard(
                      padding: const EdgeInsets.all(22),
                      borderRadius: BorderRadius.circular(28),
                      borderColor: const Color(0x32FFFFFF),
                      borderWidth: 1,
                      fillColor: const Color(0xCA0A0D16),
                      surfaceOpacity: 0.7,
                      surfaceBlur: 28,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 300,
                                  maxHeight: 300,
                                ),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: const Color(0x3AFFFFFF),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: palette.color.withAlpha(82),
                                          blurRadius: 48,
                                          spreadRadius: 3,
                                        ),
                                        const BoxShadow(
                                          color: Color(0xA3000000),
                                          blurRadius: 28,
                                          offset: Offset(0, 18),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(24),
                                      child: UniversalImage(
                                        path: albumArt,
                                        placeholder:
                                            Assets.images.albumPlaceholder.path,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const Gap(22),
                            Text(
                              activeTrack?.name ?? context.l10n.not_playing,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.typography.h3.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.16,
                              ),
                            ),
                            const Gap(6),
                            Text(
                              activeTrack?.artists.asString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Gap(3),
                            Text(
                              activeTrack?.album.name ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.mutedForeground,
                                fontSize: 11,
                              ),
                            ),
                            const Gap(18),
                            const PlayerControls(compact: true),
                            const PlayerActions(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              showQueue: false,
                            ),
                            const Gap(8),
                            Consumer(
                              builder: (context, ref, _) {
                                final volume = ref.watch(volumeProvider);
                                return VolumeSlider(
                                  fullWidth: true,
                                  value: volume,
                                  onChanged: (value) => ref
                                      .read(volumeProvider.notifier)
                                      .setVolume(value),
                                );
                              },
                            ),
                            const Gap(12),
                            Button.outline(
                              onPressed: () =>
                                  context.navigateTo(const PlayerQueueRoute()),
                              leading: const Icon(SpotubeIcons.queue, size: 17),
                              child: Text(context.l10n.queue),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Gap(16),
                  Expanded(
                    flex: 6,
                    child: SurfaceCard(
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(28),
                      borderColor: const Color(0x32FFFFFF),
                      borderWidth: 1,
                      fillColor: const Color(0xC20A0D16),
                      surfaceOpacity: 0.66,
                      surfaceBlur: 30,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 18, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isChinese ? '歌词舞台' : 'LYRICS STAGE',
                                        style: theme.typography.h4.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Consumer(
                                        builder: (context, ref, _) {
                                          final lyrics = ref.watch(
                                            syncedLyricsProvider(activeTrack),
                                          );
                                          final provider =
                                              lyrics.asData?.value.provider;
                                          return Text(
                                            provider == null
                                                ? (isChinese
                                                    ? '跟随音乐滚动'
                                                    : 'Follow the music')
                                                : context.l10n
                                                    .powered_by_provider(
                                                    provider,
                                                  ),
                                            style: TextStyle(
                                              color: theme
                                                  .colorScheme.mutedForeground,
                                              fontSize: 10,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                TabList(
                                  index: selectedIndex.value,
                                  onChanged: (index) =>
                                      selectedIndex.value = index,
                                  children: [
                                    TabItem(
                                      child: Text(context.l10n.synced),
                                    ),
                                    TabItem(
                                      child: Text(context.l10n.plain),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Gap(12),
                            const Divider(),
                            Expanded(
                              child: IndexedStack(
                                index: selectedIndex.value,
                                children: [
                                  SyncedLyrics(
                                    palette: palette,
                                    isModal: true,
                                    defaultTextZoom: 108,
                                  ),
                                  PlainLyrics(
                                    palette: palette,
                                    isModal: true,
                                    defaultTextZoom: 105,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
