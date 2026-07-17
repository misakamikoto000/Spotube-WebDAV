import 'package:auto_size_text/auto_size_text.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/windows/windows_page_header.dart';
import 'package:spotube/modules/library/user_downloads/download_item.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/utils/platform.dart';
import 'package:auto_route/auto_route.dart';

@RoutePage()
class UserDownloadsPage extends HookConsumerWidget {
  static const name = 'user_downloads';
  const UserDownloadsPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final downloadQueue = ref.watch(downloadManagerProvider);
    final downloadManagerNotifier = ref.watch(downloadManagerProvider.notifier);
    final windowsStage = useImmersiveUi(context);
    final isChinese = Localizations.localeOf(context).languageCode == 'zh';

    final cancelButton = Button.destructive(
      onPressed:
          downloadQueue.isEmpty ? null : downloadManagerNotifier.clearAll,
      child: Text(context.l10n.cancel_all),
    );

    final downloadList = ListView.builder(
      itemCount: downloadQueue.length,
      padding: const EdgeInsets.only(bottom: 200),
      itemBuilder: (context, index) {
        return DownloadItem(
          task: downloadQueue.elementAt(index),
        );
      },
    );

    if (windowsStage) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          kIsAndroid ? 8 : 12,
          8,
          kIsAndroid ? 8 : 24,
          MediaQuery.paddingOf(context).bottom + 14,
        ),
        child: Column(
          children: [
            WindowsPageHeader(
              icon: SpotubeIcons.download,
              title: context.l10n.downloads,
              subtitle: isChinese
                  ? '管理正在下载和等待中的音乐'
                  : 'Manage active and queued music downloads',
              trailing: cancelButton,
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
                  child: downloadQueue.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                SpotubeIcons.download,
                                size: 44,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const Gap(12),
                              Text(context.l10n.currently_downloading(0))
                                  .muted(),
                            ],
                          ),
                        )
                      : downloadList,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: AutoSizeText(
                  context.l10n.currently_downloading(downloadQueue.length),
                  maxLines: 1,
                ).semiBold(),
              ),
              const SizedBox(width: 10),
              cancelButton,
            ],
          ),
        ),
        Expanded(
          child: SafeArea(
            child: downloadList,
          ),
        ),
      ],
    );
  }
}
