import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/models/provider.dart';
import '../data/services/balance_service.dart';
import '../data/services/key_store.dart';
import '../data/services/preferences_service.dart';

class ProviderRecord {
  ProviderRecord({
    required this.defId,
    required this.apiKey,
    this.info,
    this.error,
    this.loading = false,
    this.updatedAt = '',
  });

  final String defId;
  String apiKey;
  BalanceInfo? info;
  String? error;
  bool loading;
  String updatedAt;

  ProviderDefinition? get definition => findProvider(defId);

  ProviderRecord copy() => ProviderRecord(
        defId: defId,
        apiKey: apiKey,
        info: info,
        error: error,
        loading: loading,
        updatedAt: updatedAt,
      );
}

class CurrencyGroup {
  CurrencyGroup({
    required this.currency,
    this.available = 0,
    this.total = 0,
    this.used = 0,
  });

  final String currency;
  double available;
  double total;
  double used;
}

/// Owns the provider dashboard state.
///
/// Async safety: every refresh-all / single refresh increments a session token;
/// stale responses are dropped before mutating state (see rule on async
/// resource isolation).
class AssetsController extends ChangeNotifier {
  AssetsController({
    required PreferencesService prefs,
    required KeyStore keyStore,
  })  : _prefs = prefs,
        _keyStore = keyStore;

  final PreferencesService _prefs;
  final KeyStore _keyStore;

  final List<ProviderRecord> _records = <ProviderRecord>[];
  int _session = 0;
  bool _refreshingAll = false;
  bool _loaded = false;

  List<ProviderRecord> get records => List<ProviderRecord>.unmodifiable(_records);
  bool get refreshingAll => _refreshingAll;
  bool get loaded => _loaded;

  List<CurrencyGroup> get heroGroups {
    final List<CurrencyGroup> groups = <CurrencyGroup>[];
    for (final ProviderRecord record in _records) {
      final BalanceInfo? info = record.info;
      if (info == null) {
        continue;
      }
      CurrencyGroup? group;
      for (final CurrencyGroup existing in groups) {
        if (existing.currency == info.currency) {
          group = existing;
          break;
        }
      }
      if (group == null) {
        group = CurrencyGroup(currency: info.currency);
        groups.add(group);
      }
      group.available += info.available;
      group.total += info.total;
      group.used += info.used;
    }
    return groups;
  }

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    _records.clear();
    final List<String> ids = _decodeIds(
      _prefs.getString(PreferencesService.keyAddedProviderIds),
    );
    for (final String id in ids) {
      if (findProvider(id) == null) {
        continue;
      }
      final String key = await _keyStore.read(KeyStore.providerKey(id));
      _records.add(ProviderRecord(defId: id, apiKey: key));
    }
    _loaded = true;
    notifyListeners();
    if (_records.isNotEmpty) {
      await refreshAll();
    }
  }

  List<String> _decodeIds(String raw) {
    if (raw.isEmpty) {
      return <String>[];
    }
    try {
      final Object? parsed = jsonDecode(raw);
      if (parsed is List) {
        return parsed.whereType<String>().toList(growable: false);
      }
    } catch (_) {
      // Legacy comma-separated value.
      return raw
          .split(',')
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return <String>[];
  }

  /// Re-reads keys after another screen edits them (System Two settings).
  Future<void> reloadKeys() async {
    for (final ProviderRecord record in _records) {
      record.apiKey =
          await _keyStore.read(KeyStore.providerKey(record.defId));
    }
    notifyListeners();
  }

  int indexOf(String id) =>
      _records.indexWhere((ProviderRecord r) => r.defId == id);

  bool isAdded(String id) => indexOf(id) >= 0;

  Future<void> refreshAll() async {
    _session++;
    final int token = _session;
    _refreshingAll = true;
    notifyListeners();
    for (final String id in _records.map((ProviderRecord r) => r.defId).toList()) {
      if (token != _session) {
        break;
      }
      await _queryOne(id, token);
    }
    if (token == _session) {
      _refreshingAll = false;
      notifyListeners();
    }
  }

  Future<void> refreshOne(String id) async {
    _session++;
    // A single-card refresh invalidates an in-flight refresh-all; reset the
    // bulk flag here or the button stays disabled forever.
    _refreshingAll = false;
    notifyListeners();
    await _queryOne(id, _session);
  }

  Future<void> _queryOne(String id, int token) async {
    final int index = indexOf(id);
    if (index < 0) {
      return;
    }
    final ProviderDefinition? def = findProvider(id);
    if (def == null) {
      return;
    }
    _records[index].loading = true;
    _records[index].error = null;
    notifyListeners();

    try {
      final ProviderBalanceResult result =
          await fetchProviderBalance(id, _records[index].apiKey);
      if (token != _session) {
        return;
      }
      final int at = indexOf(id);
      if (at < 0) {
        return;
      }
      if (result.success && result.info != null) {
        _records[at]
          ..info = result.info
          ..error = null
          ..updatedAt = result.info!.updatedAt;
      } else {
        _records[at]
          ..info = null
          ..error = result.error ?? '查询失败';
      }
      notifyListeners();
    } catch (error) {
      if (token != _session) {
        return;
      }
      final int at = indexOf(id);
      if (at >= 0) {
        // Transient failure keeps the last good value (keep-last-good).
        final bool kept = _records[at].info != null;
        _records[at].error = kept
            ? '网络异常（可重试，已保留上次成功结果）：$error'
            : '网络异常（可重试）：$error';
        notifyListeners();
      }
    } finally {
      if (token == _session) {
        final int at = indexOf(id);
        if (at >= 0) {
          _records[at].loading = false;
          notifyListeners();
        }
      }
    }
  }

  Future<void> saveProviderKey(String id, String key) async {
    final String trimmed = key.trim();
    final int index = indexOf(id);
    if (index < 0) {
      _records.add(ProviderRecord(defId: id, apiKey: trimmed));
    } else {
      _records[index].apiKey = trimmed;
    }
    await _keyStore.write(KeyStore.providerKey(id), trimmed);
    await _persistIds();
    notifyListeners();
    await refreshOne(id);
  }

  Future<void> removeProvider(String id) async {
    _session++;
    _records.removeWhere((ProviderRecord r) => r.defId == id);
    await _keyStore.delete(KeyStore.providerKey(id));
    await _persistIds();
    notifyListeners();
  }

  Future<void> _persistIds() async {
    final List<String> ids =
        _records.map((ProviderRecord r) => r.defId).toList(growable: false);
    await _prefs.setString(
      PreferencesService.keyAddedProviderIds,
      jsonEncode(ids),
    );
  }

  /// Raw key for prefilling the local edit dialog. Never log this value.
  String apiKeyOf(String id) {
    final int index = indexOf(id);
    return index < 0 ? '' : _records[index].apiKey;
  }

  /// Masked hint used by the key dialog; never renders the raw credential.
  String keyHint(String id) {
    final int index = indexOf(id);
    if (index < 0) {
      return '';
    }
    return maskKey(_records[index].apiKey);
  }
}
