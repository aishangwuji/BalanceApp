/*
 * ProviderRegistry.ets
 *
 * 数据驱动的供应商注册表 —— 对齐智额 `models/provider_definition.dart` +
 * `config/provider_registry.dart` 的实现形式（酒馆/SillyTavern 相关除外）。
 *
 * Business Rule: 新增供应商只需追加一条 ProviderDefinition 数据，无需手写
 *   查询函数；查询语义由 BalanceQueryConfig 描述，通用 bearer 引擎执行。
 */

export enum ProviderCategory {
  CnOfficial = '国内官方',
  Aggregator = 'API聚合',
}

export enum BalanceQueryType {
  Bearer = 'bearer',
}

export interface BalanceQueryConfig {
  /** 余额端点路径，拼接到 baseUrl 后（绝对 URL 也允许）。 */
  endpoint: string;
  /** JSON 导航路径，如 'data'、'balance_infos'；缺省为整包。 */
  responsePath?: string;
  /** Authorization 头是否带 Bearer 前缀（智谱式裸 key 预留，当前均为 true）。 */
  useBearerPrefix?: boolean;
  /** 金额换算因子，如 Novita 为 0.0001（单位 0.0001 USD）。 */
  amountMultiplier?: number;
  /** 已用字段名；缺省时按 total-available 推导。 */
  usedField?: string;
  /** 总额字段名。 */
  totalField?: string;
  /** 可用/余额字段名；数组响应时对数组元素求和。 */
  availableField?: string;
  /** 币种字段名；缺省用 defaultCurrency。 */
  currencyField?: string;
  /** 兜底币种。 */
  defaultCurrency?: string;
  /**
   * 业务成功码字段名（如 Kimi 的顶层 `code`）；缺省不校验。
   * Reason: Kimi 用 HTTP 200 + code!=0 表业务失败，与它家只看 HTTP 状态不同。
   */
  successCodeField?: string;
  /** 与 successCodeField 配对的成功值（如 Kimi 为 0）。 */
  successCodeValue?: number;
}

export interface ProviderDefinition {
  id: string;
  name: string;
  baseUrl: string;
  category: ProviderCategory;
  balanceType: BalanceQueryType;
  balanceConfig: BalanceQueryConfig;
  /** 品牌色（卡片点缀用，十六进制字符串）。 */
  brandColor: string;
  websiteUrl: string;
  /**
   * 品牌图标资源名（entry resources/base/media 下的 png，不带后缀）。
   * Reason: ArkTS $r 不支持动态拼接，界面侧用静态映射取图（见 Index.providerIcon）。
   */
  icon: string;
  /**
   * 是否支持 OpenAI 格式思考模式（thinking/reasoning_effort）。
   * Business Rule: 仅对官方明确支持该扩展的厂商下发思考参数，避免对
   *   未知厂商透传非标准字段导致 400。
   */
  supportsThinking?: boolean;
}

/** 统一余额模型 —— 对齐智额 `models/balance_info.dart`。 */
export interface BalanceInfo {
  providerId: string;
  total: number;
  used: number;
  available: number;
  currency: string;
  updatedAt: string;
}

export function usagePercentage(info: BalanceInfo): number {
  if (info.total > 0) {
    return (info.used / info.total) * 100.0;
  }
  return 0.0;
}

export function currencySymbol(currency: string): string {
  if (currency === 'CNY') {
    return '¥';
  }
  return '$';
}

