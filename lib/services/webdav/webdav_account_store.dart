import 'dart:convert';

import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';

abstract class WebDavAccountStore {
  static const _storageKey = 'webdav_accounts_v1';
  static List<WebDavAccount> _accounts = const [];

  static List<WebDavAccount> get accounts => List.unmodifiable(_accounts);

  static Future<void> initialize() async {
    final raw = KVStoreService.sharedPreferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _accounts = const [];
      return;
    }

    try {
      final values = (jsonDecode(raw) as List).cast<Map>();
      _accounts = values
          .map((value) => WebDavAccount.fromStorageJson(
                value.cast<String, dynamic>(),
              ))
          .toList(growable: false);
    } catch (error, stackTrace) {
      _accounts = const [];
      AppLogger.reportError(error, stackTrace);
    }
  }

  static WebDavAccount? getById(String id) {
    for (final account in _accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  static Map<String, String>? headersFor(String? accountId) {
    if (accountId == null) return null;
    return getById(accountId)?.authorizationHeaders;
  }

  static Future<void> saveAll(Iterable<WebDavAccount> accounts) async {
    final next = accounts.toList(growable: false);
    final encoded = jsonEncode(
      next.map((account) => account.toStorageJson()).toList(growable: false),
    );
    await KVStoreService.sharedPreferences.setString(_storageKey, encoded);
    _accounts = next;
  }
}
