import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/webdav/webdav_account.dart';

void main() {
  test('normalizes an optional WebDAV folder path', () {
    expect(
      WebDavAccount.normalizeRootPath(r'\Music\\Lossless\'),
      'Music/Lossless',
    );
    expect(WebDavAccount.normalizeRootPath(' /Music/无损/ '), 'Music/无损');
    expect(
      () => WebDavAccount.normalizeRootPath('/Music/../Private'),
      throwsFormatException,
    );
  });

  test('resolves and encodes a selected folder below the WebDAV endpoint', () {
    const account = WebDavAccount(
      id: 'account-1',
      name: 'Music server',
      url: 'https://dav.example/dav/',
      rootPath: '/Music/无损 音乐/',
      username: 'listener',
      password: 'secret',
    );

    expect(
      account.rootUri.toString(),
      'https://dav.example/dav/Music/%E6%97%A0%E6%8D%9F%20%E9%9F%B3%E4%B9%90/',
    );
    expect(account.rootUri.pathSegments, ['dav', 'Music', '无损 音乐', '']);
    expect(account.rootDisplayPath, '/Music/无损 音乐/');
  });

  test('keeps existing accounts compatible when no folder is configured', () {
    const account = WebDavAccount(
      id: 'account-1',
      name: 'Music server',
      url: 'https://dav.example/dav/Music/',
      username: '',
      password: '',
    );

    expect(account.rootUri.toString(), account.url);
    expect(account.rootDisplayPath, '/');
  });

  test('derives a library root path from a browsed folder', () {
    const account = WebDavAccount(
      id: 'account-1',
      name: 'Music server',
      url: 'https://dav.example/dav/',
      username: '',
      password: '',
    );

    expect(
      account.rootPathFor(
        Uri.parse(
          'https://dav.example/dav/Music/%E6%97%A0%E6%8D%9F%20%E9%9F%B3%E4%B9%90/',
        ),
      ),
      'Music/无损 音乐',
    );
    expect(
      () => account.rootPathFor(Uri.parse('https://other.example/Music/')),
      throwsFormatException,
    );
  });

  test('only accepts playback URLs inside the selected library folder', () {
    const account = WebDavAccount(
      id: 'account-1',
      name: 'Music server',
      url: 'https://dav.example/dav/',
      rootPath: 'Music/无损',
      username: '',
      password: '',
    );

    expect(
      account.contains(
        Uri.parse(
          'https://dav.example/dav/Music/%E6%97%A0%E6%8D%9F/Album/Song.flac',
        ),
      ),
      isTrue,
    );
    expect(
      account.contains(Uri.parse('https://dav.example/dav/Private/Song.mp3')),
      isFalse,
    );
    expect(
      account.contains(
        Uri.parse('https://untrusted.example/dav/Music/无损/Song.mp3'),
      ),
      isFalse,
    );
  });
}
