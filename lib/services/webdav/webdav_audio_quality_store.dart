import 'dart:convert';

import 'package:spotube/models/webdav/webdav_audio_quality.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';

abstract final class WebDavAudioQualityStore {
  static const _storageKey = 'webdav_audio_quality_v1';
  static Map<String, WebDavAudioQualityCacheEntry> _entries = const {};

  static Map<String, WebDavAudioQualityCacheEntry> get entries =>
      Map.unmodifiable(_entries);

  static Map<String, WebDavAudioQuality> get qualitiesByPath => {
        for (final entry in _entries.values)
          if (entry.quality != null) entry.path: entry.quality!,
      };

  static WebDavAudioQualityCacheEntry? get(String path) => _entries[path];

  static Future<void> initialize() async {
    final raw = KVStoreService.sharedPreferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _entries = const {};
      return;
    }
    try {
      final json = (jsonDecode(raw) as Map).cast<String, dynamic>();
      _entries = json.map((path, value) {
        final entry = WebDavAudioQualityCacheEntry.fromJson(
          (value as Map).cast<String, dynamic>(),
        );
        return MapEntry(path, entry);
      });
    } catch (error, stackTrace) {
      _entries = const {};
      AppLogger.reportError(error, stackTrace);
    }
  }

  static Future<void> upsertAll(
    Iterable<WebDavAudioQualityCacheEntry> entries,
  ) async {
    final updated = Map<String, WebDavAudioQualityCacheEntry>.of(_entries);
    for (final entry in entries) {
      updated[entry.path] = entry;
    }
    _entries = updated;
    await _persist();
  }

  static Future<void> pruneAccount(
    String accountId,
    Set<String> activePaths,
  ) async {
    final updated = Map<String, WebDavAudioQualityCacheEntry>.of(_entries)
      ..removeWhere(
        (_, entry) =>
            entry.accountId == accountId && !activePaths.contains(entry.path),
      );
    if (updated.length == _entries.length) return;
    _entries = updated;
    await _persist();
  }

  static Future<void> removeAccount(String accountId) async {
    final updated = Map<String, WebDavAudioQualityCacheEntry>.of(_entries)
      ..removeWhere((_, entry) => entry.accountId == accountId);
    if (updated.length == _entries.length) return;
    _entries = updated;
    await _persist();
  }

  static Future<void> _persist() async {
    final encoded = jsonEncode(
      _entries.map((path, entry) => MapEntry(path, entry.toJson())),
    );
    await KVStoreService.sharedPreferences.setString(_storageKey, encoded);
  }
}
