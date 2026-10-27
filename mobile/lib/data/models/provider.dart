/// Provider categories surfaced in the add-provider sheet.
enum ProviderCategory { cnOfficial, aggregator }

enum BalanceQueryType { bearer }

/// Declarative description of one provider endpoint.
///
/// Business Rule: adding a Bearer provider is data only; the query engine
/// stays generic. Non-Bearer engines must add an explicit branch.
class BalanceQueryConfig {
  const BalanceQueryConfig({
    required this.endpoint,
    this.responsePath,
    this.useBearerPrefix,
    this.amountMultiplier,
    this.usedField,
    this.totalField,
    this.availableField,
    this.currencyField,
    this.defaultCurrency,
    this.successCodeField,
    this.successCodeValue,
  });

  final String endpoint;
  final String? responsePath;
  final bool? useBearerPrefix;
  final double? amountMultiplier;
  final String? usedField;
  final String? totalField;
  final String? availableField;
  final String? currencyField;
  final String? defaultCurrency;
  final String? successCodeField;
  final int? successCodeValue;
}

class ProviderDefinition {
  const ProviderDefinition({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.category,
    required this.balanceType,
    required this.balanceConfig,
    required this.brandColor,
    required this.websiteUrl,
    required this.iconAsset,
    this.supportsThinking = false,
    this.chatEndpoint = '/v1/chat/completions',
    this.modelsEndpoint = '/v1/models',
  });

  final String id;
  final String name;
  final String baseUrl;
  final ProviderCategory category;
  final BalanceQueryType balanceType;
  final BalanceQueryConfig balanceConfig;
  final String brandColor;
  final String websiteUrl;
  final String iconAsset;
  final bool supportsThinking;

  /// Provider-specific OpenAI-compatible chat path.
  ///
  /// Business Rule: never assume every provider lives under `/v1`; OpenRouter
  /// uses `/api/v1` and Novita uses `/openai/v1`.
  final String chatEndpoint;
  final String modelsEndpoint;

  String get categoryLabel =>
      category == ProviderCategory.cnOfficial ? '国内官方' : 'API聚合';
}

class BalanceInfo {
  const BalanceInfo({
    required this.providerId,
    required this.total,
    required this.used,
    required this.available,
    required this.currency,
    required this.updatedAt,
  });

  final String providerId;
  final double total;
  final double used;
  final double available;
  final String currency;
  final String updatedAt;

  double get usagePercentage {
    if (total <= 0) {
      return 0;
    }
    return (used / total) * 100;
  }
}

String currencySymbol(String currency) => currency == 'CNY' ? '¥' : '\$';

