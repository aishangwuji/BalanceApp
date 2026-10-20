/*
 * TopicGateService.ets
 *
 * 写时上下文净化（topic gate）—— 对齐 nanobot 的拦截点与语义：
 * 1. 只在助手回复写入历史时判定一次，掩码随消息持久化；之后回放按 keep 投影，
 *    同一段永不重复判定（判定结果即缓存，token 序列因此保持稳定）。
 * 2. 判定主题取「产生该回复的用户消息」，不是当前会话主题；
 *    否则会话漂移后会把当时切题的内容误删。
 * 3. 流式阶段原文已交付用户、无法回收，故不在接收端设点，只影响后续回放。
 * 4. 任何失败（无 Key/网络/结构非法/条数不符/不足两段）一律 fail-open 保留全文。
 *
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，捕获异常转为 Error 类型。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChatMessage, TopicGateMask } from '../models/ChatModels';
import { JevService } from './JevService';
import {
  KEY_TOPIC_GATE_ENABLED, KEY_TOPIC_GATE_API_KEY, KEY_TOPIC_GATE_THRESHOLD,
  KEY_TOPIC_GATE_ENDPOINT, KEY_TOPIC_GATE_MODEL, DEFAULT_TOPIC_GATE_THRESHOLD
} from './SettingsService';

const DOMAIN = 0x0000;
const TAG = 'TopicGateService';
const PREFS_NAME = 'balance_prefs';

/** 作为主题送入判定的最大长度（与 nanobot 一致：过长主题无助于相关性判断）。 */
const TOPIC_MAX_CHARS = 400;
/** 落库回显用的主题长度上限。 */
const TOPIC_STORE_MAX_CHARS = 120;

/**
 * 切段边界：中英文句末与分号、换行。
 * Business Rule: 切段必须无损（join 后等于原文），否则掩码长度与回放文本无法对齐。
 */
const SEGMENT_BOUNDARIES = '。！？!?；;\n';

export interface TopicGateConfig {
  enabled: boolean;
  apiKey: string;
  threshold: number;
  endpoint: string;
  model: string;
}

/** 按句末标点切段，保留分隔符本身。 */
export function splitSegments(text: string): string[] {
  const segments: string[] = [];
  let start: number = 0;
  let i: number = 0;
  while (i < text.length) {
    const ch: string = text.charAt(i);
    if (SEGMENT_BOUNDARIES.indexOf(ch) >= 0) {
      segments.push(text.substring(start, i + 1));
      start = i + 1;
    }
    i += 1;
  }
  if (start < text.length) {
    segments.push(text.substring(start));
  }
  return segments;
}

/**
 * 回放投影：丢弃低于阈值的分段。
 * Business Rule: 掩码缺省或与切段长度不符时返回原文（fail-open）——
 *   宁可多带一段历史，也不能因数据错位删掉正文。
 */
export function applyTopicMask(content: string, mask: TopicGateMask | undefined): string {
  if (mask === undefined) {
    return content;
  }
  const segments: string[] = splitSegments(content);
  if (mask.keep.length !== segments.length) {
    return content;
  }
  let allKept: boolean = true;
  let i: number = 0;
  while (i < mask.keep.length) {
    if (!mask.keep[i]) {
      allKept = false;
      break;
    }
    i += 1;
  }
  if (allKept) {
    return content;
  }
  let out: string = '';
  let k: number = 0;
  while (k < segments.length) {
    if (mask.keep[k]) {
      out += segments[k];
    }
    k += 1;
  }
  return out;
}

export class TopicGateService {
  private static prefs: preferences.Preferences | undefined = undefined;

