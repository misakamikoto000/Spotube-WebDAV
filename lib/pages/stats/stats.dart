import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/components/windows/windows_page_header.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/stats/summary/summary.dart';
import 'package:spotube/modules/stats/top/top.dart';
import 'package:spotube/utils/platform.dart';
import 'package:auto_route/auto_route.dart';

@RoutePage()
class StatsPage extends HookConsumerWidget {
  static const name = "stats";

  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final windowsStage = useImmersiveUi(context);
    final isChinese = Localizations.localeOf(context).languageCode == 'zh';
    final content = CustomScrollView(
      slivers: [
        if (kIsMacOS) const SliverGap(20),
        const StatsPageSummarySection(),
        const StatsPageTopSection(),
        const SliverToBoxAdapter(
          child: SafeArea(
            child: SizedBox(height: 140),
          ),
        ),
      ],
    );

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
                height: windowsStage ? 30 : null,
                backgroundColor: windowsStage ? Colors.transparent : null,
                surfaceBlur: windowsStage ? 0 : null,
              ),
          ],
          child: windowsStage
              ? Padding(
                  padding: EdgeInsets.fromLTRB(
                    kIsAndroid ? 8 : 12,
                    8,
                    kIsAndroid ? 8 : 24,
                    MediaQuery.paddingOf(context).bottom + 14,
                  ),
                  child: Column(
                    children: [
                      WindowsPageHeader(
                        icon: SpotubeIcons.chart,
                        title: context.l10n.stats,
                        subtitle: isChinese
                            ? '聆听时长、播放次数与最常播放内容'
                            : 'Listening time, play counts and your favorites',
                      ),
                      const Gap(10),
                      Expanded(
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
                            child: content,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : content,
        ),
      ),
    );
  }
}
