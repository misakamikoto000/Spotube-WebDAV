import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/webdav/webdav_library_store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
    await WebDavLibraryStore.initialize();
  });

  test('persists scanned WebDAV tracks without account credentials', () async {
    const account = WebDavAccount(
      id: 'account-1',
      name: 'Music server',
      url: 'https://dav.example/dav/',
      username: 'listener',
      password: 'very-secret',
    );
    final track = WebDavEntry(
      uri: Uri.parse('https://dav.example/dav/Music/Artist%20-%20Song.mp3'),
      displayName: 'Artist - Song.mp3',
      isDirectory: false,
      contentType: 'audio/mpeg',
    ).toTrack(account);

    await WebDavLibraryStore.save(account.id, [track]);
    final raw =
        KVStoreService.sharedPreferences.getString('webdav_library_tracks_v1')!;

    expect(raw, isNot(contains(account.password)));
    await WebDavLibraryStore.initialize();
    expect(WebDavLibraryStore.tracksByAccount[account.id], hasLength(1));
    expect(
      WebDavLibraryStore.tracksByAccount[account.id]!.single.path,
      track.path,
    );
  });

  test('does not persist release-site promotional audio', () async {
    const account = WebDavAccount(
      id: 'account-1',
      name: 'Music server',
      url: 'https://dav.example/dav/',
      username: 'listener',
      password: 'secret',
    );
    final song = WebDavEntry(
      uri: Uri.parse('https://dav.example/dav/Music/01.song.flac'),
      displayName: '01.song.flac',
      isDirectory: false,
    ).toTrack(account);
    final promo = WebDavEntry(
      uri: Uri.parse(
        'https://dav.example/dav/Music/02.artist%20-%20CNHiFi.COM.flac',
      ),
      displayName: '02.artist - CNHiFi.COM.flac',
      isDirectory: false,
    ).toTrack(account);

    await WebDavLibraryStore.save(account.id, [song, promo]);

    expect(WebDavLibraryStore.tracksByAccount[account.id], [song]);
  });
}
