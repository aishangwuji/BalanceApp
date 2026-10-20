/*
 * ChatService.ets
 *
 * 流式与非流式对话引擎 —— 采用系统 @kit.NetworkKit 实现 OpenAI 兼容格式通信。
 * 对齐 Kimi《流式输出》《多轮对话（messages 记忆）》两节规范，按本项目实际裁剪落地：
 * 1. 流式：requestInStream + SSE 逐块解析（content 追加、reasoning_content 追加折叠、
 *    [DONE] 为完成判据、不以 finish_reason 判完）；role 仅首块、usage 终块 choices 为空
 *    均已容错。tool_calls 本项目未声明 tools，故有意忽略其增量（n 恒为 1，不下发 n）。
 * 2. 记忆：/chat/completions 无状态，每轮回传 system + 历史 user/assistant（按时间序）；
 *    system 常驻、历史截断取新（条数+字符双预算，见 buildApiMessages）。
 * 3. 中断：返回取消函数 destroy 旧连接（用户点停止即丢弃后续块）。
 * 4. token 用量：ChatUsage 已下线，故不下发 stream_options.include_usage，
 *    终块 usage 到达即忽略，不做 UI 统计。
 *
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，捕获异常转为 Error 类型。
 */

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChatMessage } from '../models/ChatModels';
import { findProvider, ProviderDefinition } from './ProviderRegistry';
import { applyTopicMask } from './TopicGateService';

const DOMAIN = 0x0000;
const TAG = 'ChatService';
const CONNECT_TIMEOUT = 15000;
const READ_TIMEOUT = 90000;
/**
 * 历史截断预算（对齐 Kimi make_messages 取新 20 条 + 本项目群聊设计 6000 字预算）。
 * Business Rule: system 常驻不计入预算；历史超限从旧到新丢弃，保证请求稳定。
 */
const MAX_HISTORY_MESSAGES = 20;
const MAX_HISTORY_CHARS = 12000;

export interface StreamCallbacks {
  onToken: (token: string, reasoningChunk?: string) => void;
  onComplete: () => void;
  onError: (error: string) => void;
}

export interface ChatRequestOptions {
  providerId: string;
  apiKey: string;
  model: string;
  temperature?: number;
  messages: ChatMessage[];
  systemPrompt?: string;
  /** 深度思考开关；仅当供应商 supportsThinking 时生效。 */
  enableThinking?: boolean;
  /** 思考强度 low/high/max；缺省 high。 */
  reasoningEffort?: string;
}

