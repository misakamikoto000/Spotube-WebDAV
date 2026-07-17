import 'dart:async';
import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/discord_provider.dart';
import 'package:spotube/provider/history/history.dart';
import 'package:spotube/provider/history/history_utils.dart';
import 'package:spotube/provider/metadata_plugin/core/scrobble.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/skip_segments/skip_segments.dart';
import 'package:spotube/provider/scrobbler/scrobbler.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/audio_services/audio_services.dart';
import 'package:spotube/services/logger/logger.dart';

class AudioPlayerStreamListeners {
  final Ref ref;
  late final AudioServices notificationService;
  AudioPlayerStreamListeners(this.ref) {
    AudioServices.create(ref, ref.read(audioPlayerProvider.notifier)).then(
      (value) => notificationService = value,
    );

    final subscriptions = [
      subscribeToPlaylist(),
      subscribeToSkipSponsor(),
      subscribeToScrobbleChanged(),
      subscribeToPosition(),
      subscribeToPlayerError(),
    ];

    ref.onDispose(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    });
  }

  ScrobblerNotifier get scrobbler => ref.read(scrobblerProvider.notifier);
  UserPreferences get preferences => ref.read(userPreferencesProvider);
  DiscordNotifier get discord => ref.read(discordProvider.notifier);
  AudioPlayerState get audioPlayerState => ref.read(audioPlayerProvider);
  PlaybackHistoryActions get history =>
      ref.read(playbackHistoryActionsProvider);

  StreamSubscription subscribeToPlaylist() {
    return audioPlayer.playlistStream.listen((mpvPlaylist) {
      try {
        if (audioPlayerState.activeTrack == null) return;
        notificationService.addTrack(audioPlayerState.activeTrack!);
        discord.updatePresence(audioPlayerState.activeTrack!);
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });
  }

  StreamSubscription subscribeToSkipSponsor() {
    return audioPlayer.positionStream.listen((position) async {
      try {
        final currentSegments = await ref.read(segmentProvider.future);

        if (currentSegments?.segments.isNotEmpty != true ||
            position < const Duration(seconds: 3)) {
          return;
        }

        for (final segment in currentSegments!.segments) {
          final seconds = position.inSeconds;

          if (seconds < segment.start || seconds >= segment.end) continue;

          await audioPlayer.seek(Duration(seconds: segment.end + 1));
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });
  }

  StreamSubscription subscribeToScrobbleChanged() {
    final historyTracker = PlaybackHistoryScrobbleTracker();
    return audioPlayer.positionStream.listen((position) async {
      String? uid;
      try {
        final currentTrack = audioPlayerState.activeTrack;
        if (currentTrack == null) return;
        uid = playbackHistoryTrackKey(currentTrack);
        if (!historyTracker.shouldRecord(
          uid: uid,
          position: position,
          duration: audioPlayer.duration,
        )) {
          return;
        }

        /// The [Track] from Playlist.getTracks doesn't contain artist images
        /// so we try to fetch them from the API for remote tracks. Local and
        /// WebDAV tracks must never depend on an online metadata plugin.
        var historyTrack = prepareTrackForPlaybackHistory(currentTrack);
        if (historyTrack is! SpotubeLocalTrackObject &&
            historyTrack.artists.any((artist) => artist.images == null)) {
          try {
            final metadataPlugin =
                await ref.read(metadataPluginProvider.future);
            if (metadataPlugin != null) {
              final artists = await Future.wait(
                historyTrack.artists.map((artist) async {
                  if (artist.images != null) return artist;
                  try {
                    final fullArtist =
                        await metadataPlugin.artist.getArtist(artist.id);
                    return SpotubeSimpleArtistObject.fromJson(
                      fullArtist.toJson(),
                    );
                  } catch (error, stack) {
                    AppLogger.reportError(error, stack);
                    return artist;
                  }
                }),
              );
              historyTrack = historyTrack.copyWith(artists: artists);
            }
          } catch (error, stack) {
            AppLogger.reportError(error, stack);
          }
        }
        historyTrack = ensurePlaybackHistoryArtistImages(historyTrack);

        // Local history is the source of truth for the statistics page. Only
        // mark this listen as handled after the database write succeeds.
        await history.addTrack(historyTrack);
        historyTracker.markRecorded(uid);

        scrobbler.scrobble(currentTrack);
        ref
            .read(metadataPluginScrobbleProvider.notifier)
            .scrobble(currentTrack);
      } catch (e, stack) {
        if (uid != null) historyTracker.markFailed(uid);
        AppLogger.reportError(e, stack);
      }
    });
  }

  StreamSubscription subscribeToPosition() {
    String lastTrack = ""; // used to prevent multiple calls to the same track
    return audioPlayer.positionStream.listen((event) async {
      final percentProgress =
          (event.inSeconds / max(audioPlayer.duration.inSeconds, 1)) * 100;
      try {
        if (percentProgress < 80 ||
            audioPlayerState.currentIndex == -1 ||
            audioPlayerState.currentIndex ==
                audioPlayerState.tracks.length - 1) {
          return;
        }
        final nextTrack = audioPlayerState.tracks
            .elementAtOrNull(audioPlayerState.currentIndex + 1);

        if (nextTrack == null ||
            lastTrack == nextTrack.id ||
            nextTrack is SpotubeLocalTrackObject) {
          return;
        }

        try {
          await ref.read(
            sourcedTrackProvider(nextTrack as SpotubeFullTrackObject).future,
          );
        } finally {
          lastTrack = nextTrack.id;
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });
  }

  StreamSubscription subscribeToPlayerError() {
    return audioPlayer.errorStream.listen((event) {});
  }
}

final audioPlayerStreamListenersProvider =
    Provider<AudioPlayerStreamListeners>(AudioPlayerStreamListeners.new);
