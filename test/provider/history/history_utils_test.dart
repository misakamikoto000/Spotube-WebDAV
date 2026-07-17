import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/history/history_utils.dart';

void main() {
  group('prepareTrackForPlaybackHistory', () {
    test('uses cached album artwork for a WebDAV artist', () {
      final track = _localTrack(
        artistImages: null,
        albumImages: [
          SpotubeImageObject(
            url: 'file:///cached/cover.jpg',
            width: 300,
            height: 300,
          ),
        ],
      );

      final prepared = prepareTrackForPlaybackHistory(track);

      expect(prepared, isA<SpotubeLocalTrackObject>());
      expect(prepared.artists.single.images, track.album.images);
    });

    test('uses a non-null empty image list when no cover is available', () {
      final prepared = prepareTrackForPlaybackHistory(
        _localTrack(artistImages: null),
      );

      expect(prepared.artists.single.images, isEmpty);
      expect(prepared.artists.single.images, isNotNull);
    });

    test('does not alter a remote track that may use its metadata plugin', () {
      final artist = _artist(images: null);
      final remote = SpotubeFullTrackObject(
        id: 'remote-id',
        name: 'Song',
        externalUri: 'https://example.test/song',
        artists: [artist],
        album: _album(artist: artist),
        durationMs: 240000,
        isrc: 'TEST00000001',
        explicit: false,
      );

      expect(prepareTrackForPlaybackHistory(remote), same(remote));
      expect(remote.artists.single.images, isNull);
    });
  });

  group('history identity', () {
    test('uses the stable WebDAV path instead of changing metadata ids', () {
      final first = _localTrack(id: 'musicbrainz:track-1');
      final rematched = _localTrack(id: 'qq:track-9');

      expect(
          playbackHistoryTrackKey(first), playbackHistoryTrackKey(rematched));
    });

    test('merges traditional and simplified artist names', () {
      final traditional = _artist(name: '周杰倫');
      final simplified = _artist(id: 'qq:artist-2', name: '周杰伦');

      expect(
        playbackHistoryArtistKey(traditional),
        playbackHistoryArtistKey(simplified),
      );
    });
  });

  group('PlaybackHistoryScrobbleTracker', () {
    test('records at 50 percent and does not duplicate stream events', () {
      final tracker = PlaybackHistoryScrobbleTracker();

      expect(
        tracker.shouldRecord(
          uid: 'song',
          position: const Duration(seconds: 119),
          duration: const Duration(seconds: 240),
        ),
        isFalse,
      );
      expect(
        tracker.shouldRecord(
          uid: 'song',
          position: const Duration(seconds: 120),
          duration: const Duration(seconds: 240),
        ),
        isTrue,
      );
      expect(
        tracker.shouldRecord(
          uid: 'song',
          position: const Duration(seconds: 121),
          duration: const Duration(seconds: 240),
        ),
        isFalse,
      );
      tracker.markRecorded('song');
      expect(
        tracker.shouldRecord(
          uid: 'song',
          position: const Duration(seconds: 180),
          duration: const Duration(seconds: 240),
        ),
        isFalse,
      );
    });

    test('records the same track again after repeat-one restarts it', () {
      final tracker = PlaybackHistoryScrobbleTracker();
      expect(
        tracker.shouldRecord(
          uid: 'song',
          position: const Duration(seconds: 120),
          duration: const Duration(seconds: 240),
        ),
        isTrue,
      );
      tracker.markRecorded('song');
      expect(
        tracker.shouldRecord(
          uid: 'song',
          position: const Duration(seconds: 1),
          duration: const Duration(seconds: 240),
        ),
        isFalse,
      );
      expect(
        tracker.shouldRecord(
          uid: 'song',
          position: const Duration(seconds: 120),
          duration: const Duration(seconds: 240),
        ),
        isTrue,
      );
    });

    test('retries after a database write fails', () {
      final tracker = PlaybackHistoryScrobbleTracker();
      expect(
        tracker.shouldRecord(
          uid: 'song',
          position: const Duration(seconds: 120),
          duration: const Duration(seconds: 240),
        ),
        isTrue,
      );
      tracker.markFailed('song');
      expect(
        tracker.shouldRecord(
          uid: 'song',
          position: const Duration(seconds: 121),
          duration: const Duration(seconds: 240),
        ),
        isTrue,
      );
    });
  });

  test('monthly range includes the 31st and excludes the next month', () {
    final range = playbackHistoryMonthRange(DateTime(2026, 7, 16));

    expect(range.start, DateTime(2026, 7, 1));
    expect(range.end, DateTime(2026, 8, 1));
    expect(DateTime(2026, 7, 31, 23, 59).isBefore(range.end), isTrue);
    expect(DateTime(2026, 8, 1).isBefore(range.end), isFalse);
  });
}

SpotubeLocalTrackObject _localTrack({
  String id = 'musicbrainz:track-1',
  List<SpotubeImageObject>? artistImages = const [],
  List<SpotubeImageObject> albumImages = const [],
}) {
  final artist = _artist(images: artistImages);
  return SpotubeLocalTrackObject(
    id: id,
    name: 'Song',
    externalUri: 'https://dav.example.test/music/song.flac',
    artists: [artist],
    album: _album(artist: artist, images: albumImages),
    durationMs: 240000,
    path: '/music/song.flac',
    webDavAccountId: 'account-1',
  );
}

SpotubeSimpleArtistObject _artist({
  String id = 'musicbrainz:artist-1',
  String name = 'Artist',
  List<SpotubeImageObject>? images = const [],
}) {
  return SpotubeSimpleArtistObject(
    id: id,
    name: name,
    externalUri: 'https://example.test/artist',
    images: images,
  );
}

SpotubeSimpleAlbumObject _album({
  required SpotubeSimpleArtistObject artist,
  List<SpotubeImageObject> images = const [],
}) {
  return SpotubeSimpleAlbumObject(
    id: 'musicbrainz:album-1',
    name: 'Album',
    externalUri: 'https://example.test/album',
    artists: [artist],
    albumType: SpotubeAlbumType.album,
    images: images,
  );
}
