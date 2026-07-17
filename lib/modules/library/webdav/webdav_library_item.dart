import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/provider/webdav/webdav_library_provider.dart';
import 'package:spotube/services/webdav/webdav_metadata_status.dart';

class WebDavLibraryItem extends HookConsumerWidget {
  final WebDavAccount account;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const WebDavLibraryItem({
    super.key,
    required this.account,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final scanning = useState(false);
    final rematchingUnmatched = useState(false);
    final metadataJob = ref.watch(
      webDavMetadataJobProvider.select((jobs) => jobs[account.id]),
    );
    final matchingMetadata = metadataJob?.isMatching == true;
    final scanSummary = ref.watch(
      webDavLibraryProvider.select(
        (state) => (
          hasScanned: state.containsKey(account.id),
          count: state[account.id]?.length ?? 0,
          unmatched:
              webDavUnmatchedTracks(state[account.id] ?? const []).length,
        ),
      ),
    );

    void showMessage(String message) {
      showToast(
        context: context,
        location: ToastLocation.topRight,
        builder: (context, overlay) => SurfaceCard(
          child: Basic(title: Text(message)),
        ),
      );
    }

    Future<void> scanMusic() async {
      if (scanning.value || matchingMetadata) return;
      scanning.value = true;
      try {
        final tracks =
            await ref.read(webDavLibraryProvider.notifier).scan(account);
        if (context.mounted) {
          showMessage(context.l10n.webdav_scan_complete(tracks.length));
        }
      } on Exception catch (error) {
        if (context.mounted) showMessage(error.toString());
      } finally {
        if (context.mounted) scanning.value = false;
      }
    }

    Future<void> matchMetadata() async {
      if (scanning.value || matchingMetadata) return;
      if (!scanSummary.hasScanned || scanSummary.count == 0) {
        showMessage(context.l10n.webdav_match_metadata_scan_first);
        return;
      }

      try {
        final summary = await ref
            .read(webDavLibraryProvider.notifier)
            .matchMetadata(account);
        if (context.mounted) {
          showMessage(
            context.l10n.webdav_match_metadata_complete(
              summary.matched,
              summary.lyricsCached,
              summary.unmatched,
              summary.failed,
            ),
          );
        }
      } on Exception catch (error) {
        if (context.mounted) showMessage(error.toString());
      }
    }

    Future<void> rematchUnmatchedMetadata() async {
      if (scanning.value ||
          matchingMetadata ||
          rematchingUnmatched.value ||
          scanSummary.unmatched == 0) {
        if (scanSummary.unmatched == 0) {
          showMessage(context.l10n.webdav_no_unmatched_tracks);
        }
        return;
      }
      rematchingUnmatched.value = true;
      try {
        final summary = await ref
            .read(webDavLibraryProvider.notifier)
            .rematchUnmatchedMetadata(account);
        if (context.mounted) {
          showMessage(
            context.l10n.webdav_match_metadata_complete(
              summary.matched,
              summary.lyricsCached,
              summary.unmatched,
              summary.failed,
            ),
          );
        }
      } on Exception catch (error) {
        if (context.mounted) showMessage(error.toString());
      } finally {
        if (context.mounted) rematchingUnmatched.value = false;
      }
    }

    void openLibrary({required bool unmatchedOnly}) {
      final filter = ref.read(webDavUnmatchedFilterRequestProvider.notifier);
      filter.state = unmatchedOnly
          ? {...filter.state, account.id}
          : (Set<String>.of(filter.state)..remove(account.id));
      context.navigateTo(
        LocalLibraryRoute(
          location: webDavLibraryLocationKey(account.id),
        ),
      );
    }

    return Button(
      onPressed: () {
        if (scanSummary.count > 0) {
          openLibrary(unmatchedOnly: false);
        } else {
          context.navigateTo(WebDavBrowserRoute(accountId: account.id));
        }
      },
      style: ButtonVariance.card.copyWith(
        padding: (context, states, value) => const EdgeInsets.all(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.primary.withAlpha(24),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                SpotubeIcons.piped,
                size: 72,
                color: colorScheme.primary,
              ),
            ),
          ),
          const Gap(10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).semiBold(),
                    Text(
                      '${account.rootUri.host}${account.rootDisplayPath}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).xSmall().muted(),
                    if (scanSummary.hasScanned)
                      Text(
                        context.l10n.webdav_scanned_tracks(scanSummary.count),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).xSmall().muted(),
                    if (scanSummary.unmatched > 0)
                      Text(
                        context.l10n
                            .webdav_filter_unmatched(scanSummary.unmatched),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).xSmall().muted(),
                    if (metadataJob?.phase == WebDavMetadataJobPhase.matching)
                      Text(
                        context.l10n.webdav_metadata_progress(
                          metadataJob!.completed,
                          metadataJob.total,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).xSmall().muted(),
                    if (metadataJob?.summary case final summary?)
                      Text(
                        context.l10n.webdav_match_metadata_complete(
                          summary.matched,
                          summary.lyricsCached,
                          summary.unmatched,
                          summary.failed,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).xSmall().muted(),
                    if (metadataJob?.phase == WebDavMetadataJobPhase.failed)
                      Text(
                        context.l10n.webdav_metadata_failed,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).xSmall().muted(),
                  ],
                ),
              ),
              IconButton.ghost(
                icon: const Icon(SpotubeIcons.moreVertical),
                size: ButtonSize.small,
                onPressed: () {
                  showDropdown(
                    context: context,
                    builder: (context) => DropdownMenu(
                      children: [
                        MenuButton(
                          leading: scanning.value
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(),
                                )
                              : const Icon(SpotubeIcons.refresh),
                          enabled: !scanning.value && !matchingMetadata,
                          onPressed: (_) => scanMusic(),
                          child: Text(
                            scanning.value
                                ? context.l10n.webdav_scanning_music
                                : context.l10n.webdav_scan_music,
                          ),
                        ),
                        MenuButton(
                          leading: const Icon(SpotubeIcons.filter),
                          enabled: scanSummary.unmatched > 0,
                          onPressed: (_) {
                            openLibrary(unmatchedOnly: true);
                          },
                          child: Text(
                            context.l10n.webdav_view_unmatched_tracks(
                              scanSummary.unmatched,
                            ),
                          ),
                        ),
                        MenuButton(
                          leading: rematchingUnmatched.value
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(),
                                )
                              : const Icon(SpotubeIcons.magic),
                          enabled: scanSummary.unmatched > 0 &&
                              !scanning.value &&
                              !matchingMetadata &&
                              !rematchingUnmatched.value,
                          onPressed: (_) => rematchUnmatchedMetadata(),
                          child: Text(
                            context.l10n.webdav_rematch_unmatched,
                          ),
                        ),
                        MenuButton(
                          leading: matchingMetadata
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(),
                                )
                              : const Icon(SpotubeIcons.magic),
                          enabled: !scanning.value && !matchingMetadata,
                          onPressed: (_) => matchMetadata(),
                          child: Text(
                            matchingMetadata
                                ? context.l10n.webdav_matching_metadata
                                : context.l10n.webdav_match_metadata,
                          ),
                        ),
                        MenuButton(
                          leading: const Icon(SpotubeIcons.folder),
                          onPressed: (_) {
                            context.navigateTo(
                              WebDavBrowserRoute(accountId: account.id),
                            );
                          },
                          child: Text(context.l10n.webdav_browse_files),
                        ),
                        MenuButton(
                          leading: const Icon(SpotubeIcons.edit),
                          onPressed: (context) => onEdit(),
                          child: Text(context.l10n.edit),
                        ),
                        MenuButton(
                          leading: Icon(
                            SpotubeIcons.delete,
                            color: colorScheme.destructive,
                          ),
                          onPressed: (context) => onRemove(),
                          child: Text(context.l10n.delete),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
