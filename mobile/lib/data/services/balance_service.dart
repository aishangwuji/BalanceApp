import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/provider.dart';

class ProviderBalanceResult {
  const ProviderBalanceResult({required this.success, this.info, this.error});

  final bool success;
  final BalanceInfo? info;
  final String? error;
}

/// Deterministic failures (bad key, unknown provider, auth, non-2xx, bad JSON)
/// are returned as `success: false`. Transient transport failures are thrown
/// so the caller can keep the last good value and offer a retry.
class AuthFailedException implements Exception {
  const AuthFailedException(this.status);
  final int status;

  @override
  String toString() => 'Authentication failed (HTTP $status)';
}

class DeterministicException implements Exception {
  const DeterministicException(this.message);
  final String message;

  @override
  String toString() => message;
}

const Duration _timeout = Duration(seconds: 15);

double _toNumber(Object? value) {
  if (value is num) {
    return value.toDouble().isFinite ? value.toDouble() : 0;
  }
  if (value is String) {
    final double parsed = double.tryParse(value.trim()) ?? 0;
    return parsed.isFinite ? parsed : 0;
  }
  return 0;
}

Object? _fieldOf(Object? object, String? field) {
  if (object is! Map || field == null || field.isEmpty) {
    return null;
  }
  return object[field];
}

Object? _navigatePath(Object? root, String? path) {
  if (path == null || path.isEmpty) {
    return root;
  }
  Object? current = root;
  for (final String key in path.split('.')) {
    current = _fieldOf(current, key);
    if (current == null) {
      return null;
    }
  }
  return current;
}

String _buildUrl(String baseUrl, String endpoint) {
  if (endpoint.startsWith('http')) {
    return endpoint;
  }
  if (endpoint.isEmpty) {
    return baseUrl;
  }
  final String base =
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  return '$base$endpoint';
}

Future<BalanceInfo> _queryBearer(ProviderDefinition def, String apiKey) async {
  final BalanceQueryConfig config = def.balanceConfig;
  final Uri uri = Uri.parse(_buildUrl(def.baseUrl, config.endpoint));
  final bool bearer = config.useBearerPrefix ?? true;
  final Map<String, String> headers = <String, String>{
    'Authorization': bearer ? 'Bearer $apiKey' : apiKey,
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  final http.Client client = http.Client();
  late final http.Response response;
  try {
    response = await client.get(uri, headers: headers).timeout(_timeout);
  } on TimeoutException {
    rethrow;
  } catch (error) {
    debugPrint('BalanceService: network error provider=${def.id} error=$error');
    rethrow;
  } finally {
    client.close();
  }

  if (response.statusCode == 401 || response.statusCode == 403) {
    throw AuthFailedException(response.statusCode);
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw DeterministicException(
      'API error (HTTP ${response.statusCode}): '
      '${_truncate(response.body)}',
    );
  }

  return parseBalanceBody(def, response.body);
}

/// Pure response parser extracted for unit tests.
///
/// Boundary contract: HTTP status is already validated; this function owns
/// JSON shape validation, business-code checks and value derivation.
@visibleForTesting
BalanceInfo parseBalanceBody(ProviderDefinition def, String body) {
  final BalanceQueryConfig config = def.balanceConfig;
  final Object? root;
  try {
    root = jsonDecode(body);
  } catch (_) {
    throw const DeterministicException('Failed to parse response');
  }
  if (root is! Map) {
    throw const DeterministicException('Failed to parse response');
  }

  final String? successField = config.successCodeField;
  final int? successValue = config.successCodeValue;
  if (successField != null && successValue != null) {
    final Object? code = root[successField];
    final bool ok = (code is num && code.toInt() == successValue) ||
        (code is String && code == successValue.toString());
    if (!ok) {
      throw DeterministicException(
        'API error (business code): ${_truncate(body)}',
      );
    }
  }

  final Object? target = _navigatePath(root, config.responsePath);
  double available = 0;
  double total = 0;
  double used = 0;
  String currency = config.defaultCurrency ?? 'CNY';

  if (target is List) {
    final String availKey = config.availableField?.isNotEmpty == true
        ? config.availableField!
        : 'total_balance';
    final String currencyKey = config.currencyField?.isNotEmpty == true
        ? config.currencyField!
        : 'currency';
    for (final Object? item in target) {
      if (item is Map) {
        final double balance = _toNumber(item[availKey]);
        available += balance;
        total += balance;
        final Object? c = item[currencyKey];
        if (c is String && c.isNotEmpty) {
          currency = c;
        }
      }
    }
  } else if (target is Map) {
    available = _toNumber(_fieldOf(target, config.availableField));
    total = _toNumber(_fieldOf(target, config.totalField));
    used = _toNumber(_fieldOf(target, config.usedField));
    if (config.currencyField != null) {
      final Object? c = _fieldOf(target, config.currencyField);
      if (c is String && c.isNotEmpty) {
        currency = c;
      }
    }
  } else if (target is num) {
    available = target.toDouble();
    total = available;
  }

  final double multiplier = config.amountMultiplier ?? 1;
  available *= multiplier;
  total *= multiplier;
  used *= multiplier;

  if (config.usedField == null && total > 0 && used == 0 && total > available) {
    used = total - available;
  }
  if (config.availableField == null && total > 0 && available == 0 && used > 0) {
    available = total - used;
  }

  final double finalTotal = total > 0 ? total : available + used;
  return BalanceInfo(
    providerId: def.id,
    total: finalTotal,
    used: used,
    available: available,
    currency: currency,
    updatedAt: _nowLabel(),
  );
}

String _truncate(String text) =>
    text.length <= 300 ? text : text.substring(0, 300);

String _nowLabel() {
  final DateTime now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}:${two(now.minute)}';
}

/// Public entry: validates inputs at the boundary before touching the network.
Future<ProviderBalanceResult> fetchProviderBalance(
  String providerId,
  String apiKey,
) async {
  final String key = apiKey.trim();
  if (key.isEmpty) {
    return const ProviderBalanceResult(
      success: false,
      error: 'API key is empty',
    );
  }
  final ProviderDefinition? def = findProvider(providerId);
  if (def == null) {
    return const ProviderBalanceResult(
      success: false,
      error: 'Unknown provider',
    );
  }
  try {
    final BalanceInfo info = await _queryBearer(def, key);
    return ProviderBalanceResult(success: true, info: info);
  } on AuthFailedException catch (error) {
    return ProviderBalanceResult(success: false, error: error.toString());
  } on DeterministicException catch (error) {
    return ProviderBalanceResult(success: false, error: error.message);
  }
}
