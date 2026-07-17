import 'package:path/path.dart' as path;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/webdav/webdav_account.dart';

class WebDavEntry {
  final Uri uri;
  final String displayName;
  final bool isDirectory;
  final int? contentLength;
  final String? contentType;
  final DateTime? lastModified;

  const WebDavEntry({
    required this.uri,
    required this.displayName,
    required this.isDirectory,
    this.contentLength,
    this.contentType,
    this.lastModified,
  });
}

const supportedWebDavAudioExtensions = {
  '.aac',
  '.aif',
  '.aiff',
  '.alac',
  '.ape',
  '.dff',
  '.dsf',
  '.flac',
  '.m4a',
  '.mp3',
  '.mp4',
  '.ogg',
  '.opus',
  '.wav',
  '.wave',
  '.webm',
  '.wma',
  '.wv',
};

const webDavUnknownArtist = 'Unknown Artist';
const webDavUnknownAlbum = 'Unknown Album';

bool webDavIsPromotionalAudioName(String value) {
  final basename = path.basenameWithoutExtension(value).trim();
  return RegExp(
    r'(?:^|[\s\-–—_])(?:www\.)?(?:cnhifi|cndsd)\.(?:com|net)(?:$|[\s\-–—_])',
    caseSensitive: false,
  ).hasMatch(basename);
}

bool webDavTrackIsPromotional(SpotubeLocalTrackObject track) {
  if (webDavIsPromotionalAudioName(track.name)) return true;
  final uri = Uri.tryParse(track.path);
  final filename = uri == null || uri.pathSegments.isEmpty
      ? track.path
      : uri.pathSegments.last;
  return webDavIsPromotionalAudioName(filename);
}

/// Returns a high-confidence artist encoded in a collection folder such as
/// `王力宏20年精选`. It deliberately ignores ordinary album folders.
String? webDavExpectedCollectionArtist(String trackPath) {
  final uri = Uri.tryParse(trackPath);
  if (uri == null || uri.pathSegments.length < 2) return null;
  for (final segment in uri.pathSegments.reversed.skip(1)) {
    final artist = WebDavTrackIdentity.collectionArtistFromFolder(segment);
    if (artist != null) return artist;
  }
  return null;
}

bool webDavUsesComparableWritingSystem(String left, String right) {
  final han = RegExp(r'[\u3400-\u9fff]');
  return han.hasMatch(left) == han.hasMatch(right);
}

/// Metadata inferred without reading or modifying the remote audio file.
///
/// WebDAV libraries commonly use either `Artist/Album/Track.ext` or
/// `Artist - Track.ext`. Supporting both gives the online matcher useful
/// search terms while keeping the scan inexpensive for large lossless files.
class WebDavTrackIdentity {
  final String title;
  final List<String> artists;
  final String album;

  const WebDavTrackIdentity({
    required this.title,
    required this.artists,
    required this.album,
  });

  factory WebDavTrackIdentity.fromEntry(
    WebDavEntry entry,
    WebDavAccount account,
  ) {
    final rawFilename = path.basenameWithoutExtension(entry.displayName).trim();
    final filename = cleanSearchTitle(_removeTrackNumber(rawFilename));
    final directorySegments = _usableDirectorySegments(
      _relativeDirectorySegments(entry.uri, account),
    );
    final parent = directorySegments.isEmpty ? null : directorySegments.last;
    final hierarchyArtist = directorySegments.length >= 2
        ? directorySegments[directorySegments.length - 2]
        : null;

    final strictSeparation = _splitArtistAndTitle(filename, parent: parent);
    final looseSeparation = strictSeparation == null
        ? _splitLooseCjkArtistAndTitle(filename, parent: parent)
        : null;
    final separated = strictSeparation ?? looseSeparation;
    var explicitArtists =
        separated == null ? const <String>[] : _splitArtists(separated.$1);
    if (looseSeparation != null &&
        parent != null &&
        _looksLikeArtist(parent) &&
        !explicitArtists.any(
          (artist) =>
              _normalizeForComparison(artist) ==
              _normalizeForComparison(parent),
        )) {
      // A filename such as `蔡卓妍 小酒窝` inside the `林俊杰` folder
      // credits a guest before the title. Retain the folder artist as the
      // primary search hint and the filename credit as an additional artist.
      explicitArtists = [parent, ...explicitArtists];
    }
    explicitArtists = _preferHierarchyArtist(
      explicitArtists,
      hierarchyArtist,
    );
    final combinedFolder = directorySegments.length == 1
        ? _splitArtistAndAlbum(directorySegments.single)
        : null;

    late final List<String> artists;
    late final String album;
    if (explicitArtists.isNotEmpty) {
      artists = explicitArtists;
      final parentIsArtist = parent != null &&
          artists.any(
            (artist) =>
                _normalizeForComparison(artist) ==
                _normalizeForComparison(parent),
          );
      album = parent == null || parentIsArtist ? webDavUnknownAlbum : parent;
    } else if (combinedFolder != null) {
      artists = _splitArtists(combinedFolder.$1);
      album = combinedFolder.$2;
    } else if (directorySegments.length >= 2) {
      artists = _looksLikeArtist(hierarchyArtist!)
          ? _splitArtists(hierarchyArtist)
          : const [webDavUnknownArtist];
      album = directorySegments.last;
    } else if (directorySegments.length == 1) {
      final folder = directorySegments.single;
      final collectionArtist = _collectionArtist(folder);
      artists = collectionArtist == null
          ? const [webDavUnknownArtist]
          : [collectionArtist];
      album = folder;
    } else {
      artists = const [webDavUnknownArtist];
      album = webDavUnknownAlbum;
    }

    return WebDavTrackIdentity(
      title: (separated?.$2 ?? filename).trim().isEmpty
          ? rawFilename
          : (separated?.$2 ?? filename).trim(),
      artists: artists.isEmpty ? const [webDavUnknownArtist] : artists,
      album: album.trim().isEmpty ? webDavUnknownAlbum : album.trim(),
    );
  }

