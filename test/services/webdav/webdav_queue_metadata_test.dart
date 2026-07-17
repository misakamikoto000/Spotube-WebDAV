import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/webdav/webdav_queue_metadata.dart';

void main() {
  test('replaces stale queue metadata by WebDAV path', () {
    final stale = _track(
      albumName: 'Unknown Album',
      durationMs: 0,
      images: const [],
    );
    final matched = _track(
      albumName: '叶惠美',
      durationMs: 315413,
      images: [
        SpotubeImageObject(
          url: 'C:/Spotube/covers/yehuimei.jpg',
          width: 250,
          height: 250,
        ),
      ],
    );

    final queue = mergeWebDavQueueMetadata([stale], [matched]);
    final updated = queue.single as SpotubeLocalTrackObject;

    expect(updated.album.name, '叶惠美');
    expect(updated.album.images.single.url, contains('yehuimei.jpg'));
    expect(updated.durationMs, 315413);
  });
}

SpotubeLocalTrackObject _track({
  required String albumName,
  required int durationMs,
  required List<SpotubeImageObject> images,
}) {
  final artist = SpotubeSimpleArtistObject(
    id: 'musicbrainz:artist-1',
    name: '周杰伦',
    externalUri: '',
  );
  return SpotubeLocalTrackObject(
    id: 'track-1',
    name: '东风破',
    externalUri: 'https://dav.example/Music/东风破.flac',
    artists: [artist],
    album: SpotubeSimpleAlbumObject(
      id: 'album-1',
      name: albumName,
      externalUri: '',
      artists: [artist],
      images: images,
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: durationMs,
    path: 'https://dav.example/Music/东风破.flac',
    webDavAccountId: 'account-1',
  );
}
