import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/webdav/chinese_metadata_normalizer.dart';

void main() {
  test('normalizes the MusicBrainz bedtime-stories album alias', () {
    expect(
      ChineseMetadataNormalizer.normalizeAlbumName('周杰倫的睡前故事'),
      '周杰伦的床边故事',
    );
    expect(
      ChineseMetadataNormalizer.albumKey('周杰伦的睡前故事'),
      ChineseMetadataNormalizer.albumKey('周杰伦的床边故事'),
    );
  });

  test('converts traditional music metadata to simplified Chinese', () {
    expect(ChineseMetadataNormalizer.simplify('周杰倫'), '周杰伦');
    expect(ChineseMetadataNormalizer.simplify('蘭亭序'), '兰亭序');
    expect(ChineseMetadataNormalizer.simplify('葉惠美'), '叶惠美');
    expect(ChineseMetadataNormalizer.simplify('跨時代'), '跨时代');
  });

  test('album identity ignores copy-specific release decorations', () {
    final canonical = ChineseMetadataNormalizer.albumKey('梦游计');

    expect(ChineseMetadataNormalizer.albumKey('2022-01-12 梦游计'), canonical);
    expect(ChineseMetadataNormalizer.albumKey('梦游计 [FLAC 24bit-96kHz]'),
        canonical);
    expect(
        ChineseMetadataNormalizer.albumKey('梦游计 (Deluxe Edition)'), canonical);
    expect(ChineseMetadataNormalizer.albumKey('梦游计 CD 2'), canonical);
  });

  test('normalizes title, artist and album while preserving local identity',
      () {
    final artist = SpotubeSimpleArtistObject(
      id: 'musicbrainz:artist-1',
      name: '周杰倫',
      externalUri: 'https://musicbrainz.org/artist/artist-1',
    );
    final source = SpotubeLocalTrackObject(
      id: 'track-1',
      name: '蘭亭序',
      externalUri: 'https://dav.example/蘭亭序.flac',
      artists: [artist],
      album: SpotubeSimpleAlbumObject(
        id: 'musicbrainz:album-1',
        name: '魔杰座',
        externalUri: 'https://musicbrainz.org/release-group/album-1',
        artists: [artist],
        albumType: SpotubeAlbumType.album,
      ),
      durationMs: 253000,
      path: 'https://dav.example/蘭亭序.flac',
      webDavAccountId: 'account-1',
    );

    final normalized = ChineseMetadataNormalizer.normalizeTrack(source);

    expect(normalized.id, source.id);
    expect(normalized.path, source.path);
    expect(normalized.name, '兰亭序');
    expect(normalized.artists.single.name, '周杰伦');
    expect(normalized.album.name, '魔杰座');
    expect(normalized.album.artists.single.name, '周杰伦');
  });
}
