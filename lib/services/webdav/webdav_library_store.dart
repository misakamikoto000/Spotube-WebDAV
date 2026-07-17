import 'dart:convert';

import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/webdav/chinese_metadata_normalizer.dart';

abstract class WebDavLibraryStore {
  static const _storageKey = 'webdav_library_tracks_v1';
  static Map<String, List<SpotubeLocalTrackObject>> _tracksByAccount = const {};

  static Map<String, List<SpotubeLocalTrackObject>> get tracksByAccount =>
      Map.unmodifiable(_tracksByAccount);

  static Future<void> initialize() async {
    final raw = KVStoreService.sharedPreferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _tracksByAccount = const {};
      return;
    }

    try {
      final values = (jsonDecode(raw) as Map).cast<String, dynamic>();
      var migrated = false;
      _tracksByAccount = values.map(
        (accountId, tracks) {
          final normalizedTracks = <SpotubeLocalTrackObject>[];
          for (final track in tracks as List) {
            final decoded = SpotubeTrackObject.fromJson(
              (track as Map).cast<String, dynamic>(),
            ) as SpotubeLocalTrackObject;
            if (webDavTrackIsPromotional(decoded)) {
              migrated = true;
              continue;
            }
            final normalized =
                ChineseMetadataNormalizer.normalizeTrack(decoded);
            if (!identical(decoded, normalized)) migrated = true;
            normalizedTracks.add(normalized);
          }
          return MapEntry(accountId, normalizedTracks);
        },
      );
      if (migrated) await _persist();
    } catch (error, stackTrace) {
      _tracksByAccount = const {};
      AppLogger.reportError(error, stackTrace);
    }
  }

  static Future<void> save(
    String accountId,
    Iterable<SpotubeLocalTrackObject> tracks,
  ) async {
    _tracksByAccount = {
      ..._tracksByAccount,
      accountId: tracks
          .where((track) => !webDavTrackIsPromotional(track))
          .map(ChineseMetadataNormalizer.normalizeTrack)
          .toList(growable: false),
    };
    await _persist();
  }

  static Future<void> remove(String accountId) async {
    if (!_tracksByAccount.containsKey(accountId)) return;
    _tracksByAccount = Map.of(_tracksByAccount)..remove(accountId);
    await _persist();
  }

  static Future<void> _persist() async {
    final encoded = jsonEncode(
      _tracksByAccount.map(
        (accountId, tracks) => MapEntry(
          accountId,
          tracks.map((track) => track.toJson()).toList(growable: false),
        ),
      ),
    );
    await KVStoreService.sharedPreferences.setString(_storageKey, encoded);
  }
}