/** Reason: 以下 6 家配置逐项对照智额 registry（endpoint/responsePath/字段名/换算因子一致）。 */
export const PROVIDERS: ProviderDefinition[] = [
  {
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    category: ProviderCategory.CnOfficial,
    balanceType: BalanceQueryType.Bearer,
    balanceConfig: {
      endpoint: '/user/balance',
      responsePath: 'balance_infos',
      availableField: 'total_balance',
      currencyField: 'currency',
      defaultCurrency: 'CNY',
    },
    brandColor: '#4D6BFE',
    icon: 'deepseek',
    websiteUrl: 'https://platform.deepseek.com',
    supportsThinking: true,
  },
  {
    id: 'siliconflow_cn',
    name: '硅基流动 CN',
    baseUrl: 'https://api.siliconflow.cn',
    category: ProviderCategory.CnOfficial,
    balanceType: BalanceQueryType.Bearer,
    balanceConfig: {
      endpoint: '/v1/user/info',
      responsePath: 'data',
      availableField: 'totalBalance',
      defaultCurrency: 'CNY',
    },
    brandColor: '#7C3AED',
    icon: 'siliconflow',
    websiteUrl: 'https://cloud.siliconflow.cn',
  },
  {
    id: 'siliconflow_en',
    name: '硅基流动 EN',
    baseUrl: 'https://api.siliconflow.com',
    category: ProviderCategory.CnOfficial,
    balanceType: BalanceQueryType.Bearer,
    balanceConfig: {
      endpoint: '/v1/user/info',
      responsePath: 'data',
      availableField: 'totalBalance',
      defaultCurrency: 'USD',
    },
    brandColor: '#7C3AED',
    icon: 'siliconflow',
    websiteUrl: 'https://cloud.siliconflow.com',
  },
  {
    id: 'stepfun',
    name: '阶跃 StepFun',
    baseUrl: 'https://api.stepfun.com',
    category: ProviderCategory.CnOfficial,
    balanceType: BalanceQueryType.Bearer,
    balanceConfig: {
      endpoint: '/v1/accounts',
      availableField: 'balance',
      defaultCurrency: 'CNY',
    },
    brandColor: '#0EA5E9',
    icon: 'stepfun',
    websiteUrl: 'https://platform.stepfun.com',
  },
  {
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai',
    category: ProviderCategory.Aggregator,
    balanceType: BalanceQueryType.Bearer,
    balanceConfig: {
      endpoint: '/api/v1/credits',
      responsePath: 'data',
      totalField: 'total_credits',
      usedField: 'total_usage',
      defaultCurrency: 'USD',
    },
    brandColor: '#E85D3D',
    icon: 'openrouter',
    websiteUrl: 'https://openrouter.ai',
  },
  {
    id: 'novita',
    name: 'Novita AI',
    baseUrl: 'https://api.novita.ai',
    category: ProviderCategory.Aggregator,
    balanceType: BalanceQueryType.Bearer,
    balanceConfig: {
      endpoint: '/v3/user/balance',
      availableField: 'availableBalance',
      amountMultiplier: 0.0001,
      defaultCurrency: 'USD',
    },
    brandColor: '#10B981',
    icon: 'novita',
    websiteUrl: 'https://novita.ai',
  },
  {
    id: 'kimi',
    name: 'Kimi',
    baseUrl: 'https://api.moonshot.cn',
    category: ProviderCategory.CnOfficial,
    balanceType: BalanceQueryType.Bearer,
    balanceConfig: {
      endpoint: '/v1/users/me/balance',
      responsePath: 'data',
      availableField: 'available_balance',
      defaultCurrency: 'CNY',
      successCodeField: 'code',
      successCodeValue: 0,
    },
    brandColor: '#1A1A1A',
    icon: 'kimi',
    websiteUrl: 'https://platform.kimi.com',
    supportsThinking: true,
  },
  {
    id: 'mimo',
    name: '小米 MiMo',
    baseUrl: 'https://api.xiaomimimo.com',
    category: ProviderCategory.CnOfficial,
    balanceType: BalanceQueryType.Bearer,
    balanceConfig: {
      endpoint: '/v1/models',
      availableField: '',
      defaultCurrency: 'CNY',
    },
    brandColor: '#FF6900',
    icon: 'mimo',
    websiteUrl: 'https://mimo.mi.com',
    supportsThinking: true,
  },
];

export const MIMO_THINKING_MODELS: string[] = [
  'mimo-v2.6-flash',
  'mimo-v2.6-pro',
  'mimo-v2.6-pro-ultraspeed',
  'mimo-v2.5-pro',
  'mimo-v2.5'
];

export const KIMI_THINKING_MODELS: string[] = [
  'kimi-k3',
  'kimi-k2.7-code',
  'kimi-k2.7-code-highspeed',
  'kimi-k2.6'
];

/**
 * 判断指定服务商及模型是否支持深度思考模式
 */
export function isThinkingSupported(providerId: string, modelId?: string): boolean {
  if (providerId === 'deepseek') {
    return true;
  }
  if (providerId === 'mimo') {
    if (!modelId || modelId.length === 0 || modelId === '选择模型') {
      return true;
    }
    const lower: string = modelId.toLowerCase().trim();
    let i: number = 0;
    while (i < MIMO_THINKING_MODELS.length) {
      if (lower === MIMO_THINKING_MODELS[i] || lower.includes(MIMO_THINKING_MODELS[i])) {
        return true;
      }
      i += 1;
    }
    return lower.includes('mimo-v2.6') || lower.includes('mimo-v2.5');
  }
  if (providerId === 'kimi') {
    if (!modelId || modelId.length === 0 || modelId === '选择模型') {
      return true;
    }
    const lower: string = modelId.toLowerCase().trim();
    let i: number = 0;
    while (i < KIMI_THINKING_MODELS.length) {
      if (lower === KIMI_THINKING_MODELS[i] || lower.includes(KIMI_THINKING_MODELS[i])) {
        return true;
      }
      i += 1;
    }
    return lower.includes('k3') || lower.includes('k2.7') || lower.includes('k2.6');
  }
  const def: ProviderDefinition | undefined = findProvider(providerId);
  return def !== undefined && def.supportsThinking === true;
}

export function findProvider(id: string): ProviderDefinition | undefined {
  let i: number = 0;
  while (i < PROVIDERS.length) {
    if (PROVIDERS[i].id === id) {
      return PROVIDERS[i];
    }
    i += 1;
  }
  return undefined;
}

export function categoryLabel(cat: ProviderCategory): string {
  if (cat === ProviderCategory.CnOfficial) {
    return '国内官方';
  }
  return 'API聚合';
}
