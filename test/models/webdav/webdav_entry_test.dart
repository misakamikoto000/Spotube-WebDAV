import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';

void main() {
  const account = WebDavAccount(
    id: 'account-1',
    name: 'Home server',
    url: 'https://dav.example/Music/',
    username: 'listener',
    password: 'secret',
  );

  test('normalizes roots and rejects credentials embedded in the URL', () {
    expect(
      WebDavAccount.normalizeUri('https://dav.example/Music').toString(),
      'https://dav.example/Music/',
    );
    expect(
      () => WebDavAccount.normalizeUri(
        'https://listener:secret@dav.example/Music/',
      ),
      throwsFormatException,
    );
  });

  test('filters audio by MIME type or supported extension', () {
    expect(_entry('track.flac').isSupportedAudio, isTrue);
    expect(
      _entry('stream.bin', contentType: 'audio/ogg').isSupportedAudio,
      isTrue,
    );
    expect(_entry('cover.jpg', contentType: 'image/jpeg').isSupportedAudio,
        isFalse);
    expect(_entry('playlist.m3u').isSupportedAudio, isFalse);
    expect(_entry('Album', isDirectory: true).isSupportedAudio, isFalse);
  });

  test('derives track, artist, and album metadata from the remote path', () {
    final entry = WebDavEntry(
      uri: Uri.parse(
        'https://dav.example/Music/%E5%8D%8E%E8%AF%AD/%E5%91%A8%E6%9D%B0%E4%BC%A6%20-%20%E6%99%B4%E5%A4%A9.flac',
      ),
      displayName: '周杰伦 - 晴天.flac',
      isDirectory: false,
      contentType: 'audio/flac',
    );

    final track = entry.toTrack(account);

    expect(track.name, '晴天');
    expect(track.artists.single.name, '周杰伦');
    expect(track.album.name, '华语');
    expect(track.webDavAccountId, account.id);
    expect(track.path, entry.uri.toString());
    expect(track.toJson(), isNot(contains('password')));
    expect(track.toJson()['webDavAccountId'], account.id);
  });

  test('uses an unknown artist when the filename has no artist prefix', () {
    final track = _entry('Instrumental.mp3').toTrack(account);

    expect(track.name, 'Instrumental');
    expect(track.artists.single.name, 'Unknown Artist');
  });

  test('parses compact Chinese artist-title filenames', () {
    final entry = WebDavEntry(
      uri: Uri.parse(
        'https://dav.example/Music/%E5%91%A8%E6%9D%B0%E4%BC%A6/%E5%91%A8%E6%9D%B0%E4%BC%A6-%E4%B8%9C%E9%A3%8E%E7%A0%B4.wav',
      ),
      displayName: '周杰伦-东风破.wav',
      isDirectory: false,
      contentType: 'audio/wav',
    );

    final track = entry.toTrack(account);

    expect(track.name, '东风破');
    expect(track.artists.single.name, '周杰伦');
    expect(track.album.name, webDavUnknownAlbum);
  });

  test('uses artist and album folders when the filename has no artist', () {
    final entry = WebDavEntry(
      uri: Uri.parse(
        'https://dav.example/Music/%E5%91%A8%E6%9D%B0%E4%BC%A6/%E5%8F%B6%E6%83%A0%E7%BE%8E/01.%20%E6%99%B4%E5%A4%A9.flac',
      ),
      displayName: '01. 晴天.flac',
      isDirectory: false,
      contentType: 'audio/flac',
    );

    final track = entry.toTrack(account);

    expect(track.name, '晴天');
    expect(track.artists.single.name, '周杰伦');
    expect(track.album.name, '叶惠美');
  });

  test('uses a cautious loose CJK credit inside an artist folder', () {
    final track = _pathEntry('林俊杰/蔡卓妍 小酒窝.wav').toTrack(account);

    expect(track.name, '小酒窝');
    expect(track.artists.map((artist) => artist.name), ['林俊杰', '蔡卓妍']);
    expect(track.album.name, webDavUnknownAlbum);
  });

  test('keeps hyphens inside artist names and splits multiple artists', () {
    final acdc = _entry('AC-DC - Thunderstruck.flac').toTrack(account);
    final duet = _entry('周杰伦&杨瑞代-爱的飞行日记.wav').toTrack(account);

    expect(acdc.name, 'Thunderstruck');
    expect(acdc.artists.single.name, 'AC-DC');
    expect(duet.name, '爱的飞行日记');
    expect(duet.artists.map((artist) => artist.name), ['周杰伦', '杨瑞代']);
  });

  test('treats a dated release folder as an album instead of an artist', () {
    final track = _pathEntry(
      '2021-08-31 苏格拉没有底/01.想象之中.flac',
    ).toTrack(account);

    expect(track.name, '想象之中');
    expect(track.artists.single.name, webDavUnknownArtist);
    expect(track.album.name, '苏格拉没有底');
  });

  test('cleans DF prefixes from a one-folder album layout', () {
    final track = _pathEntry('DF 寻雾启示/01.叹服.flac').toTrack(account);

    expect(track.artists.single.name, webDavUnknownArtist);
    expect(track.album.name, '寻雾启示');
  });

  test('extracts artist and album from a decorated release folder', () {
    final track = _pathEntry(
      '许嵩 - 许嵩 No.1 2010 FLAC16441/01.爱情里的眼泪.flac',
    ).toTrack(account);

    expect(track.artists.single.name, '许嵩');
    expect(track.album.name, '许嵩 No.1 2010');
  });

  test('extracts a collection artist and removes release-site tags', () {
    final track = _pathEntry(
      '【解压密码cndsd.com】王力宏20年精选 [FLAC_24B-48.0kHz]/02.Wei Yi.flac',
    ).toTrack(account);

    expect(track.artists.single.name, '王力宏');
    expect(track.album.name, '王力宏20年精选');
  });

  test('uses the artist folder when filename credit contains release text', () {
    final track = _pathEntry(
      '陶喆/暗恋 电影原声带/陶喆-暗恋 - 原本的你.wav',
    ).toTrack(account);

    expect(track.name, '原本的你');
    expect(track.artists.single.name, '陶喆');
    expect(track.album.name, '暗恋 电影原声带');
  });

  test('ignores disc folders when deriving artist and album', () {
    final track = _pathEntry(
      '周杰伦/叶惠美/CD 1/01.晴天.flac',
    ).toTrack(account);

    expect(track.artists.single.name, '周杰伦');
    expect(track.album.name, '叶惠美');
  });

  test('filters known release-site promotional audio', () {
    expect(_entry('CNHiFi.COM.flac').isSupportedAudio, isFalse);
    expect(_entry('02.安琪 - CNHiFi.COM.flac').isSupportedAudio, isFalse);
    expect(_entry('02 - 幻听 - CNHiFi.COM.flac').isSupportedAudio, isFalse);
    expect(_entry('real-song.flac').isSupportedAudio, isTrue);
  });

  test('extracts strong artist evidence from collection folders', () {
    expect(
      webDavExpectedCollectionArtist(
        'https://dav.example/Music/%E7%8E%8B%E5%8A%9B%E5%AE%8F20%E5%B9%B4%E7%B2%BE%E9%80%89/01.flac',
      ),
      '王力宏',
    );
    expect(
      webDavExpectedCollectionArtist(
        'https://dav.example/Music/2022-01-12%20%E6%A2%A6%E6%B8%B8%E8%AE%A1/01.flac',
      ),
      isNull,
    );
  });
}

WebDavEntry _entry(
  String name, {
  String? contentType,
  bool isDirectory = false,
}) {
  return WebDavEntry(
    uri: Uri.parse('https://dav.example/Music/$name'),
    displayName: name,
    isDirectory: isDirectory,
    contentType: contentType,
  );
}

WebDavEntry _pathEntry(String relativePath) {
  final uri = Uri.parse('https://dav.example/Music/').resolve(
    relativePath.split('/').map(Uri.encodeComponent).join('/'),
  );
  return WebDavEntry(
    uri: uri,
    displayName: relativePath.split('/').last,
    isDirectory: false,
    contentType: 'audio/flac',
  );
}
