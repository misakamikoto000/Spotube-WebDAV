import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/provider/local_library/local_library_catalog.dart';
import 'package:spotube/provider/metadata_plugin/browse/sections.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/library/albums.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/kv_store/encrypted_kv_store.dart';
import 'package:spotube/services/webdav/webdav_account_store.dart';
import 'package:spotube/services/webdav/webdav_library_store.dart';

void main() {
  const account = WebDavAccount(
    id: 'account-1',
    name: '家庭音乐',
    url: 'https://dav.example/dav/',
    rootPath: 'Music',
    username: 'listener',
    password: 'secret',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
    await EncryptedKvStoreService.initialize();
    await WebDavAccountStore.initialize();
    await WebDavLibraryStore.initialize();
    await WebDavAccountStore.saveAll([account]);
    await WebDavLibraryStore.save(account.id, [
      _track(
        id: 'track-1',
        title: '东风破',
        albumId: 'musicbrainz:album-1',
        albumName: '葉惠美',
      ),
      _track(
        id: 'track-2',
        title: '晴天',
        albumId: 'musicbrainz:album-1',
        albumName: '葉惠美',
      ),
      _track(
        id: 'track-3',
        title: '七里香',
        albumId: 'musicbrainz:album-2',
        albumName: '七里香',
      ),
    ]);
  });

  test('groups matched WebDAV tracks into local albums and artists', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final catalog = container.read(localLibraryCatalogProvider);

    expect(catalog.tracks, hasLength(3));
    expect(catalog.albums.map((album) => album.title), ['七里香', '叶惠美']);
    expect(catalog.artists, hasLength(1));
    expect(catalog.artists.single.title, '周杰伦');
    expect(catalog.artists.single.tracks, hasLength(3));
    expect(catalog.playlists, hasLength(2));
    expect(
      catalog.tracksForLocation(
        catalog.albumLocationsById['musicbrainz:album-1']!,
      ),
      hasLength(2),
    );
  });

  test('serves local playlists, artists, albums and browse when logged out',
      () async {
    final container = ProviderContainer(
      overrides: [
        metadataPluginAuthenticatedProvider.overrideWith(_LoggedOutAuth.new),
      ],
    );
    addTearDown(container.dispose);

    final playlists =
        await container.read(metadataPluginSavedPlaylistsProvider.future);
    final artists =
        await container.read(metadataPluginSavedArtistsProvider.future);
    final albums =
        await container.read(metadataPluginSavedAlbumsProvider.future);
    final browse =
        await container.read(metadataPluginBrowseSectionsProvider.future);

    expect(playlists.items, hasLength(2));
    expect(artists.items.single.name, '周杰伦');
    expect(albums.items, hasLength(2));
    expect(
      browse.items.map((section) => section.id),
      ['local:playlists', 'local:albums', 'local:artists'],
    );
    expect(browse.items.every((section) => section.items.isNotEmpty), isTrue);
  });

  test('merges simplified and traditional spellings into one artist', () async {
    await WebDavLibraryStore.save(account.id, [
      _track(
        id: 'track-simple',
        title: '兰亭序',
        albumId: 'webdav:album-1',
        albumName: '跨时代',
        artistId: 'webdav:artist:周杰伦',
        artistName: '周杰伦',
      ),
      _track(
        id: 'track-traditional',
        title: '蘭亭序',
        albumId: 'musicbrainz:album-1',
        albumName: '跨時代',
        artistId: 'musicbrainz:artist-1',
        artistName: '周杰倫',
      ),
    ]);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final catalog = container.read(localLibraryCatalogProvider);

    expect(catalog.artists, hasLength(1));
    expect(catalog.artists.single.title, '周杰伦');
    expect(catalog.artists.single.item.id, 'musicbrainz:artist-1');
    expect(catalog.artists.single.tracks, hasLength(2));
    expect(
      catalog.artistLocationsById['webdav:artist:周杰伦'],
      catalog.artistLocationsById['musicbrainz:artist-1'],
    );
  });

  test('merges the same album across catalog ids and album types', () async {
    await WebDavLibraryStore.save(account.id, [
      _track(
        id: 'track-album-source-1',
        title: 'Song A',
        albumId: 'musicbrainz:album-1',
        albumName: '周杰伦的睡前故事',
      ),
      _track(
        id: 'track-album-source-2',
        title: 'Song B',
        albumId: 'itunes:album-9',
        albumName: '周杰伦的床边故事',
        albumType: SpotubeAlbumType.compilation,
      ),
    ]);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final catalog = container.read(localLibraryCatalogProvider);

    expect(catalog.albums, hasLength(1));
    expect(catalog.albums.single.tracks, hasLength(2));
    expect(
      catalog.albumLocationsById['musicbrainz:album-1'],
      catalog.albumLocationsById['itunes:album-9'],
    );
  });

  test('keeps one album id together when track credits include guests',
      () async {
    await WebDavLibraryStore.save(account.id, [
      _track(
        id: 'track-main-credit',
        title: '主打歌',
        albumId: 'qq:album-shared',
        albumName: '再见你好吗',
        artistName: '陶喆',
      ),
      _track(
        id: 'track-guest-credit',
        title: '合唱歌',
        albumId: 'qq:album-shared',
        albumName: '再见你好吗',
        artistName: '陶喆',
        additionalArtistNames: const ['关诗敏'],
      ),
    ]);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final catalog = container.read(localLibraryCatalogProvider);

    expect(catalog.albums, hasLength(1));
    expect(catalog.albums.single.tracks, hasLength(2));
  });

  test('merges conflicting catalog matches from the same physical album',
      () async {
    const directory = 'https://dav.example/dav/Music/2022-01-12%20梦游计/';
    await WebDavLibraryStore.save(account.id, [
      _track(
        id: 'track-wrong-match',
        title: '幻听',
        albumId: 'qq:wrong-album',
        albumName: '梦游计',
        artistId: 'qq:artist-wrong',
        artistName: '翻唱歌手',
        trackPath: '${directory}01.flac',
      ),
      _track(
        id: 'track-correct-match',
        title: '想象之中',
        albumId: 'qq:correct-album',
        albumName: '梦游计',
        artistId: 'qq:artist-correct',
        artistName: '许嵩',
        trackPath: '${directory}02.flac',
      ),
    ]);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final catalog = container.read(localLibraryCatalogProvider);

    expect(catalog.albums, hasLength(1));
    expect(catalog.albums.single.tracks, hasLength(2));
    expect(
      catalog.albumLocationsById['qq:wrong-album'],
      catalog.albumLocationsById['qq:correct-album'],
    );
  });

  test('does not merge same-name albums without shared release evidence',
      () async {
    await WebDavLibraryStore.save(account.id, [
      _track(
        id: 'track-album-a',
        title: 'Song A',
        albumId: 'qq:album-a',
        albumName: '同名专辑',
        artistId: 'qq:artist-a',
        artistName: '歌手甲',
        trackPath: 'https://dav.example/dav/Music/A/01.flac',
      ),
      _track(
        id: 'track-album-b',
        title: 'Song B',
        albumId: 'qq:album-b',
        albumName: '同名专辑',
        artistId: 'qq:artist-b',
        artistName: '歌手乙',
        trackPath: 'https://dav.example/dav/Music/B/01.flac',
      ),
    ]);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(localLibraryCatalogProvider).albums, hasLength(2));
  });

  test('prefers a matched artist portrait over album artwork', () async {
    await WebDavLibraryStore.save(account.id, [
      _track(
        id: 'track-with-artist-image',
        title: 'Song',
        albumId: 'album-1',
        albumName: 'Album',
        artistImages: [
          SpotubeImageObject(
            url: 'C:/Spotube/artists/artist.jpg',
            width: 500,
            height: 500,
          ),
        ],
      ),
    ]);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final artist = container.read(localLibraryCatalogProvider).artists.single;

    expect(artist.item.images.single.url, 'C:/Spotube/artists/artist.jpg');
  });
}