/// Closed-set registry ported from the HarmonyOS implementation.
const List<ProviderDefinition> providers = <ProviderDefinition>[
  ProviderDefinition(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    category: ProviderCategory.cnOfficial,
    balanceType: BalanceQueryType.bearer,
    balanceConfig: BalanceQueryConfig(
      endpoint: '/user/balance',
      responsePath: 'balance_infos',
      availableField: 'total_balance',
      currencyField: 'currency',
      defaultCurrency: 'CNY',
    ),
    brandColor: '#4D6BFE',
    websiteUrl: 'https://platform.deepseek.com',
    iconAsset: 'assets/providers/deepseek.png',
    supportsThinking: true,
    chatEndpoint: '/chat/completions',
    modelsEndpoint: '/models',
  ),
  ProviderDefinition(
    id: 'stepfun',
    name: '阶跃 StepFun',
    baseUrl: 'https://api.stepfun.com',
    category: ProviderCategory.cnOfficial,
    balanceType: BalanceQueryType.bearer,
    balanceConfig: BalanceQueryConfig(
      endpoint: '/v1/accounts',
      availableField: 'balance',
      defaultCurrency: 'CNY',
    ),
    brandColor: '#0EA5E9',
    websiteUrl: 'https://platform.stepfun.com',
    iconAsset: 'assets/providers/stepfun.png',
  ),
  ProviderDefinition(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai',
    category: ProviderCategory.aggregator,
    balanceType: BalanceQueryType.bearer,
    balanceConfig: BalanceQueryConfig(
      endpoint: '/api/v1/credits',
      responsePath: 'data',
      totalField: 'total_credits',
      usedField: 'total_usage',
      defaultCurrency: 'USD',
    ),
    brandColor: '#E85D3D',
    websiteUrl: 'https://openrouter.ai',
    iconAsset: 'assets/providers/openrouter.png',
    chatEndpoint: '/api/v1/chat/completions',
    modelsEndpoint: '/api/v1/models',
  ),
  ProviderDefinition(
    id: 'novita',
    name: 'Novita AI',
    baseUrl: 'https://api.novita.ai',
    category: ProviderCategory.aggregator,
    balanceType: BalanceQueryType.bearer,
    balanceConfig: BalanceQueryConfig(
      endpoint: '/v3/user/balance',
      availableField: 'availableBalance',
      amountMultiplier: 0.0001,
      defaultCurrency: 'USD',
    ),
    brandColor: '#10B981',
    websiteUrl: 'https://novita.ai',
    iconAsset: 'assets/providers/novita.png',
    chatEndpoint: '/openai/v1/chat/completions',
    modelsEndpoint: '/openai/v1/models',
  ),
  ProviderDefinition(
    id: 'kimi',
    name: 'Kimi',
    baseUrl: 'https://api.moonshot.cn',
    category: ProviderCategory.cnOfficial,
    balanceType: BalanceQueryType.bearer,
    balanceConfig: BalanceQueryConfig(
      endpoint: '/v1/users/me/balance',
      responsePath: 'data',
      availableField: 'available_balance',
      defaultCurrency: 'CNY',
      successCodeField: 'code',
      successCodeValue: 0,
    ),
    brandColor: '#1A1A1A',
    websiteUrl: 'https://platform.kimi.com',
    iconAsset: 'assets/providers/kimi.png',
    supportsThinking: true,
  ),
  ProviderDefinition(
    id: 'mimo',
    name: '小米 MiMo',
    baseUrl: 'https://api.xiaomimimo.com',
    category: ProviderCategory.cnOfficial,
    balanceType: BalanceQueryType.bearer,
    balanceConfig: BalanceQueryConfig(
      endpoint: '/v1/models',
      availableField: '',
      defaultCurrency: 'CNY',
    ),
    brandColor: '#FF6900',
    websiteUrl: 'https://mimo.mi.com',
    iconAsset: 'assets/providers/mimo.png',
    supportsThinking: true,
  ),
];

const List<String> mimoThinkingModels = <String>[
  'mimo-v2.6-flash',
  'mimo-v2.6-pro',
  'mimo-v2.6-pro-ultraspeed',
  'mimo-v2.5-pro',
  'mimo-v2.5',
];

const List<String> kimiThinkingModels = <String>[
  'kimi-k3',
  'kimi-k2.7-code',
  'kimi-k2.7-code-highspeed',
  'kimi-k2.6',
];

ProviderDefinition? findProvider(String id) {
  for (final ProviderDefinition p in providers) {
    if (p.id == id) {
      return p;
    }
  }
  return null;
}

bool isThinkingSupported(String providerId, String modelId) {
  if (providerId == 'deepseek') {
    return true;
  }
  if (providerId == 'mimo') {
    if (modelId.isEmpty || modelId == '选择模型') {
      return true;
    }
    final String lower = modelId.toLowerCase().trim();
    for (final String m in mimoThinkingModels) {
      if (lower == m || lower.contains(m)) {
        return true;
      }
    }
    return lower.contains('mimo-v2.6') || lower.contains('mimo-v2.5');
  }
  if (providerId == 'kimi') {
    if (modelId.isEmpty || modelId == '选择模型') {
      return true;
    }
    final String lower = modelId.toLowerCase().trim();
    for (final String m in kimiThinkingModels) {
      if (lower == m || lower.contains(m)) {
        return true;
      }
    }
    return lower.contains('k3') || lower.contains('k2.7') || lower.contains('k2.6');
  }
  return findProvider(providerId)?.supportsThinking == true;
}
