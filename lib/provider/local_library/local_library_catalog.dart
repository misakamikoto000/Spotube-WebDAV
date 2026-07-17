import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/provider/webdav/webdav_accounts_provider.dart';
import 'package:spotube/provider/webdav/webdav_library_provider.dart';
import 'package:spotube/services/webdav/chinese_metadata_normalizer.dart';

String localCatalogAlbumLocation(String albumId) =>
    'spotube-local://album/${Uri.encodeComponent(albumId)}';

String localCatalogArtistLocation(String artistId) =>
    'spotube-local://artist/${Uri.encodeComponent(artistId)}';

const localCatalogAllTracksLocation = 'spotube-local://playlist/all';

class LocalLibraryCollection<T> {
  final T item;
  final String location;
  final String title;
  final List<SpotubeLocalTrackObject> tracks;

  const LocalLibraryCollection({
    required this.item,
    required this.location,
    required this.title,
    required this.tracks,
  });
}

class LocalLibraryCatalog {
  final List<SpotubeLocalTrackObject> tracks;
  final List<LocalLibraryCollection<SpotubeSimplePlaylistObject>> playlists;
  final List<LocalLibraryCollection<SpotubeSimpleAlbumObject>> albums;
  final List<LocalLibraryCollection<SpotubeFullArtistObject>> artists;
  final Map<String, LocalLibraryCollection<Object>> collectionsByLocation;
  final Map<String, String> albumLocationsById;
  final Map<String, String> artistLocationsById;
  final Map<String, String> playlistLocationsById;

  const LocalLibraryCatalog({
    required this.tracks,
    required this.playlists,
    required this.albums,
    required this.artists,
    required this.collectionsByLocation,
    required this.albumLocationsById,
    required this.artistLocationsById,
    required this.playlistLocationsById,
  });

  LocalLibraryCollection<Object>? collectionForLocation(String location) =>
      collectionsByLocation[location];

  List<SpotubeLocalTrackObject>? tracksForLocation(String location) =>
      collectionsByLocation[location]?.tracks;
}

