import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/framework/app_pop_scope.dart';
import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/components/track_tile/track_tile.dart';
import 'package:spotube/components/ui/button_tile.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/webdav/webdav_accounts_provider.dart';
import 'package:spotube/services/webdav/webdav_client.dart';
import 'package:spotube/utils/platform.dart';

@RoutePage()
class WebDavBrowserPage extends HookConsumerWidget {
  final String accountId;

  const WebDavBrowserPage({super.key, required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compactHeader = kIsMobile && MediaQuery.sizeOf(context).width < 600;
    final androidSafeTop = kIsAndroid ? 6.0 : 0.0;
    final accounts = ref.watch(webDavAccountsProvider);
    WebDavAccount? account;
    for (final value in accounts) {
      if (value.id == accountId) {
        account = value;
        break;
      }
    }

    final fallbackUri = Uri.parse('https://localhost/');
    final pathStack = useState<List<Uri>>([
      account?.rootUri ?? fallbackUri,
    ]);
    final refreshKey = useState(0);
    final addingToLibrary = useState(false);
    final client = useMemoized(
      () => account == null ? null : WebDavClient(account),
      [account],
    );

    useEffect(() {
      return client?.close;
    }, [client]);
    useEffect(() {
      if (account != null) pathStack.value = [account.rootUri];
      return null;
    }, [account?.url, account?.rootPath]);

    final currentUri = pathStack.value.last;
    final entriesFuture = useMemoized(
      () => client == null
          ? Future<List<WebDavEntry>>.value(const [])
          : client.list(currentUri),
      [client, currentUri, refreshKey.value],
    );
    final snapshot = useFuture(entriesFuture);
    final playlist = ref.watch(audioPlayerProvider);
    final playback = ref.read(audioPlayerProvider.notifier);

    void goBack() {
      if (pathStack.value.length > 1) {
        pathStack.value = pathStack.value.sublist(
          0,
          pathStack.value.length - 1,
        );
      } else {
        Navigator.of(context).pop();
      }
    }

    if (account == null) {
      return SafeArea(
        bottom: false,
        minimum: EdgeInsets.only(top: androidSafeTop),
        child: Scaffold(
          backgroundColor: kIsAndroid ? Colors.transparent : null,
          headers: [
            TitleBar(
              title: Text(context.l10n.webdav),
              backgroundColor: kIsAndroid ? Colors.transparent : null,
              surfaceBlur: kIsAndroid ? 0 : null,
            ),
          ],
          child: Center(child: Text(context.l10n.webdav_account_not_found)),
        ),
      );
    }
    final resolvedAccount = account;

    final selectedRootPath = resolvedAccount.rootPathFor(currentUri);
    final isCurrentLibraryFolder = selectedRootPath ==
        WebDavAccount.normalizeRootPath(resolvedAccount.rootPath);

    void showMessage(String message) {
      showToast(
        context: context,
        location: ToastLocation.topRight,
        builder: (context, overlay) => SurfaceCard(
          child: Basic(title: Text(message)),
        ),
      );
    }

    Future<void> addCurrentFolderToLibrary() async {
      if (addingToLibrary.value || isCurrentLibraryFolder) return;
      addingToLibrary.value = true;
      try {
        final updatedAccount = resolvedAccount.copyWith(
          rootPath: selectedRootPath,
        );
        await ref.read(webDavAccountsProvider.notifier).upsert(updatedAccount);
        if (context.mounted) {
          showMessage(
            context.l10n.webdav_folder_added_to_library(
              updatedAccount.rootDisplayPath,
            ),
          );
        }
      } on Exception catch (error) {
        if (context.mounted) showMessage(error.toString());
      } finally {
        if (context.mounted) addingToLibrary.value = false;
      }
    }

    final visibleEntries = (snapshot.data ?? const <WebDavEntry>[])
        .where((entry) => entry.isDirectory || entry.isSupportedAudio)
        .toList(growable: false);
    final audioEntries = visibleEntries
        .where((entry) => entry.isSupportedAudio)
        .toList(growable: false);
    final tracks = audioEntries
        .map((entry) => entry.toTrack(resolvedAccount))
        .toList(growable: false);
    final relativePath = account.rootUri.path == currentUri.path
        ? '/'
        : currentUri.path.replaceFirst(account.rootUri.path, '/');

    return SafeArea(
      bottom: false,
      minimum: EdgeInsets.only(top: androidSafeTop),
      child: AppPopScope(
        canPop: pathStack.value.length == 1,
        onPopInvoked: (didPop) {
          if (!didPop) goBack();
        },
        child: Scaffold(
          backgroundColor: kIsAndroid ? Colors.transparent : null,
          headers: [
            TitleBar(
              automaticallyImplyLeading: false,
              height: compactHeader ? 58 : null,
              backgroundColor: kIsAndroid ? Colors.transparent : null,
              surfaceBlur: kIsAndroid ? 0 : null,
              leading: [
                IconButton.ghost(
                  size: const ButtonSize(1.2),
                  icon: const Icon(SpotubeIcons.angleLeft),
                  onPressed: goBack,
                ),
              ],
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    relativePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).xSmall().muted(),
                ],
              ),
              trailing: [
                if (compactHeader)
                  IconButton.ghost(
                    icon: addingToLibrary.value
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(),
                          )
                        : Icon(
                            isCurrentLibraryFolder
                                ? SpotubeIcons.done
                                : SpotubeIcons.folderAdd,
                          ),
                    onPressed: addingToLibrary.value || isCurrentLibraryFolder
                        ? null
                        : addCurrentFolderToLibrary,
                  )
                else
                  Button.outline(
                    leading: addingToLibrary.value
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(),
                          )
                        : Icon(
                            isCurrentLibraryFolder
                                ? SpotubeIcons.done
                                : SpotubeIcons.folderAdd,
                          ),
                    enabled: !addingToLibrary.value && !isCurrentLibraryFolder,
                    onPressed: addCurrentFolderToLibrary,
                    child: Text(
                      isCurrentLibraryFolder
                          ? context.l10n.webdav_current_library_folder
                          : context.l10n.webdav_add_folder_to_library,
                    ),
                  ),
                IconButton.ghost(
                  icon: const Icon(SpotubeIcons.refresh),
                  onPressed: snapshot.connectionState == ConnectionState.waiting
                      ? null
                      : () => refreshKey.value++,
                ),
              ],
            ),
          ],
          child: Builder(
            builder: (context) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(SpotubeIcons.error, size: 48),
                      const Gap(12),
                      Text(snapshot.error.toString(),
                          textAlign: TextAlign.center),
                      const Gap(12),
                      Button.secondary(
                        onPressed: () => refreshKey.value++,
                        child: Text(context.l10n.retry),
                      ),
                    ],
                  ),
                );
              }
              if (visibleEntries.isEmpty) {
                return Center(child: Text(context.l10n.webdav_empty_folder));
              }

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 180),
                itemCount: visibleEntries.length,
                itemBuilder: (context, index) {
                  final entry = visibleEntries[index];
                  if (entry.isDirectory) {
                    return ButtonTile(
                      style: ButtonVariance.ghost,
                      leading: const Icon(SpotubeIcons.folder),
                      title: Text(entry.displayName),
                      trailing: const Icon(SpotubeIcons.angleRight),
                      onPressed: () {
                        pathStack.value = [...pathStack.value, entry.uri];
                      },
                    );
                  }

                  final trackIndex = audioEntries.indexOf(entry);
                  final track = tracks[trackIndex];
                  return TrackTile(
                    index: trackIndex,
                    playlist: playlist,
                    track: track,
                    userPlaylist: false,
                    onTap: () async {
                      await playback.load(
                        tracks,
                        initialIndex: trackIndex,
                        autoPlay: true,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
