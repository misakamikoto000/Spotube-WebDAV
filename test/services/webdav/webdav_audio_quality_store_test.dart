import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/webdav/webdav_audio_quality.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/webdav/webdav_audio_quality_store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
    await WebDavAudioQualityStore.initialize();
  });

  test('persists detected quality locally and validates file signatures',
      () async {
    final entry = WebDavEntry(
      uri: Uri.parse('https://dav.example/Music/track.flac'),
      displayName: 'track.flac',
      isDirectory: false,
      contentLength: 100000000,
      lastModified: DateTime.utc(2026, 7, 17),
    );
    final cached = WebDavAudioQualityCacheEntry.fromProbe(
      accountId: 'account-1',
      entry: entry,
      quality: const WebDavAudioQuality(
        container: 'flac',
        codec: 'FLAC',
        lossless: true,
        bitDepth: 24,
        sampleRate: 96000,
      ),
    );

    await WebDavAudioQualityStore.upsertAll([cached]);
    await WebDavAudioQualityStore.initialize();

    final restored = WebDavAudioQualityStore.get(entry.uri.toString());
    expect(restored, isNotNull);
    expect(restored!.matches(entry), isTrue);
    expect(restored.quality!.bitDepth, 24);
    expect(restored.toJson().toString(), isNot(contains('password')));

    final changed = WebDavEntry(
      uri: entry.uri,
      displayName: entry.displayName,
      isDirectory: false,
      contentLength: entry.contentLength! + 1,
      lastModified: entry.lastModified,
    );
    expect(restored.matches(changed), isFalse);
  });

  test('prunes quality records that disappeared from an account', () async {
    final entry = WebDavEntry(
      uri: Uri.parse('https://dav.example/Music/old.flac'),
      displayName: 'old.flac',
      isDirectory: false,
    );
    await WebDavAudioQualityStore.upsertAll([
      WebDavAudioQualityCacheEntry.fromProbe(
        accountId: 'account-1',
        entry: entry,
        quality: null,
      ),
    ]);

    await WebDavAudioQualityStore.pruneAccount('account-1', const {});

    expect(WebDavAudioQualityStore.get(entry.uri.toString()), isNull);
  });
}
