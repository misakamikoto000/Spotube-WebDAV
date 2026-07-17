import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/provider/webdav/webdav_library_provider.dart';
import 'package:spotube/services/webdav/webdav_account_store.dart';

class WebDavAccountsNotifier extends Notifier<List<WebDavAccount>> {
  @override
  List<WebDavAccount> build() => WebDavAccountStore.accounts;

  Future<void> upsert(WebDavAccount account) async {
    final index = state.indexWhere((item) => item.id == account.id);
    final next = [...state];
    if (index == -1) {
      next.add(account);
    } else {
      if (state[index].rootUri != account.rootUri) {
        await ref.read(webDavLibraryProvider.notifier).remove(account.id);
      }
      next[index] = account;
    }
    await WebDavAccountStore.saveAll(next);
    state = WebDavAccountStore.accounts;
  }

  Future<void> remove(String accountId) async {
    await ref.read(webDavLibraryProvider.notifier).remove(accountId);
    await WebDavAccountStore.saveAll(
      state.where((account) => account.id != accountId),
    );
    state = WebDavAccountStore.accounts;
  }
}

final webDavAccountsProvider =
    NotifierProvider<WebDavAccountsNotifier, List<WebDavAccount>>(
  WebDavAccountsNotifier.new,
);