final localLibraryCatalogProvider = Provider<LocalLibraryCatalog>((ref) {
  final tracksByAccount = ref.watch(webDavLibraryProvider);
  final accounts = ref.watch(webDavAccountsProvider);
  final accountNames = {
    for (final account in accounts) account.id: account.name
  };
  final allTracksById = <String, SpotubeLocalTrackObject>{};
  for (final tracks in tracksByAccount.values) {
    for (final track in tracks) {
      allTracksById[track.id] = track;
    }
  }
  final allTracks = allTracksById.values.toList(growable: false)
    ..sort(_compareTracks);

  final artistGroups = <String, List<SpotubeLocalTrackObject>>{};
  final artistObjects = <String, SpotubeSimpleArtistObject>{};
  final artistIdsByGroup = <String, Set<String>>{};
  for (final track in allTracks) {
    for (final artist in track.artists) {
      if (artist.name == webDavUnknownArtist || artist.name.isEmpty) continue;
      final groupKey = ChineseMetadataNormalizer.key(artist.name);
      if (groupKey.isEmpty) continue;
      final normalizedArtist = artist.copyWith(
        name: ChineseMetadataNormalizer.simplify(artist.name),
      );
      final current = artistObjects[groupKey];
      final currentHasImage = current?.images?.isNotEmpty == true;
      final candidateHasImage = normalizedArtist.images?.isNotEmpty == true;
      if (current == null ||
          (!currentHasImage && candidateHasImage) ||
          (currentHasImage == candidateHasImage &&
              !current.id.startsWith('musicbrainz:') &&
              normalizedArtist.id.startsWith('musicbrainz:'))) {
        artistObjects[groupKey] = normalizedArtist;
      }
      artistIdsByGroup.putIfAbsent(groupKey, () => <String>{}).add(artist.id);
      final groupedTracks = artistGroups.putIfAbsent(groupKey, () => []);
      if (!groupedTracks.any((candidate) => candidate.id == track.id)) {
        groupedTracks.add(track);
      }
    }
  }

  final albums = <LocalLibraryCollection<SpotubeSimpleAlbumObject>>[];
  final albumLocationsById = <String, String>{};
  for (final group in _groupLocalAlbums(allTracks)) {
    final tracks = group.tracks..sort(_compareTracks);
    final album = _bestAlbum(tracks);
    final collection = LocalLibraryCollection<SpotubeSimpleAlbumObject>(
      item: album,
      location: localCatalogAlbumLocation(album.id),
      title: album.name,
      tracks: List.unmodifiable(tracks),
    );
    albums.add(collection);
    for (final albumId in group.albumIds) {
      albumLocationsById[albumId] = collection.location;
    }
    albumLocationsById[album.id] = collection.location;
  }
  albums.sort((left, right) => left.title.compareTo(right.title));

  final artists = artistGroups.entries.map((entry) {
    final tracks = entry.value..sort(_compareTracks);
    final simpleArtist = artistObjects[entry.key]!;
    final matchedArtistImages = simpleArtist.images ?? const [];
    final images = matchedArtistImages.isNotEmpty
        ? matchedArtistImages
        : tracks
            .expand((track) => track.album.images)
            .fold<List<SpotubeImageObject>>(
            <SpotubeImageObject>[],
            (result, image) => result.isEmpty ? [image] : result,
          );
    final artist = SpotubeFullArtistObject(
      id: simpleArtist.id,
      name: simpleArtist.name,
      externalUri: simpleArtist.externalUri,
      images: images,
    );
    return LocalLibraryCollection<SpotubeFullArtistObject>(
      item: artist,
      location: localCatalogArtistLocation(artist.id),
      title: artist.name,
      tracks: List.unmodifiable(tracks),
    );
  }).toList(growable: false)
    ..sort((left, right) => left.title.compareTo(right.title));

  final localOwner = SpotubeUserObject(
    id: 'local:webdav',
    name: 'WebDAV',
    externalUri: '',
  );
  final playlists = <LocalLibraryCollection<SpotubeSimplePlaylistObject>>[];
  if (allTracks.isNotEmpty) {
    playlists.add(
      LocalLibraryCollection<SpotubeSimplePlaylistObject>(
        item: SpotubeSimplePlaylistObject(
          id: 'local:webdav:all',
          name: 'WebDAV',
          description: '♫ ${allTracks.length}',
          externalUri: '',
          owner: localOwner,
          images: _firstCover(allTracks),
        ),
        location: localCatalogAllTracksLocation,
        title: 'WebDAV',
        tracks: List.unmodifiable(allTracks),
      ),
    );
  }
  for (final entry in tracksByAccount.entries) {
    if (entry.value.isEmpty) continue;
    final tracks = entry.value.toList(growable: false)..sort(_compareTracks);
    final title = accountNames[entry.key] ?? 'WebDAV';
    playlists.add(
      LocalLibraryCollection<SpotubeSimplePlaylistObject>(
        item: SpotubeSimplePlaylistObject(
          id: 'local:webdav:${entry.key}',
          name: title,
          description: 'WebDAV · ♫ ${tracks.length}',
          externalUri: '',
          owner: localOwner,
          images: _firstCover(tracks),
        ),
        location: webDavLibraryLocationKey(entry.key),
        title: title,
        tracks: List.unmodifiable(tracks),
      ),
    );
  }

  final collectionsByLocation = <String, LocalLibraryCollection<Object>>{};
  for (final collection in [...playlists, ...albums, ...artists]) {
    collectionsByLocation[collection.location] = LocalLibraryCollection<Object>(
      item: collection.item,
      location: collection.location,
      title: collection.title,
      tracks: collection.tracks,
    );
  }

  return LocalLibraryCatalog(
    tracks: List.unmodifiable(allTracks),
    playlists: List.unmodifiable(playlists),
    albums: List.unmodifiable(albums),
    artists: List.unmodifiable(artists),
    collectionsByLocation: Map.unmodifiable(collectionsByLocation),
    albumLocationsById: Map.unmodifiable(albumLocationsById),
    artistLocationsById: Map.unmodifiable({
      for (final collection in artists)
        for (final artistId in {
          collection.item.id,
          ...?artistIdsByGroup[
              ChineseMetadataNormalizer.key(collection.item.name)],
        })
          artistId: collection.location,
    }),
    playlistLocationsById: Map.unmodifiable({
      for (final collection in playlists)
        collection.item.id: collection.location,
    }),
  );
});

