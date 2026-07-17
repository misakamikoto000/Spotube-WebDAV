import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/components/windows/windows_page_header.dart';
import 'package:spotube/utils/platform.dart';

class StatsDetailScaffold extends StatelessWidget {
  final String title;
  final Widget child;

  const StatsDetailScaffold({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final windowsStage = useImmersiveUi(context);
    final isChinese = Localizations.localeOf(context).languageCode == 'zh';

    return SafeArea(
      bottom: false,
      child: Scaffold(
        backgroundColor: windowsStage ? Colors.transparent : null,
        headers: [
          TitleBar(
            title: windowsStage ? null : Text(title),
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
                      title: title,
                      subtitle: isChinese
                          ? '查看完整的本地听歌记录'
                          : 'Explore your complete local listening history',
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
                          child: child,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : child,
      ),
    );
  }
}