  /** 读取净化配置；读失败即返回「未启用」的空配置（fail-open）。 */
  public static async loadConfig(context: common.UIAbilityContext): Promise<TopicGateConfig> {
    const config: TopicGateConfig = {
      enabled: false,
      apiKey: '',
      threshold: DEFAULT_TOPIC_GATE_THRESHOLD,
      endpoint: JevService.DEFAULT_ENDPOINT,
      model: JevService.DEFAULT_MODEL
    };
    try {
      if (TopicGateService.prefs === undefined) {
        TopicGateService.prefs = await preferences.getPreferences(context, { name: PREFS_NAME });
      }
      const prefs: preferences.Preferences = TopicGateService.prefs as preferences.Preferences;

      const enabledVal: preferences.ValueType = await prefs.get(KEY_TOPIC_GATE_ENABLED, false);
      if (typeof enabledVal === 'boolean') {
        config.enabled = enabledVal as boolean;
      }
      const keyVal: preferences.ValueType = await prefs.get(KEY_TOPIC_GATE_API_KEY, '');
      if (typeof keyVal === 'string') {
        config.apiKey = keyVal as string;
      }
      const thresholdVal: preferences.ValueType =
        await prefs.get(KEY_TOPIC_GATE_THRESHOLD, DEFAULT_TOPIC_GATE_THRESHOLD);
      if (typeof thresholdVal === 'number' && thresholdVal >= 0 && thresholdVal <= 1) {
        config.threshold = thresholdVal as number;
      }
      const endpointVal: preferences.ValueType = await prefs.get(KEY_TOPIC_GATE_ENDPOINT, '');
      if (typeof endpointVal === 'string' && (endpointVal as string).trim().length > 0) {
        config.endpoint = (endpointVal as string).trim();
      }
      const modelVal: preferences.ValueType = await prefs.get(KEY_TOPIC_GATE_MODEL, '');
      if (typeof modelVal === 'string' && (modelVal as string).trim().length > 0) {
        config.model = (modelVal as string).trim();
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadConfig failed: %{public}s', String(err));
    }
    return config;
  }

  /**
   * 为一条刚写入历史的助手消息附加掩码。
   * @param topicText 产生该回复的用户消息原文（不是当前会话主题）。
   * @returns 是否真的写入了掩码（调用方据此决定是否落盘）。
   */
  public static async annotate(
    message: ChatMessage,
    topicText: string,
    config: TopicGateConfig
  ): Promise<boolean> {
    if (!config.enabled || config.apiKey.trim().length === 0) {
      return false;
    }
    if (message.role !== 'assistant' || message.topicMask !== undefined) {
      return false;
    }
    const topic: string = topicText.trim();
    if (topic.length === 0 || message.content.trim().length === 0) {
      return false;
    }

    const segments: string[] = splitSegments(message.content);
    const candidateIndexes: number[] = [];
    const candidateTexts: string[] = [];
    let i: number = 0;
    while (i < segments.length) {
      if (segments[i].trim().length > 0) {
        candidateIndexes.push(i);
        candidateTexts.push(segments[i]);
      }
      i += 1;
    }
    // 单段回复没有可删的「非主线内容」，判定纯属浪费调用。
    if (candidateTexts.length < 2) {
      return false;
    }

    const scores: number[] | undefined = await JevService.scoreSegments(
      topic.substring(0, TOPIC_MAX_CHARS),
      candidateTexts,
      config.apiKey,
      config.endpoint,
      config.model
    );
    if (scores === undefined || scores.length !== candidateTexts.length) {
      return false;
    }

    const keep: boolean[] = [];
    let s: number = 0;
    while (s < segments.length) {
      keep.push(true);
      s += 1;
    }
    let dropped: number = 0;
    let c: number = 0;
    while (c < candidateIndexes.length) {
      const onTopic: boolean = scores[c] >= config.threshold;
      keep[candidateIndexes[c]] = onTopic;
      if (!onTopic) {
        dropped += 1;
      }
      c += 1;
    }

    const mask: TopicGateMask = {
      topic: topic.substring(0, TOPIC_STORE_MAX_CHARS),
      keep: keep
    };
    message.topicMask = mask;
    hilog.info(DOMAIN, TAG, 'topic gate masked %{public}d/%{public}d segments at write time',
      dropped, segments.length);
    return true;
  }
}