class _LocalAlbumGroup {
  final List<SpotubeLocalTrackObject> tracks;
  final Set<String> albumIds;

  const _LocalAlbumGroup({required this.tracks, required this.albumIds});
}

/// Builds album components from progressively weaker evidence:
///
/// 1. the same catalog album id is authoritative;
/// 2. the same normalized album name in the same WebDAV directory is one
///    physical release, even when individual songs were matched to bad ids;
/// 3. the same normalized name with a shared credible album artist joins
///    copies coming from different catalogs or directories.
///
/// A name by itself is deliberately not enough, so genuinely different
/// self-titled albums are kept separate.
List<_LocalAlbumGroup> _groupLocalAlbums(
  List<SpotubeLocalTrackObject> allTracks,
) {
  final tracks = allTracks
      .where(
        (track) =>
            track.album.name.isNotEmpty &&
            track.album.name != webDavUnknownAlbum &&
            ChineseMetadataNormalizer.albumKey(track.album.name).isNotEmpty,
      )
      .toList(growable: false);
  if (tracks.isEmpty) return const [];

  final parents = List<int>.generate(tracks.length, (index) => index);
  final ranks = List<int>.filled(tracks.length, 0);
  int find(int index) {
    var root = index;
    while (parents[root] != root) {
      root = parents[root];
    }
    while (parents[index] != index) {
      final next = parents[index];
      parents[index] = root;
      index = next;
    }
    return root;
  }

  void union(int left, int right) {
    var leftRoot = find(left);
    var rightRoot = find(right);
    if (leftRoot == rightRoot) return;
    if (ranks[leftRoot] < ranks[rightRoot]) {
      final swap = leftRoot;
      leftRoot = rightRoot;
      rightRoot = swap;
    }
    parents[rightRoot] = leftRoot;
    if (ranks[leftRoot] == ranks[rightRoot]) ranks[leftRoot]++;
  }

  final firstByEvidence = <String, int>{};
  void connect(String evidence, int index) {
    final first = firstByEvidence.putIfAbsent(evidence, () => index);
    union(first, index);
  }

  for (var index = 0; index < tracks.length; index++) {
    final track = tracks[index];
    final album = track.album;
    final albumName = ChineseMetadataNormalizer.albumKey(album.name);
    if (album.id.trim().isNotEmpty) {
      connect('id:${album.id}', index);
    }

    final directory = _trackDirectoryKey(track);
    if (directory != null) {
      connect('directory:$albumName|$directory', index);
    }

    for (final artist in album.artists) {
      final artistKey = _credibleAlbumArtistKey(artist.name, album.name);
      if (artistKey != null) {
        connect('artist:$albumName|$artistKey', index);
      }
    }
  }

  final tracksByRoot = <int, List<SpotubeLocalTrackObject>>{};
  for (var index = 0; index < tracks.length; index++) {
    tracksByRoot.putIfAbsent(find(index), () => []).add(tracks[index]);
  }
  return tracksByRoot.values
      .map(
        (groupTracks) => _LocalAlbumGroup(
          tracks: groupTracks,
          albumIds: {
            for (final track in groupTracks)
              if (track.album.id.trim().isNotEmpty) track.album.id,
          },
        ),
      )
      .toList(growable: false);
}

