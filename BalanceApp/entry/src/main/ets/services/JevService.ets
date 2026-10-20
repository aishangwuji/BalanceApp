/*
 * JevService.ets
 *
 * TypeSafe System One 判定客户端 —— 只为上下文净化服务，不参与生成。
 * 一次请求合并本消息的所有分段：每段一个 Noul 问句，返回该段的「切题概率」。
 * 对齐 nanobot 的 topic gate 请求形状（state + questions），
 * 供应商端点与模型可被偏好覆盖，未配置时整体不启用。
 *
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，捕获异常转为 Error 类型。
 */

import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'JevService';
const CONNECT_TIMEOUT = 10000;
const READ_TIMEOUT = 20000;

export interface SystemOneChannel {
  id: string;
  label: string;
  endpoint: string;
  model: string;
}

/**
 * System One 仅支持两个渠道，端点与模型按官方文档固定：
 * - TypeSafe 官方：POST https://api.typesafe.ai/v1/systemone，model `jev-latest`
 * - OpenRouter：POST https://openrouter.ai/api/v1/systemone，model `~typesafe/jev-latest`
 *   （OpenRouter 的 System One 兼容面，Key 为 OpenRouter Key，与官方 Key 不通用）
 */
export const SYSTEM_ONE_CHANNELS: SystemOneChannel[] = [
  {
    id: 'typesafe',
    label: 'Jev 官方',
    endpoint: 'https://api.typesafe.ai/v1/systemone',
    model: 'jev-latest'
  },
  {
    id: 'openrouter',
    label: 'OpenRouter',
    endpoint: 'https://openrouter.ai/api/v1/systemone',
    model: '~typesafe/jev-latest'
  }
];

export function findSystemOneChannel(id: string): SystemOneChannel | undefined {
  let i: number = 0;
  while (i < SYSTEM_ONE_CHANNELS.length) {
    if (SYSTEM_ONE_CHANNELS[i].id === id) {
      return SYSTEM_ONE_CHANNELS[i];
    }
    i += 1;
  }
  return undefined;
}

export class JevService {
  /** 默认 System One 端点与模型（Jev 官方直连）。 */
  public static readonly DEFAULT_ENDPOINT: string = 'https://api.typesafe.ai/v1/systemone';
  public static readonly DEFAULT_MODEL: string = 'jev-latest';

  /**
   * 为每个分段打分：返回与 segments 等长的切题概率数组。
   * Business Rule: 任何失败（网络/非 200/结构非法/条数不符）都返回 undefined，
   *   由调用方 fail-open 保留全部内容——净化绝不能因判定失败而丢正文。
   */
  public static async scoreSegments(
    topic: string,
    segments: string[],
    apiKey: string,
    endpoint: string,
    model: string
  ): Promise<number[] | undefined> {
    if (segments.length === 0 || apiKey.trim().length === 0) {
      return undefined;
    }
    const req: http.HttpRequest = http.createHttp();
    try {
      const payload: Record<string, ESObject> = JevService.buildPayload(topic, segments, model);
      const resp: http.HttpResponse = await req.request(endpoint, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey.trim()}`,
          'Accept': 'application/json'
        },
        extraData: JSON.stringify(payload),
        connectTimeout: CONNECT_TIMEOUT,
        readTimeout: READ_TIMEOUT
      });
      if (resp.responseCode !== 200) {
        hilog.warn(DOMAIN, TAG, 'System One returned %{public}d; keeping every segment', resp.responseCode);
        return undefined;
      }
      let parsed: ESObject;
      if (typeof resp.result === 'string') {
        parsed = JSON.parse(resp.result as string) as ESObject;
      } else {
        parsed = resp.result as ESObject;
      }
      return JevService.parseScores(parsed, segments.length);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'System One call failed (%{public}s); keeping every segment', String(err));
      return undefined;
    } finally {
      req.destroy();
    }
  }

  private static buildPayload(
    topic: string,
    segments: string[],
    model: string
  ): Record<string, ESObject> {
    const stateSegments: Record<string, ESObject> = {};
    const questions: Record<string, ESObject> = {};
    let i: number = 0;
    while (i < segments.length) {
      const key: string = `segment_${i}`;
      stateSegments[key] = segments[i];
      const question: Record<string, string> = {
        'type': 'noul',
        'instructions': `Does \`segments.${key}\` stay on the conversation topic \`topic\`? Judge only relevance to the topic.`
      };
      questions[key] = question as ESObject;
      i += 1;
    }
    const state: Record<string, ESObject> = {
      'topic': topic,
      'segments': stateSegments as ESObject
    };
    return {
      'model': model,
      'state': state as ESObject,
      'questions': questions as ESObject
    };
  }

  /** 解析 answers.<key>.noul；结构不合法返回 undefined（调用方 fail-open）。 */
  private static parseScores(parsed: ESObject, expected: number): number[] | undefined {
    if (parsed === null || typeof parsed !== 'object') {
      return undefined;
    }
    const rootRec: Record<string, ESObject> = parsed as Record<string, ESObject>;
    const answers: ESObject = rootRec['answers'];
    if (answers === null || typeof answers !== 'object' || Array.isArray(answers)) {
      return undefined;
    }
    const answersRec: Record<string, ESObject> = answers as Record<string, ESObject>;
    const out: number[] = [];
    let i: number = 0;
    while (i < expected) {
      const answer: ESObject = answersRec[`segment_${i}`];
      let score: number = 0;
      if (answer !== null && typeof answer === 'object') {
        const answerRec: Record<string, ESObject> = answer as Record<string, ESObject>;
        const scoreVal: ESObject = answerRec['noul'];
        if (typeof scoreVal === 'number') {
          score = scoreVal as number;
        }
      }
      out.push(score);
      i += 1;
    }
    return out;
  }
}