export class ChatService {
  /**
   * 流式对话调用，返回用于中断取消的控制器对象
   */
  public static streamChat(options: ChatRequestOptions, callbacks: StreamCallbacks): () => void {
    const def: ProviderDefinition | undefined = findProvider(options.providerId);
    if (def === undefined) {
      callbacks.onError(`未知的服务商: ${options.providerId}`);
      return () => {};
    }

    if (options.apiKey.trim().length === 0) {
      callbacks.onError('未配置 API Key，请先配置');
      return () => {};
    }

    const endpointUrl: string = `${def.baseUrl}/v1/chat/completions`;
    const req: http.HttpRequest = http.createHttp();
    let isAborted: boolean = false;
    let textBuffer: string = '';
    let sawDone: boolean = false;
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });

    // 多轮拼接：/chat/completions 无状态，须每轮回传 system + 历史（见 buildApiMessages）。
    const formattedMessages: Record<string, string>[] =
      ChatService.buildApiMessages(options.messages, options.systemPrompt);

    const payloadObj: Record<string, ESObject> = ChatService.buildPayload(options, def, formattedMessages, true);
    const bodyStr: string = JSON.stringify(payloadObj);

    // 绑定流式数据接收
    req.on('dataReceive', (chunkBuffer: ArrayBuffer) => {
      if (isAborted) {
        return;
      }
      try {
        const u8: Uint8Array = new Uint8Array(chunkBuffer);
        const chunkText: string = decoder.decodeWithStream(u8, { stream: true });
        textBuffer += chunkText;

        const lines: string[] = textBuffer.split('\n');
        // 最后一个元素可能是未截断完整的，留在 buffer 里
        const lastLine: string | undefined = lines.pop();
        textBuffer = lastLine !== undefined ? lastLine : '';

        let lineIdx: number = 0;
        while (lineIdx < lines.length) {
          const rawLine: string = lines[lineIdx].trim();
          lineIdx += 1;
          if (!rawLine.startsWith('data:')) {
            continue;
          }
          const dataStr: string = rawLine.substring(5).trim();
          // 完成判据只认 data:[DONE]（不对 finish_reason 做完成判断；中断走 err 回调）。
          if (dataStr === '[DONE]') {
            sawDone = true;
            continue;
          }

          try {
            const parsedChunk: ESObject = JSON.parse(dataStr) as ESObject;
            if (parsedChunk !== null && typeof parsedChunk === 'object') {
              const rootRec: Record<string, ESObject> = parsedChunk as Record<string, ESObject>;

              // 终块 usage 形如 {choices:[], usage:{...}}：choices 为空即跳过，
              // 本项目 token 统计已下线，不读取 usage。
              // 解析 delta content / reasoning_content（均为追加式增量，不可覆盖）；
              // role 仅首块出现，此处忽略；delta.tool_calls 本项目无 tools，有意忽略。
              const choices: ESObject = rootRec['choices'];
              if (Array.isArray(choices) && choices.length > 0) {
                const choiceItem: ESObject = choices[0];
                if (choiceItem !== null && typeof choiceItem === 'object') {
                  const choiceRec: Record<string, ESObject> = choiceItem as Record<string, ESObject>;
                  const delta: ESObject = choiceRec['delta'];
                  if (delta !== null && typeof delta === 'object') {
                    const deltaRec: Record<string, ESObject> = delta as Record<string, ESObject>;
                    const contentStr: string = typeof deltaRec['content'] === 'string' ? deltaRec['content'] as string : '';
                    const reasoningStr: string = typeof deltaRec['reasoning_content'] === 'string' ? deltaRec['reasoning_content'] as string : '';

                    if (contentStr.length > 0 || reasoningStr.length > 0) {
                      callbacks.onToken(contentStr, reasoningStr.length > 0 ? reasoningStr : undefined);
                    }
                  }
                }
              }
            }
          } catch (_parseErr) {
            // 忽略单行非合法 JSON 的心跳片段
          }
        }
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'SSE decode error: %{public}s', String(err));
      }
    });

    req.on('dataEnd', () => {
      if (!isAborted) {
        if (!sawDone) {
          // 未收到 [DONE] 即关流：按不完整对待，仅打日志，仍以已收 token 落库（调用方已做 keep-partial）。
          hilog.warn(DOMAIN, TAG, 'Stream ended without [DONE], keep partial content');
        }
        callbacks.onComplete();
      }
      try {
        req.destroy();
      } catch (_e) {
      }
    });

    // 发起 requestInStream 请求
    req.requestInStream(endpointUrl, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${options.apiKey.trim()}`,
        'api-key': options.apiKey.trim(),
        'Accept': 'text/event-stream'
      },
      extraData: bodyStr,
      connectTimeout: CONNECT_TIMEOUT,
      readTimeout: READ_TIMEOUT
    }, (err: BusinessErrorLike | null | undefined) => {
      if (err) {
        if (!isAborted) {
          hilog.error(DOMAIN, TAG, 'Stream request failed: %{public}s', String(err));
          callbacks.onError(`网络请求失败: ${String(err)}`);
        }
        try {
          req.destroy();
        } catch (_e) {
        }
      }
    });

    // 返回取消打断函数
    return () => {
      isAborted = true;
      try {
        req.destroy();
      } catch (_e) {
      }
    };
  }

  /**
   * 非流式对话调用
   */
  public static async nonStreamChat(options: ChatRequestOptions): Promise<string> {
    const def: ProviderDefinition | undefined = findProvider(options.providerId);
    if (def === undefined) {
      throw new Error(`未知的服务商: ${options.providerId}`);
    }

    const endpointUrl: string = `${def.baseUrl}/v1/chat/completions`;
    const req: http.HttpRequest = http.createHttp();

    try {
      const formattedMessages: Record<string, string>[] =
        ChatService.buildApiMessages(options.messages, options.systemPrompt);

      const payloadObj: Record<string, ESObject> = ChatService.buildPayload(options, def, formattedMessages, false);

      const resp: http.HttpResponse = await req.request(endpointUrl, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${options.apiKey.trim()}`,
          'api-key': options.apiKey.trim(),
          'Accept': 'application/json'
        },
        extraData: JSON.stringify(payloadObj),
        connectTimeout: CONNECT_TIMEOUT,
        readTimeout: READ_TIMEOUT
      });

      if (resp.responseCode !== 200) {
        throw new Error(`服务商返回状态码 ${resp.responseCode}: ${String(resp.result)}`);
      }

      let parsed: ESObject;
      if (typeof resp.result === 'string') {
        parsed = JSON.parse(resp.result as string) as ESObject;
      } else {
        parsed = resp.result as ESObject;
      }

      const rootRec: Record<string, ESObject> = parsed as Record<string, ESObject>;
      const choices: ESObject = rootRec['choices'];
      if (!Array.isArray(choices) || choices.length === 0) {
        throw new Error('返回结果未包含任何文本回复');
      }

      const choiceRec: Record<string, ESObject> = choices[0] as Record<string, ESObject>;
      const msg: ESObject = choiceRec['message'];
      if (msg === null || typeof msg !== 'object') {
        throw new Error('回复消息结构非法');
      }

      const msgRec: Record<string, ESObject> = msg as Record<string, ESObject>;
      return typeof msgRec['content'] === 'string' ? msgRec['content'] as string : '';
    } finally {
      req.destroy();
    }
  }

  /**
   * 组装 API 用 messages：system 常驻首位 + 历史按时间序取新截断。
   * Business Rule: 对齐 Kimi make_messages（system 必带、超 n 仅保留最新 n 条），
   *   再叠加字符预算从旧到新丢弃；调用方传分支路径即可，此处统一收口流式/非流式。
   * Reason: 长会话无截断会撑爆上下文窗口导致 400/变慢；多会话隔离与持久化由
   *   ChatStorageService 按 session 存全量承担，此处只裁剪本次请求。
   */
  private static buildApiMessages(messages: ChatMessage[], systemPrompt?: string): Record<string, string>[] {
    const out: Record<string, string>[] = [];
    if (systemPrompt !== undefined && systemPrompt.trim().length > 0) {
      const sysMsg: Record<string, string> = {
        'role': 'system',
        'content': systemPrompt.trim()
      };
      out.push(sysMsg);
    }
    // 先过滤 user/assistant 并拼出待选（含 Preserved Thinking 回传）。
    const candidates: Record<string, string>[] = [];
    let i: number = 0;
    while (i < messages.length) {
      const m: ChatMessage = messages[i];
      i += 1;
      if (m.role !== 'user' && m.role !== 'assistant') {
        continue;
      }
      // 写时净化：助手历史按持久化掩码投影（原文与界面不变，仅影响本次请求）。
      // 掩码缺失/长度不符时 applyTopicMask 原样返回，故旧数据无需迁移。
      const replayContent: string = m.role === 'assistant' ? applyTopicMask(m.content, m.topicMask) : m.content;
      if (replayContent.length === 0 && !(m.reasoningContent && m.reasoningContent.length > 0)) {
        continue;
      }
      const item: Record<string, string> = {
        'role': m.role,
        'content': replayContent
      };
      // 保留式思考（Preserved Thinking）：Kimi/小米 MiMo 回传 reasoning_content 保多轮思维连贯；
      // DeepSeek 等无 tools 场景传了也被忽略，统一回传无害。
      if (m.role === 'assistant' && m.reasoningContent && m.reasoningContent.length > 0) {
        item['reasoning_content'] = m.reasoningContent;
      }
      candidates.push(item);
    }
    // 条数截断：仅保留最新 MAX_HISTORY_MESSAGES 条。
    let start: number = 0;
    if (candidates.length > MAX_HISTORY_MESSAGES) {
      start = candidates.length - MAX_HISTORY_MESSAGES;
    }
    // 字符截断：从新到旧累加，超预算即丢弃更旧的。
    const kept: Record<string, string>[] = [];
    let used: number = 0;
    let j: number = candidates.length - 1;
    while (j >= start) {
      const c: Record<string, string> = candidates[j];
      let rcLen: number = 0;
      if (typeof c['reasoning_content'] === 'string') {
        rcLen = (c['reasoning_content'] as string).length;
      }
      const total: number = c['content'].length + c['role'].length + 8 + rcLen;
      if (kept.length > 0 && used + total > MAX_HISTORY_CHARS) {
        break;
      }
      kept.unshift(c);
      used += total;
      j -= 1;
    }
    let k: number = 0;
    while (k < kept.length) {
      out.push(kept[k]);
      k += 1;
    }
    return out;
  }

  /**
   * 针对不同供应商（DeepSeek / 小米 MiMo / Kimi）规范构建差异化请求体
   */
  private static buildPayload(
    options: ChatRequestOptions,
    def: ProviderDefinition,
    formattedMessages: Record<string, string>[],
    isStream: boolean
  ): Record<string, ESObject> {
    const payloadObj: Record<string, ESObject> = {
      'model': options.model,
      'messages': formattedMessages as ESObject,
      'stream': isStream
      // 有意不下发：n（Kimi k3/k2.6/k2.7 固定为 1，传>1 直接 400）、
      // stream_options.include_usage（token 统计已下线）、tools（本项目无工具调用）。
    };

    const thinkingOn: boolean = options.enableThinking === true && def.supportsThinking === true;
    const modelLower: string = options.model.toLowerCase();

    // 1. Kimi (Moonshot) 模型分支
    if (options.providerId === 'kimi') {
      if (modelLower.startsWith('kimi-k3')) {
        // K3 始终推理，不传 thinking 参数，支持顶层 reasoning_effort ("low" / "high" / "max"，默认 "max")
        payloadObj['reasoning_effort'] = options.reasoningEffort !== undefined ? options.reasoningEffort : 'max';
      } else if (modelLower.includes('kimi-k2.7')) {
        // k2.7-code 始终思考，不传 thinking 参数，不传 temperature
      } else if (modelLower.startsWith('kimi-k2.6')) {
        // k2.6 通过 thinking.type 控制开关，不传 temperature
        const thinkingCfg: Record<string, string> = {
          'type': thinkingOn ? 'enabled' : 'disabled'
        };
        payloadObj['thinking'] = thinkingCfg as ESObject;
      } else {
        // 普通 moonshot 模型
        payloadObj['temperature'] = options.temperature !== undefined ? options.temperature : 0.7;
      }
      return payloadObj;
    }

    // 2. 小米 MiMo 分支：支持 thinking.type "enabled"/"disabled"，思考模式下不传 temperature 与 reasoning_effort
    if (options.providerId === 'mimo') {
      const thinkingCfg: Record<string, string> = {
        'type': thinkingOn ? 'enabled' : 'disabled'
      };
      payloadObj['thinking'] = thinkingCfg as ESObject;
      if (!thinkingOn) {
        payloadObj['temperature'] = options.temperature !== undefined ? options.temperature : 0.7;
      }
      return payloadObj;
    }

    // 3. DeepSeek 及其他通用服务商分支
    if (thinkingOn) {
      const thinkingCfg: Record<string, string> = { 'type': 'enabled' };
      payloadObj['thinking'] = thinkingCfg as ESObject;
      payloadObj['reasoning_effort'] = options.reasoningEffort !== undefined ? options.reasoningEffort : 'high';
    } else {
      if (def.supportsThinking === true) {
        const thinkingOff: Record<string, string> = { 'type': 'disabled' };
        payloadObj['thinking'] = thinkingOff as ESObject;
      }
      payloadObj['temperature'] = options.temperature !== undefined ? options.temperature : 0.7;
    }

    return payloadObj;
  }
}

interface BusinessErrorLike {
  code?: number;
  message?: string;
}
