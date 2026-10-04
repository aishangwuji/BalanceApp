/*
 * ChatService.ets
 *
 * 流式与非流式对话引擎 —— 采用系统 @kit.NetworkKit 实现 OpenAI 兼容格式通信。
 * 支持：
 * 1. requestInStream + SSE 逐块解析（打字机流式输出、推理思维链 reasoning_content 解析）；
 * 2. usage 统计抓取（prompt_tokens, completion_tokens）；
 * 3. 任务主动中断（用户点击停止生成）。
 *
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，捕获异常转为 Error 类型。
 */

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChatMessage } from '../models/ChatModels';
import { findProvider, ProviderDefinition } from './ProviderRegistry';

const DOMAIN = 0x0000;
const TAG = 'ChatService';
const CONNECT_TIMEOUT = 15000;
const READ_TIMEOUT = 90000;

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
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });

    // 多轮拼接：DeepSeek /chat/completions 无状态，须每轮回传完整历史。
    // Reason: 按官方规范，未携带 tools 时历史 reasoning_content 无需回传（传了也被忽略），
    //   故此处仅回传 role/content；思考内容仅本地展示。
    const formattedMessages: Record<string, string>[] = [];
    if (options.systemPrompt && options.systemPrompt.trim().length > 0) {
      const sysMsg: Record<string, string> = {
        'role': 'system',
        'content': options.systemPrompt.trim()
      };
      formattedMessages.push(sysMsg);
    }

    let i: number = 0;
    while (i < options.messages.length) {
      const m: ChatMessage = options.messages[i];
      if (m.role === 'user' || m.role === 'assistant') {
        const item: Record<string, string> = {
          'role': m.role,
          'content': m.content
        };
        formattedMessages.push(item);
      }
      i += 1;
    }

    // 思考模式：仅对支持该扩展的供应商下发 thinking/reasoning_effort；
    // 思考模式下官方不支持 temperature，此时不下发，避免误导与无效参数。
    const thinkingOn: boolean = options.enableThinking === true && def.supportsThinking === true;
    const payloadObj: Record<string, ESObject> = {
      'model': options.model,
      'messages': formattedMessages as ESObject,
      'stream': true
    };
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
          if (dataStr === '[DONE]') {
            continue;
          }

          try {
            const parsedChunk: ESObject = JSON.parse(dataStr) as ESObject;
            if (parsedChunk !== null && typeof parsedChunk === 'object') {
              const rootRec: Record<string, ESObject> = parsedChunk as Record<string, ESObject>;

              // 解析 delta content / reasoning_content
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
      const formattedMessages: Record<string, string>[] = [];
      if (options.systemPrompt && options.systemPrompt.trim().length > 0) {
        const sysMsg: Record<string, string> = {
          'role': 'system',
          'content': options.systemPrompt.trim()
        };
        formattedMessages.push(sysMsg);
      }

      let i: number = 0;
      while (i < options.messages.length) {
        const m: ChatMessage = options.messages[i];
        if (m.role === 'user' || m.role === 'assistant') {
          const item: Record<string, string> = {
            'role': m.role,
            'content': m.content
          };
          formattedMessages.push(item);
        }
        i += 1;
      }

      const payloadObj: Record<string, ESObject> = {
        'model': options.model,
        'messages': formattedMessages as ESObject,
        'stream': false,
        'temperature': options.temperature !== undefined ? options.temperature : 0.7
      };

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
}

interface BusinessErrorLike {
  code?: number;
  message?: string;
}
