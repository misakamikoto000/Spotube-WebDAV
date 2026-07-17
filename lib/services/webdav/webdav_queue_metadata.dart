import 'package:spotube/models/metadata/metadata.dart';

/// Resolves WebDAV queue entries by path because their stable IDs do not
/// change when MusicBrainz metadata is added later.
List<SpotubeTrackObject> mergeWebDavQueueMetadata(
  Iterable<SpotubeTrackObject> queue,
  Iterable<SpotubeLocalTrackObject> latestTracks,
) {
  final latestByPath = {
    for (final track in latestTracks) track.path: track,
  };
  return queue.map((track) {
    if (track is! SpotubeLocalTrackObject) return track;
    return latestByPath[track.path] ?? track;
  }).toList(growable: false);
}
