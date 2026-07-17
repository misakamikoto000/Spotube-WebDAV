import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/webdav/webdav_metadata_status.dart';

void main() {
  test('filters only tracks without matched metadata', () {
    final unmatched = _track(albumId: 'webdav:album-1');
    final matchedMusicBrainz = _track(albumId: 'musicbrainz:album-1');
    final matchedItunes = _track(albumId: 'itunes:album-2');
    final matchedQq = _track(albumId: 'qq:album-3');

    expect(webDavTrackHasMatchedMetadata(unmatched), isFalse);
    expect(webDavTrackHasMatchedMetadata(matchedMusicBrainz), isTrue);
    expect(webDavTrackHasMatchedMetadata(matchedItunes), isTrue);
    expect(webDavTrackHasMatchedMetadata(matchedQq), isTrue);
    expect(
      webDavUnmatchedTracks(
        [unmatched, matchedMusicBrainz, matchedItunes, matchedQq],
      ),
      [unmatched],
    );
  });

  test('retries catalog false positives that contradict collection artist', () {
    final wrong = _track(
      albumId: 'qq:wrong-result',
      artistName: '其他歌手',
      path:
          'https://dav.example/Music/%E7%8E%8B%E5%8A%9B%E5%AE%8F20%E5%B9%B4%E7%B2%BE%E9%80%89/01.flac',
    );
    final correct = _track(
      albumId: 'qq:correct-result',
      artistName: '王力宏',
      path:
          'https://dav.example/Music/%E7%8E%8B%E5%8A%9B%E5%AE%8F20%E5%B9%B4%E7%B2%BE%E9%80%89/02.flac',
    );

    expect(webDavTrackHasMatchedMetadata(wrong), isFalse);
    expect(webDavTrackHasMatchedMetadata(correct), isTrue);
    expect(webDavUnmatchedTracks([wrong, correct]), [wrong]);
  });
}

SpotubeLocalTrackObject _track({
  required String albumId,
  String artistName = '周杰伦',
  String? path,
}) {
  final artist = SpotubeSimpleArtistObject(
    id: 'artist-1',
    name: artistName,
    externalUri: '',
  );
  final trackPath = path ?? 'https://dav.example/$albumId.wav';
  return SpotubeLocalTrackObject(
    id: 'track-$albumId',
    name: '歌曲',
    externalUri: trackPath,
    artists: [artist],
    album: SpotubeSimpleAlbumObject(
      id: albumId,
      name: albumId.startsWith('webdav:') ? 'Unknown Album' : '专辑',
      externalUri: '',
      artists: [artist],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 0,
    path: trackPath,
    webDavAccountId: 'account-1',
  );
}
