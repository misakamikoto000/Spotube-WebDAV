import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/modules/connect/connect_device.dart';
import 'package:spotube/modules/home/sections/featured.dart';
import 'package:spotube/modules/home/sections/sections.dart';
import 'package:spotube/modules/home/sections/new_releases.dart';
import 'package:spotube/modules/home/sections/recent.dart';
import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/webdav/webdav_accounts_provider.dart';
import 'package:spotube/provider/webdav/webdav_library_provider.dart';
import 'package:spotube/utils/platform.dart';

@RoutePage()
class HomePage extends HookConsumerWidget {
  static const name = "home";
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final theme = Theme.of(context);
    final controller = useScrollController();
    final mediaQuery = MediaQuery.of(context);
    final layoutMode =
        ref.watch(userPreferencesProvider.select((s) => s.layoutMode));
    final windowsStage = useImmersiveUi(context);

    return SafeArea(
        bottom: false,
        child: Scaffold(
          backgroundColor: windowsStage ? Colors.transparent : null,
          headers: [
            if (kTitlebarVisible) const TitleBar(height: 30),
          ],
          child: CustomScrollView(
            controller: controller,
            slivers: [
              if (mediaQuery.smAndDown || layoutMode == LayoutMode.compact)
                SliverAppBar(
                  floating: true,
                  title: DefaultTextStyle(
                    style: TextStyle(
                      fontFamily: "Cookie",
                      fontSize: 30,
                      letterSpacing: 1.8,
                      color: theme.colorScheme.foreground,
                    ),
                    child: const Text("Spotube"),
                  ),
                  backgroundColor: windowsStage
                      ? Colors.transparent
                      : theme.colorScheme.background,
                  foregroundColor: theme.colorScheme.foreground,
                  actions: [
                    const ConnectDeviceButton(),
                    const Gap(10),
                    IconButton.ghost(
                      icon: const Icon(SpotubeIcons.settings, size: 20),
                      onPressed: () {
                        context.navigateTo(const SettingsRoute());
                      },
                    ),
                    const Gap(10),
                  ],
                )
              else if (kIsMacOS)
                const SliverGap(10),
              if (windowsStage)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    kIsAndroid ? 8 : 10,
                    kIsAndroid ? 6 : 10,
                    kIsAndroid ? 8 : 24,
                    kIsAndroid ? 12 : 18,
                  ),
                  sliver: const SliverToBoxAdapter(
                    child: _WindowsHomeHero(),
                  ),
                )
              else
                const SliverGap(10),
              SliverList.builder(
                itemCount: 3,
                itemBuilder: (context, index) {
                  return switch (index) {
                    // 0 => const HomeGenresSection(),
                    0 => const HomeRecentlyPlayedSection(),
                    // ignore: deprecated_member_use_from_same_package
                    1 => const HomeFeaturedSection(),
                    // 3 => const HomePageFriendsSection(),
                    _ => const HomeNewReleasesSection()
                  };
                },
              ),
              const SliverSafeArea(sliver: HomePageBrowseSection()),
            ],
          ),
        ));
  }
}

class _WindowsHomeHero extends ConsumerWidget {
  const _WindowsHomeHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accounts = ref.watch(webDavAccountsProvider);
    final libraries = ref.watch(webDavLibraryProvider);
    final trackCount = libraries.values.fold<int>(
      0,
      (total, tracks) => total + tracks.length,
    );
    final isChinese = Localizations.localeOf(context).languageCode == 'zh';