String? _trackDirectoryKey(SpotubeLocalTrackObject track) {
  final uri = Uri.tryParse(track.path);
  if (uri != null && uri.pathSegments.isNotEmpty) {
    final directory = uri.resolve('.');
    return directory
        .replace(
          scheme: directory.scheme.toLowerCase(),
          host: directory.host.toLowerCase(),
          query: '',
          fragment: '',
        )
        .toString();
  }
  final normalized = track.path.replaceAll('\\', '/');
  final separator = normalized.lastIndexOf('/');
  return separator <= 0 ? null : normalized.substring(0, separator + 1);
}

String? _credibleAlbumArtistKey(String artistName, String albumName) {
  final key = ChineseMetadataNormalizer.key(artistName);
  if (key.isEmpty ||
      key == ChineseMetadataNormalizer.key(webDavUnknownArtist) ||
      key == ChineseMetadataNormalizer.albumKey(albumName)) {
    return null;
  }
  if (RegExp(
    r'^(?:unknownartist|variousartists|群星|佚名|未知歌手)$|(?:cnhifi|cndsd|\.com|\.net)',
    caseSensitive: false,
  ).hasMatch(key)) {
    return null;
  }
  return key;
}

SpotubeSimpleAlbumObject _bestAlbum(
  List<SpotubeLocalTrackObject> tracks,
) {
  final idCounts = <String, int>{};
  final artistCounts = <String, int>{};
  for (final track in tracks) {
    idCounts[track.album.id] = (idCounts[track.album.id] ?? 0) + 1;
    for (final artist in track.album.artists) {
      final key = _credibleAlbumArtistKey(artist.name, track.album.name);
      if (key != null) artistCounts[key] = (artistCounts[key] ?? 0) + 1;
    }
  }
  final candidates = tracks.map((track) => track.album).toList(growable: false)
    ..sort((left, right) {
      final quality = _albumQuality(right, idCounts, artistCounts)
          .compareTo(_albumQuality(left, idCounts, artistCounts));
      if (quality != 0) return quality;
      final artistCount = left.artists.length.compareTo(right.artists.length);
      if (artistCount != 0) return artistCount;
      return left.id.compareTo(right.id);
    });
  return candidates.first;
}

int _albumQuality(
  SpotubeSimpleAlbumObject album,
  Map<String, int> idCounts,
  Map<String, int> artistCounts,
) {
  final sourceTrackCount = idCounts[album.id] ?? 0;
  var artistSupport = 0;
  for (final artist in album.artists) {
    final key = _credibleAlbumArtistKey(artist.name, album.name);
    if (key != null && (artistCounts[key] ?? 0) > artistSupport) {
      artistSupport = artistCounts[key]!;
    }
  }
  final hasLocalArtwork = album.images.any(
    (image) =>
        image.url.isNotEmpty &&
        !image.url.startsWith('http://') &&
        !image.url.startsWith('https://'),
  );
  final hasCatalogId = album.id.startsWith('musicbrainz:') ||
      album.id.startsWith('itunes:') ||
      album.id.startsWith('qq:');
  final releaseYear = album.releaseDate == null || album.releaseDate!.length < 4
      ? null
      : int.tryParse(album.releaseDate!.substring(0, 4));
  return sourceTrackCount * 20 +
      artistSupport * 4 +
      (hasLocalArtwork ? 12 : (album.images.isNotEmpty ? 6 : 0)) +
      (hasCatalogId ? 4 : 0) +
      (releaseYear != null && releaseYear > 1970 ? 2 : 0) +
      (album.albumType == SpotubeAlbumType.album ? 1 : 0);
}

List<SpotubeImageObject> _firstCover(
  Iterable<SpotubeLocalTrackObject> tracks,
) {
  for (final track in tracks) {
    if (track.album.images.isNotEmpty) return [track.album.images.first];
  }
  return const [];
}

int _compareTracks(
  SpotubeLocalTrackObject left,
  SpotubeLocalTrackObject right,
) {
  final album = left.album.name.compareTo(right.album.name);
  if (album != 0) return album;
  return left.name.compareTo(right.name);
}