  static List<String> _relativeDirectorySegments(
    Uri uri,
    WebDavAccount account,
  ) {
    final entryParts = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (entryParts.isEmpty) return const [];

    final rootParts = account.rootUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    var rootMatches = entryParts.length > rootParts.length;
    for (var index = 0; rootMatches && index < rootParts.length; index++) {
      rootMatches = entryParts[index] == rootParts[index];
    }

    final relative = rootMatches
        ? entryParts.skip(rootParts.length).toList(growable: false)
        : entryParts;
    return relative.length <= 1
        ? const []
        : relative.sublist(0, relative.length - 1);
  }

  static List<String> _usableDirectorySegments(List<String> segments) {
    final usable = segments
        .map(cleanDirectoryLabel)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);
    while (usable.length >= 2 && _isContainerDirectory(usable.last)) {
      usable.removeLast();
    }
    return usable;
  }

  /// Removes release-site, date and audio-quality decorations while keeping
  /// the human album/artist label useful for catalog searches.
  static String cleanDirectoryLabel(String value) {
    var result = value.trim();
    result = result.replaceAll(
      RegExp(
        r'[\[【(（].*?(?:解压|密码|password|cndsd|cnhifi|flac|alac|ape|wav|dsd|hi[\s._-]?res|\d{2}[\s._-]*(?:bit|b)[\s._-]*\d{2,3}(?:\.\d)?[\s._-]*khz).*?[\]】)）]',
        caseSensitive: false,
      ),
      ' ',
    );
    result = result
        .replaceFirst(
          RegExp(r'^\s*(?:19|20)\d{2}[-._]\d{1,2}[-._]\d{1,2}\s*'),
          '',
        )
        .replaceFirst(RegExp(r'^\s*DF[\s._-]+', caseSensitive: false), '')
        .replaceFirst(
          RegExp(
            r'\s+(?:FLAC|ALAC|APE|WAV|WAVE|DSD|MP3)\s*[\d._-]*(?:KHZ|BIT|B)?\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return result;
  }

  static String cleanSearchTitle(String value) => value
      .replaceAll(
        RegExp(
          r'[\[【].*?(?:flac|alac|ape|wav|dsd|hi[\s._-]?res|\d{2}[\s._-]*(?:bit|b)[\s._-]*\d{2,3}(?:\.\d)?[\s._-]*khz).*?[\]】]',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static (String, String)? _splitArtistAndAlbum(String folder) {
    final separator = RegExp(r'\s+[-–—]\s+').firstMatch(folder);
    if (separator != null) {
      final artist = folder.substring(0, separator.start).trim();
      final album = folder.substring(separator.end).trim();
      if (_looksLikeArtist(artist) && album.isNotEmpty) {
        return (artist, album);
      }
    }
    final collectionArtist = _collectionArtist(folder);
    return collectionArtist == null ? null : (collectionArtist, folder);
  }

  static String? _collectionArtist(String folder) {
    final match = RegExp(
      r'^(.{1,24}?)(?:(?:\d{1,3}年|历年|经典)?(?:精选|合集|作品集|专辑全集|音乐全集|单曲集))',
      caseSensitive: false,
    ).firstMatch(folder);
    final artist = match?.group(1)?.trim();
    return artist == null || !_looksLikeArtist(artist) ? null : artist;
  }

  static String? collectionArtistFromFolder(String folder) =>
      _collectionArtist(cleanDirectoryLabel(folder));

  static List<String> _preferHierarchyArtist(
    List<String> explicitArtists,
    String? hierarchyArtist,
  ) {
    if (explicitArtists.length != 1 ||
        hierarchyArtist == null ||
        !_looksLikeArtist(hierarchyArtist)) {
      return explicitArtists;
    }
    final explicitKey = _normalizeForComparison(explicitArtists.single);
    final hierarchyKey = _normalizeForComparison(hierarchyArtist);
    if (explicitKey == hierarchyKey ||
        (explicitKey.startsWith(hierarchyKey) &&
            explicitArtists.single.contains('-'))) {
      return [hierarchyArtist];
    }
    return explicitArtists;
  }

  static bool _looksLikeArtist(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 36) return false;
    if (_isContainerDirectory(normalized)) return false;
    if (RegExp(
      r'^(?:华语|欧美|日韩|无损音乐|音乐|music|audio|albums?|tracks?)$',
      caseSensitive: false,
    ).hasMatch(normalized)) {
      return false;
    }
    return !RegExp(
      r'(?:精选|合集|作品集|专辑|原声|歌单|音乐包|全集|soundtrack|collection)',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  static bool _isContainerDirectory(String value) => RegExp(
        r'^(?:(?:cd|disc|disk|碟|盘)\s*0*\d+|(?:flac|alac|ape|wav|dsd|hi[\s._-]?res)(?:[\s._-].*)?)$',
        caseSensitive: false,
      ).hasMatch(value.trim());

  static String _removeTrackNumber(String value) {
    return value
        .replaceFirst(
          RegExp(r'^\s*\[?\d{1,3}\]?\s*[.、)_-]+\s*'),
          '',
        )
        .trim();
  }

  static (String, String)? _splitArtistAndTitle(
    String filename, {
    String? parent,
  }) {
    final spacedSeparator = RegExp(r'\s+[-–—]\s+').firstMatch(filename);
    if (spacedSeparator != null) {
      final artist = filename.substring(0, spacedSeparator.start).trim();
      final title = filename.substring(spacedSeparator.end).trim();
      if (artist.isNotEmpty && title.isNotEmpty) return (artist, title);
    }

    // A compact hyphen is common in Chinese libraries (周杰伦-东风破), but
    // splitting every hyphen would corrupt names such as AC-DC. Only accept
    // the compact form when CJK text is present or the prefix is the folder.
    final compactSeparator = filename.indexOf('-');
    if (compactSeparator > 0 && compactSeparator < filename.length - 1) {
      final artist = filename.substring(0, compactSeparator).trim();
      final title = filename.substring(compactSeparator + 1).trim();
      final hasCjk = RegExp(r'[\u3400-\u9fff]').hasMatch(filename);
      final matchesParent = parent != null &&
          _normalizeForComparison(artist) == _normalizeForComparison(parent);
      if ((hasCjk || matchesParent) && artist.isNotEmpty && title.isNotEmpty) {
        return (artist, title);
      }
    }
    return null;
  }

  static (String, String)? _splitLooseCjkArtistAndTitle(
    String filename, {
    required String? parent,
  }) {
    if (parent == null || !_looksLikeArtist(parent)) return null;
    final parts = filename
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length != 2 ||
        !RegExp(r'^[\u3400-\u9fff]{2,8}$').hasMatch(parts.first) ||
        !RegExp(r'^[\u3400-\u9fff]{2,12}$').hasMatch(parts.last) ||
        RegExp(r'[的了在和与]').hasMatch(parts.first)) {
      return null;
    }
    return (parts.first, parts.last);
  }

  static List<String> _splitArtists(String value) {
    final normalized = value.replaceAll(
      RegExp(r'\s+(?:feat\.?|ft\.?|featuring)\s+', caseSensitive: false),
      '&',
    );
    final seen = <String>{};
    return normalized
        .split(RegExp(r'\s*[&＆、,，;；/]\s*'))
        .map((artist) => artist.trim())
        .where((artist) => artist.isNotEmpty)
        .where((artist) => seen.add(_normalizeForComparison(artist)))
        .toList(growable: false);
  }

  static String _normalizeForComparison(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_.,，。:：;；!！?？()（）\[\]【】]'), '');
}

extension WebDavEntryMusic on WebDavEntry {
  bool get isSupportedAudio {
    if (isDirectory) return false;
    if (webDavIsPromotionalAudioName(displayName)) return false;
    if (contentType?.toLowerCase().startsWith('audio/') == true) return true;
    return supportedWebDavAudioExtensions
        .contains(path.extension(displayName).toLowerCase());
  }

  SpotubeLocalTrackObject toTrack(WebDavAccount account) {
    final identity = WebDavTrackIdentity.fromEntry(this, account);
    final albumId = 'webdav:${account.id}:${uri.resolve('.').path}';
    final artistObjects = identity.artists
        .map(
          (artist) => SpotubeSimpleArtistObject(
            id: 'webdav:${account.id}:artist:$artist',
            name: artist,
            externalUri: uri.toString(),
          ),
        )
        .toList(growable: false);

    return SpotubeLocalTrackObject(
      id: 'webdav:${account.id}:${uri.toString()}',
      name: identity.title,
      externalUri: uri.toString(),
      artists: artistObjects,
      album: SpotubeSimpleAlbumObject(
        albumType: SpotubeAlbumType.album,
        id: albumId,
        name: identity.album,
        externalUri: uri.resolve('.').toString(),
        artists: artistObjects,
        releaseDate: '1970-01-01',
        images: const [],
      ),
      durationMs: 0,
      path: uri.toString(),
      webDavAccountId: account.id,
    );
  }
}