    return SurfaceCard(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(28),
      borderColor: const Color(0x32FFFFFF),
      borderWidth: 1,
      fillColor: const Color(0xCE0A0E18),
      surfaceOpacity: 0.68,
      surfaceBlur: 26,
      boxShadow: const [
        BoxShadow(
          color: Color(0x58000000),
          blurRadius: 46,
          offset: Offset(0, 22),
        ),
      ],
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            const Positioned(
              top: -150,
              right: -90,
              child: _HeroGlow(),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final showArtwork = constraints.maxWidth >= 880;
                final compact = constraints.maxWidth < 600;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 20 : 34,
                    compact ? 22 : 30,
                    compact ? 20 : 32,
                    compact ? 22 : 30,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withAlpha(28),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color:
                                      theme.colorScheme.primary.withAlpha(76),
                                ),
                              ),
                              child: Text(
                                isChinese
                                    ? 'SPOTUBE · 私人音乐宇宙'
                                    : 'SPOTUBE · YOUR MUSIC UNIVERSE',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 10,
                                  letterSpacing: 1.35,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Gap(16),
                            Text(
                              isChinese
                                  ? '让你的音乐，在这里发光'
                                  : 'Let your music glow here',
                              style: theme.typography.h2.copyWith(
                                fontSize: compact ? 28 : 34,
                                height: 1.08,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const Gap(10),
                            Text(
                              isChinese
                                  ? '本地文件与 WebDAV 曲库汇聚在同一个沉浸式舞台。'
                                  : 'Local files and WebDAV libraries, together on one immersive stage.',
                              style: TextStyle(
                                color: theme.colorScheme.mutedForeground,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                            const Gap(20),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Button.outline(
                                onPressed: () =>
                                    context.navigateTo(const SearchRoute()),
                                leading: const Icon(
                                  SpotubeIcons.search,
                                  size: 18,
                                ),
                                trailing: Text(
                                  isChinese ? '搜索' : 'Search',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    isChinese
                                        ? '搜索歌曲、歌手或专辑'
                                        : 'Search songs, artists or albums',
                                    style: TextStyle(
                                      color: theme.colorScheme.mutedForeground,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const Gap(16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Button.primary(
                                  onPressed: () => context.navigateTo(
                                    const UserLocalLibraryRoute(),
                                  ),
                                  leading: const Icon(
                                    SpotubeIcons.device,
                                    size: 17,
                                  ),
                                  child: Text(context.l10n.local_library),
                                ),
                                _HeroMetric(
                                  value: '$trackCount',
                                  label: isChinese ? '首远程歌曲' : 'remote tracks',
                                ),
                                _HeroMetric(
                                  value: '${accounts.length}',
                                  label: 'WebDAV',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (showArtwork) ...[
                        const Gap(32),
                        const SizedBox(
                          width: 270,
                          height: 270,
                          child: _VinylStage(),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String value;
  final String label;

  const _HeroMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x20FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const Gap(5),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.mutedForeground,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroGlow extends StatelessWidget {
  const _HeroGlow();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 430,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0x3D704DFF), Color(0x00704DFF)],
          ),
        ),
      ),
    );
  }
}

class _VinylStage extends StatelessWidget {
  const _VinylStage();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 258,
          height: 258,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF090B11),
            border: Border.all(color: const Color(0x28FFFFFF)),
            boxShadow: [
              BoxShadow(
                color: primary.withAlpha(48),
                blurRadius: 52,
                spreadRadius: 3,
              ),
              const BoxShadow(
                color: Color(0x99000000),
                blurRadius: 32,
                offset: Offset(14, 22),
              ),
            ],
          ),
        ),
        for (final size in [220.0, 184.0, 146.0, 108.0])
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x18FFFFFF)),
            ),
          ),
        Container(
          width: 92,
          height: 92,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF775EFF), Color(0xFF1AAFE5)],
            ),
          ),
          child: const Icon(Icons.graphic_eq, color: Colors.white, size: 36),
        ),
        Container(
          width: 13,
          height: 13,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFE8ECFF),
          ),
        ),
        Positioned(
          top: 25,
          right: 22,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0x15FFFFFF),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x24FFFFFF)),
            ),
            child: Icon(SpotubeIcons.music, color: primary, size: 20),
          ),
        ),
      ],
    );
  }
}
