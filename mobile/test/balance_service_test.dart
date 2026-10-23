import 'package:balance_app/data/models/provider.dart';
import 'package:balance_app/data/services/balance_service.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderDefinition provider(String id) {
  final ProviderDefinition? def = findProvider(id);
  if (def == null) {
    throw StateError('missing provider $id');
  }
  return def;
}

void main() {
  group('parseBalanceBody', () {
    test('sums DeepSeek balance_infos array', () {
      final BalanceInfo info = parseBalanceBody(
        provider('deepseek'),
        '{"is_available":true,"balance_infos":['
        '{"currency":"CNY","total_balance":"12.34"},'
        '{"currency":"CNY","total_balance":"7.66"}]}',
      );
      expect(info.available, closeTo(20, 0.0001));
      expect(info.total, closeTo(20, 0.0001));
      expect(info.currency, 'CNY');
      expect(info.used, 0);
    });

    test('derives available for OpenRouter credits', () {
      final BalanceInfo info = parseBalanceBody(
        provider('openrouter'),
        '{"data":{"total_credits":50,"total_usage":12.5}}',
      );
      expect(info.total, closeTo(50, 0.0001));
      expect(info.used, closeTo(12.5, 0.0001));
      expect(info.available, closeTo(37.5, 0.0001));
      expect(info.currency, 'USD');
    });

    test('applies Novita unit multiplier', () {
      final BalanceInfo info = parseBalanceBody(
        provider('novita'),
        '{"availableBalance":1234567}',
      );
      expect(info.available, closeTo(123.4567, 0.0001));
      expect(info.currency, 'USD');
    });

    test('rejects Kimi business failure code', () {
      expect(
        () => parseBalanceBody(
          provider('kimi'),
          '{"code":1,"data":{"available_balance":9.5}}',
        ),
        throwsA(isA<DeterministicException>()),
      );
    });

    test('accepts Kimi success code zero', () {
      final BalanceInfo info = parseBalanceBody(
        provider('kimi'),
        '{"code":0,"data":{"available_balance":9.5}}',
      );
      expect(info.available, closeTo(9.5, 0.0001));
      expect(info.currency, 'CNY');
    });

    test('rejects malformed JSON', () {
      expect(
        () => parseBalanceBody(provider('deepseek'), 'not-json'),
        throwsA(isA<DeterministicException>()),
      );
    });
  });

  group('provider registry', () {
    test('uses provider-specific OpenAI-compatible paths', () {
      expect(provider('openrouter').chatEndpoint, '/api/v1/chat/completions');
      expect(provider('openrouter').modelsEndpoint, '/api/v1/models');
      expect(provider('novita').chatEndpoint, '/openai/v1/chat/completions');
      expect(provider('novita').modelsEndpoint, '/openai/v1/models');
      expect(provider('deepseek').chatEndpoint, '/chat/completions');
      expect(provider('deepseek').modelsEndpoint, '/models');
    });
  });

  group('fetchProviderBalance boundary', () {
    test('rejects an empty key before networking', () async {
      final ProviderBalanceResult result =
          await fetchProviderBalance('deepseek', '   ');
      expect(result.success, false);
      expect(result.error, 'API key is empty');
    });

    test('rejects an unknown provider before networking', () async {
      final ProviderBalanceResult result =
          await fetchProviderBalance('unknown', 'sk-test');
      expect(result.success, false);
      expect(result.error, 'Unknown provider');
    });
  });
}
