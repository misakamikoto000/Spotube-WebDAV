import 'dart:math';

import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/webdav/chinese_metadata_normalizer.dart';

/// Gives local/WebDAV tracks artist images without requiring an online
/// metadata plugin. The album artwork is already cached on the device and is
/// a suitable fallback for statistics/history cards.
SpotubeTrackObject prepareTrackForPlaybackHistory(SpotubeTrackObject track) {
  if (track is! SpotubeLocalTrackObject) return track;
  return ensurePlaybackHistoryArtistImages(track);
}

/// History entries require a non-null image list for every artist. An empty
/// list is valid and prevents an unavailable metadata service from blocking
/// the history write.
SpotubeTrackObject ensurePlaybackHistoryArtistImages(
  SpotubeTrackObject track,
) {
  if (track.artists.every((artist) => artist.images != null)) return track;

  return track.copyWith(
    artists: track.artists
        .map(
          (artist) => artist.images == null
              ? artist.copyWith(images: track.album.images)
              : artist,
        )
        .toList(growable: false),
  );
}

String playbackHistoryTrackKey(SpotubeTrackObject track) =>
    track is SpotubeLocalTrackObject ? track.path : track.id;

String playbackHistoryArtistKey(SpotubeSimpleArtistObject artist) {
  final normalizedName = ChineseMetadataNormalizer.key(artist.name);
  return normalizedName.isEmpty ? artist.id : normalizedName;
}

String playbackHistoryAlbumKey(SpotubeSimpleAlbumObject album) {
  final albumName = ChineseMetadataNormalizer.albumKey(album.name);
  final artistNames = album.artists
      .map(playbackHistoryArtistKey)
      .where((name) => name.isNotEmpty)
      .toSet()
      .toList(growable: false)
    ..sort();
  final key = '$albumName|${artistNames.join('|')}';
  return key == '|' ? album.id : key;
}

({DateTime start, DateTime end}) playbackHistoryMonthRange(DateTime now) => (
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 1),
    );

/// Tracks whether the current play has already crossed the history threshold.
/// A jump back to the beginning after it was recorded is treated as a replay,
/// so repeat-one mode creates one history entry per completed listen.
class PlaybackHistoryScrobbleTracker {
  String? _activeUid;
  String? _recordedUid;
  String? _pendingUid;
  Duration _previousPosition = Duration.zero;

  bool shouldRecord({
    required String uid,
    required Duration position,
    required Duration duration,
  }) {
    final minimumListenSeconds = min(duration.inSeconds ~/ 2, 240);
    final changedTrack = _activeUid != uid;
    final restarted = !changedTrack &&
        _recordedUid == uid &&
        position <= const Duration(seconds: 5) &&
        _previousPosition > position + const Duration(seconds: 5);

    if (changedTrack || restarted) {
      _activeUid = uid;
      _recordedUid = null;
      _pendingUid = null;
    }
    _previousPosition = position;

    if (duration == Duration.zero ||
        position == Duration.zero ||
        position.inSeconds < minimumListenSeconds ||
        _recordedUid == uid ||
        _pendingUid == uid) {
      return false;
    }

    _pendingUid = uid;
    return true;
  }

  void markRecorded(String uid) {
    if (_activeUid == uid) _recordedUid = uid;
    if (_pendingUid == uid) _pendingUid = null;
  }

  void markFailed(String uid) {
    if (_pendingUid == uid) _pendingUid = null;
  }
}
