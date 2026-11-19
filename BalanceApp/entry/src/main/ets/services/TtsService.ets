/*
 * TtsService.ets
 *
 * DeepSeek 语音合成（朗读）服务 —— POST /v1/tools/tts 整段合成 + 本地播放。
 * 1. 合成：Bearer 鉴权、JSON 体 {text, voice_id, format:'wav'}，响应为音频二进制
 *    （expectDataType=ARRAY_BUFFER），边合成边返回，单次最多 30 分钟音频。
 * 2. 落盘：写到应用 cache 目录再播放，避免把几十 KB 音频常驻内存。
 * 3. 播放：AVPlayer + fdSrc（本地文件描述符）；止于 completed/error 时统一释放并删缓存。
 * 4. 单实例：任何新朗读先停旧播放，避免两路音频叠在一起。
 *
 * 注意：服务端默认 filter_markdown=true，会自行去掉 Markdown 标记，客户端不用清洗；
 *   文本最多 10000 个计费字符（汉字算 2），这里按 UTF-16 长度保守截断。
 *
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，捕获异常转为 Error 类型。
 */

import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'TtsService';
const TTS_URL = 'https://api.deepseek.com/v1/tools/tts';
const CONNECT_TIMEOUT = 15000;
const READ_TIMEOUT = 120000;
/** 服务端单次上限 10000 个计费字符；按 UTF-16 长度截断更保守。 */
const MAX_TEXT_UNITS = 10000;

export interface TtsRequest {
  apiKey: string;
  text: string;
  /** stella（女声，默认）| tide（男声）。 */
  voiceId: string;
}

export interface TtsCallbacks {
  /** 音频已开始播放。 */
  onStart: () => void;
  /** 播放自然结束。 */
  onFinish: () => void;
  /** 合成或播放失败，message 可直接展示。 */
  onError: (message: string) => void;
}

export class TtsService {
  private static player: media.AVPlayer | undefined = undefined;
  /** 当前播放的本地文件与 fd：播放期间必须保持打开，结束统一释放。 */
  private static cachePath: string = '';
  private static cacheFd: number = -1;
  /** 自增会话号：旧播放的迟到回调不得污染新会话（红灯规则：session token 隔离）。 */
  private static session: number = 0;

  /**
   * 合成并播放；失败通过 onError 回调，不向调用方抛异常。
   * Business Rule: 新请求总是先停旧播放并作废旧会话，旧回调据此自动失效。
   */
  public static async speak(context: common.UIAbilityContext, request: TtsRequest,
    callbacks: TtsCallbacks): Promise<void> {
    TtsService.stopPlayback();

    const text: string = request.text.trim();
    if (text.length === 0) {
      callbacks.onError('没有可朗读的内容');
      return;
    }
    if (request.apiKey.trim().length === 0) {
      callbacks.onError('未配置 DeepSeek API Key');
      return;
    }
    const clipped: string = text.length > MAX_TEXT_UNITS ? text.substring(0, MAX_TEXT_UNITS) : text;
    const voice: string = request.voiceId === 'tide' ? 'tide' : 'stella';

    const req: http.HttpRequest = http.createHttp();
    try {
      const body: Record<string, string> = {
        'text': clipped,
        'voice_id': voice,
        'format': 'wav'
      };
      const resp: http.HttpResponse = await req.request(TTS_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${request.apiKey.trim()}`,
          'Accept': 'audio/wav'
        },
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: CONNECT_TIMEOUT,
        readTimeout: READ_TIMEOUT
      });

      if (resp.responseCode !== 200) {
        callbacks.onError(`朗读失败：服务返回 ${resp.responseCode}${TtsService.errorSuffix(resp.result)}`);
        return;
      }
      if (!(resp.result instanceof ArrayBuffer)) {
        callbacks.onError('朗读失败：返回的不是音频数据');
        return;
      }

      const path: string = `${context.cacheDir}/tts_${Date.now()}.wav`;
      const out: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        fs.writeSync(out.fd, resp.result as ArrayBuffer);
      } finally {
        fs.closeSync(out);
      }
      await TtsService.startPlayback(path, callbacks);
    } catch (err) {
      // 合成/落盘/起播任一步失败：清掉可能已写的缓存与半开的播放器，避免泄漏。
      TtsService.stopPlayback();
      hilog.error(DOMAIN, TAG, 'tts request failed: %{public}s', String(err));
      callbacks.onError(`朗读失败：${String(err)}`);
    } finally {
      req.destroy();
    }
  }

  /** 停止当前播放并清理缓存；无播放时是空操作。 */
  public static stopPlayback(): void {
    TtsService.session += 1;
    const player: media.AVPlayer | undefined = TtsService.player;
    TtsService.player = undefined;
    if (player !== undefined) {
      try {
        player.release().catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, 'release failed: %{public}s', String(err));
        });
      } catch (_err) {
      }
    }
    if (TtsService.cacheFd >= 0) {
      try {
        fs.closeSync(TtsService.cacheFd);
      } catch (_err) {
      }
      TtsService.cacheFd = -1;
    }
    if (TtsService.cachePath.length > 0) {
      try {
        fs.unlinkSync(TtsService.cachePath);
      } catch (_err) {
      }
      TtsService.cachePath = '';
    }
  }

  public static isPlaying(): boolean {
    return TtsService.player !== undefined;
  }

  private static async startPlayback(path: string, callbacks: TtsCallbacks): Promise<void> {
    const sessionId: number = TtsService.session + 1;
    TtsService.session = sessionId;

    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    const stat: fs.Stat = fs.statSync(path);
    TtsService.cachePath = path;
    TtsService.cacheFd = file.fd;

    const player: media.AVPlayer = await media.createAVPlayer();
    TtsService.player = player;

    player.on('stateChange', (state: media.AVPlayerState) => {
      // 旧会话的迟到回调（用户已切到别的消息/停止）一律忽略，避免误清新会话状态。
      if (sessionId !== TtsService.session) {
        return;
      }
      if (state === 'initialized') {
        player.prepare().catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'prepare failed: %{public}s', String(err));
        });
      } else if (state === 'prepared') {
        player.play().catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'play failed: %{public}s', String(err));
        });
      } else if (state === 'completed') {
        TtsService.stopPlayback();
        callbacks.onFinish();
      } else if (state === 'error') {
        TtsService.stopPlayback();
        callbacks.onError('播放失败');
      }
    });

    const src: media.AVFileDescriptor = { fd: file.fd, offset: 0, length: stat.size };
    player.fdSrc = src;
    callbacks.onStart();
  }

  /** 非 200 时尽量把服务端错误文本带出来（结果此时是二进制，需自行解码）。 */
  private static errorSuffix(result: ESObject): string {
    if (!(result instanceof ArrayBuffer)) {
      return '';
    }
    try {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      const text: string = decoder.decodeWithStream(new Uint8Array(result as ArrayBuffer), { stream: false });
      if (text.length === 0) {
        return '';
      }
      return `（${text.length > 200 ? text.substring(0, 200) : text}）`;
    } catch (_err) {
      return '';
    }
  }
}