class _LoggedOutAuth extends MetadataPluginAuthenticatedNotifier {
  @override
  FutureOr<bool> build() => false;
}

SpotubeLocalTrackObject _track({
  required String id,
  required String title,
  required String albumId,
  required String albumName,
  List<SpotubeImageObject>? artistImages,
  SpotubeAlbumType albumType = SpotubeAlbumType.album,
  String artistId = 'musicbrainz:artist-1',
  String artistName = '周杰倫',
  List<String> additionalArtistNames = const [],
  String? trackPath,
}) {
  final artist = SpotubeSimpleArtistObject(
    id: artistId,
    name: artistName,
    externalUri: 'https://musicbrainz.org/artist/artist-1',
    images: artistImages,
  );
  final artists = [
    artist,
    for (final name in additionalArtistNames)
      SpotubeSimpleArtistObject(
        id: 'musicbrainz:artist:$name',
        name: name,
        externalUri: '',
      ),
  ];
  final path = trackPath ?? 'https://dav.example/dav/Music/$id.flac';
  return SpotubeLocalTrackObject(
    id: id,
    name: title,
    externalUri: path,
    artists: artists,
    album: SpotubeSimpleAlbumObject(
      id: albumId,
      name: albumName,
      externalUri: 'https://musicbrainz.org/release-group/$albumId',
      artists: artists,
      images: [
        SpotubeImageObject(
          url: 'C:/Spotube/covers/$albumId.jpg',
          width: 250,
          height: 250,
        ),
      ],
      albumType: albumType,
      releaseDate: '2003-07-31',
    ),
    durationMs: 300000,
    path: path,
    webDavAccountId: 'account-1',
  );
}
