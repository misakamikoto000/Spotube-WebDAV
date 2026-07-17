import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/services/webdav/chinese_metadata_normalizer.dart';

bool webDavTrackHasMatchedMetadata(SpotubeLocalTrackObject track) {
  if (webDavTrackIsPromotional(track)) return false;
  final hasCatalogId = track.album.id.startsWith('musicbrainz:') ||
      track.album.id.startsWith('itunes:') ||
      track.album.id.startsWith('qq:');
  final hasLocalArtwork = track.album.images.any(
    (image) =>
        image.url.isNotEmpty &&
        !image.url.startsWith('http://') &&
        !image.url.startsWith('https://'),
  );
  if (!hasCatalogId && !hasLocalArtwork) return false;

  // Collection folders carry unusually strong artist evidence. A catalog hit
  // for another artist is almost always a romanized-title false positive and
  // must be eligible for automatic repair instead of being cached forever.
  final expectedArtist = webDavExpectedCollectionArtist(track.path);
  if (expectedArtist != null) {
    final expectedKey = ChineseMetadataNormalizer.key(expectedArtist);
    final matchedArtistKeys = {
      ...track.artists.map((artist) => artist.name),
      ...track.album.artists.map((artist) => artist.name),
    }.map(ChineseMetadataNormalizer.key);
    if (!matchedArtistKeys.contains(expectedKey)) return false;
  }
  return true;
}

List<SpotubeLocalTrackObject> webDavUnmatchedTracks(
  Iterable<SpotubeLocalTrackObject> tracks,
) =>
    tracks
        .where(
          (track) =>
              !webDavTrackIsPromotional(track) &&
              !webDavTrackHasMatchedMetadata(track),
        )
        .toList(growable: false);
