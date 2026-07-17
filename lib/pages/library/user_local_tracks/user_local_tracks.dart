import 'package:auto_route/auto_route.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/modules/library/local_folder/local_folder_item.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/modules/library/webdav/webdav_connection_dialog.dart';
import 'package:spotube/modules/library/webdav/webdav_library_item.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/webdav/webdav_accounts_provider.dart';
import 'package:spotube/utils/platform.dart';

enum SortBy {
  none,
  ascending,
  descending,
  newest,
  oldest,
  duration,
  artist,
  album,
}

@RoutePage()
class UserLocalLibraryPage extends HookConsumerWidget {
  static const name = 'user_local_library';
  const UserLocalLibraryPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final cacheDir = useFuture(UserPreferencesNotifier.getMusicCacheDir());
    final preferencesNotifier = ref.watch(userPreferencesProvider.notifier);
    final preferences = ref.watch(userPreferencesProvider);
    final webDavAccounts = ref.watch(webDavAccountsProvider);
    final webDavAccountsNotifier = ref.read(webDavAccountsProvider.notifier);

    final addLocalLibraryLocation = useCallback(() async {
      if (kIsMobile || kIsMacOS) {
        final dirStr = await FilePicker.platform.getDirectoryPath(
          initialDirectory: preferences.downloadLocation,
        );
        if (dirStr == null) return;
        if (preferences.localLibraryLocation.contains(dirStr)) return;
        preferencesNotifier.setLocalLibraryLocation(
            [...preferences.localLibraryLocation, dirStr]);
      } else {
        String? dirStr = await getDirectoryPath(
          initialDirectory: preferences.downloadLocation,
        );
        if (dirStr == null) return;
        if (preferences.localLibraryLocation.contains(dirStr)) return;
        preferencesNotifier.setLocalLibraryLocation(
            [...preferences.localLibraryLocation, dirStr]);
      }
    }, [preferences.localLibraryLocation]);

    Future<void> editWebDavAccount([WebDavAccount? account]) async {
      final result = await showDialog<WebDavAccount>(
        context: context,
        builder: (context) => WebDavConnectionDialog(account: account),
      );
      if (result == null) return;
      await webDavAccountsNotifier.upsert(result);
    }

    Future<void> removeWebDavAccount(WebDavAccount account) async {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.webdav_remove_confirmation(account.name)),
          actions: [
            Button.outline(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.cancel),
            ),
            Button.destructive(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.delete),
            ),
          ],
        ),
      );
      if (accepted == true) {
        await webDavAccountsNotifier.remove(account.id);
      }
    }

    // This is just to pre-load the tracks.
    // For now, this gets all of them.
    ref.watch(localTracksProvider);

    final locations = [
      preferences.downloadLocation,
      if (cacheDir.hasData) cacheDir.data!,
      ...preferences.localLibraryLocation,
    ];

    return LayoutBuilder(builder: (context, constrains) {
      final windowsStage = useImmersiveUi(context);
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: windowsStage && !kIsAndroid ? 24 : 12,
        ),
        child: Column(
          children: [
            if (windowsStage)
              _WindowsLibraryHeader(
                locationCount: locations.length,
                webDavCount: webDavAccounts.length,
                onAddFolder: addLocalLibraryLocation,
                onConnectWebDav: () => editWebDavAccount(),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    Button.secondary(
                      leading: const Icon(SpotubeIcons.folderAdd),
                      onPressed: addLocalLibraryLocation,
                      child: Text(context.l10n.add_library_location),
                    ),
                    Button.secondary(
                      leading: const Icon(SpotubeIcons.piped),
                      onPressed: () => editWebDavAccount(),
                      child: Text(context.l10n.connect_webdav),
                    ),
                  ],
                ),
              ),
            Gap(windowsStage ? 18 : 8),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.only(bottom: windowsStage ? 24 : 0),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: windowsStage && !kIsAndroid ? 270 : 200,
                  mainAxisExtent: windowsStage && !kIsAndroid
                      ? 280 * context.theme.scaling
                      : constrains.isXs
                          ? 230 * context.theme.scaling
                          : constrains.mdAndDown
                              ? 280 * context.theme.scaling
                              : 250 * context.theme.scaling,
                  crossAxisSpacing: windowsStage && !kIsAndroid ? 16 : 10,
                  mainAxisSpacing: windowsStage && !kIsAndroid ? 16 : 10,
                ),
                itemCount: locations.length + webDavAccounts.length,
                itemBuilder: (context, index) {
                  if (index >= locations.length) {
                    final account = webDavAccounts[index - locations.length];
                    return WebDavLibraryItem(
                      account: account,
                      onEdit: () => editWebDavAccount(account),
                      onRemove: () => removeWebDavAccount(account),
                    );
                  }
                  return LocalFolderItem(
                    folder: locations[index],
                  );
                },
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _WindowsLibraryHeader extends StatelessWidget {
  final int locationCount;
  final int webDavCount;
  final VoidCallback onAddFolder;
  final VoidCallback onConnectWebDav;

  const _WindowsLibraryHeader({
    required this.locationCount,
    required this.webDavCount,
    required this.onAddFolder,
    required this.onConnectWebDav,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isChinese = Localizations.localeOf(context).languageCode == 'zh';

    final icon = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF735CFF), Color(0xFF278EF0)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x443E78FF), blurRadius: 18),
        ],
      ),
      child: const Icon(SpotubeIcons.device, color: Colors.white),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.local_library,
          style: theme.typography.h3.copyWith(fontWeight: FontWeight.w700),
        ),
        const Gap(3),
        Text(
          isChinese
              ? '管理本机文件夹与 WebDAV 音乐空间'
              : 'Manage local folders and WebDAV music spaces',
          style: TextStyle(
            color: theme.colorScheme.mutedForeground,
            fontSize: 11,
          ),
        ),
        const Gap(8),
        Wrap(
          spacing: 8,
          children: [
            _LibraryCount(
              value: locationCount,
              label: isChinese ? '个本地位置' : 'local locations',
            ),
            _LibraryCount(value: webDavCount, label: 'WebDAV'),
          ],
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        Button.outline(
          leading: const Icon(SpotubeIcons.folderAdd, size: 17),
          onPressed: onAddFolder,
          child: Text(context.l10n.add_library_location),
        ),
        Button.primary(
          leading: const Icon(SpotubeIcons.piped, size: 17),
          onPressed: onConnectWebDav,
          child: Text(context.l10n.connect_webdav),
        ),
      ],
    );

    return SurfaceCard(
      padding: EdgeInsets.symmetric(
        horizontal: kIsAndroid ? 16 : 22,
        vertical: 18,
      ),
      borderRadius: BorderRadius.circular(22),
      borderColor: const Color(0x2BFFFFFF),
      borderWidth: 1,
      fillColor: const Color(0xC90B0F19),
      surfaceOpacity: 0.66,
      surfaceBlur: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final heading = Row(
            children: [icon, const Gap(15), Expanded(child: details)],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const Gap(14),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              icon,
              const Gap(15),
              Expanded(child: details),
              const Gap(16),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _LibraryCount extends StatelessWidget {
  final int value;
  final String label;

  const _LibraryCount({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$value $label',
      style: TextStyle(
        color: Theme.of(context).colorScheme.mutedForeground,
        fontSize: 10,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
