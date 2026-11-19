/*
 * TtsService.ets
 *
 * DeepSeek 语音合成（朗读）服务 —— POST /v1/tools/tts 整段合成 + 本地播放。
 * 1. 合成：Bearer 鉴权、JSON 体 {text, voice_id, format:'wav'}，响应为音频二进制
 *    （expectDataType=ARRAY_BUFFER），边合成边返回，单次最多 30 分钟音频。
 * 2. 落盘：写到应用 cache 目录的 tts_cache/ 下再播放，避免把几十 KB 音频常驻内存。
 * 3. 缓存：以「音色 + 文本」的哈希命名，同一条回答只合成一次；停止播放不删缓存，
 *    再次点朗读直接复用本地音频（不请求、不计费）；超过文件数/总字节上限按 mtime 淘汰。
 * 4. 播放：AVPlayer + fdSrc（本地文件描述符）；止于 completed/error 时统一释放播放器与句柄。
 * 5. 单实例：任何新朗读先停旧播放，避免两路音频叠在一起。
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
/** 朗读音频本地缓存：同一条回答 + 同一音色只合成一次，重播直接读缓存（不请求、不计费）。 */
const CACHE_DIR_NAME = 'tts_cache';
/** 缓存水位：超过任一上限就按修改时间从旧到新淘汰（WAV 未压缩，单条约 48KB/秒）。 */
const MAX_CACHE_FILES = 16;
const MAX_CACHE_BYTES = 40 * 1024 * 1024;
/** WAV 头 44 字节：小于它的文件视为写坏的残片。 */
const MIN_WAV_BYTES = 44;

/** 缓存目录内的音频条目（淘汰时按 mtime 排序）。 */
interface TtsCacheFile {
  path: string;
  size: number;
  mtime: number;
}

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
  /** 自增会话号：旧播放/旧请求的迟到回调不得污染新会话（红灯规则：session token 隔离）。 */
  private static session: number = 0;
  /** 正在合成的缓存键：同一段音频重复点击直接忽略，避免并发重复请求与重复计费。 */
  private static pendingKey: string = '';

  /**
   * 合成并播放；失败通过 onError 回调，不向调用方抛异常。
   * Business Rule:
   *   1. 先按「音色 + 文本」查本地缓存，命中就直接播放——停止后再点不会重新请求、不重复计费；
   *   2. 未命中才请求服务端，先写 .tmp 再 rename，保证缓存里只可能是完整文件；
   *   3. 新请求总是先停旧播放并作废旧会话，旧回调据此自动失效。
   */
  public static async speak(context: common.UIAbilityContext, request: TtsRequest,
    callbacks: TtsCallbacks): Promise<void> {
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
    const dir: string = TtsService.ensureCacheDir(context);
    const cachePath: string = `${dir}/${TtsService.cacheKey(clipped, voice)}.wav`;

    // 同一段正在合成：直接忽略这次点击，避免并发重复请求（会重复计费）。
    if (TtsService.pendingKey === cachePath) {
      return;
    }

    TtsService.stopPlayback();
    // 本次调用的会话号：若期间用户又点了别的朗读，旧请求回来时据此放弃播放。
    const callId: number = TtsService.session;

    // 命中缓存：直接播放，不发请求、不产生费用。
    if (TtsService.isUsable(cachePath)) {
      await TtsService.startPlayback(cachePath, callbacks);
      return;
    }

    TtsService.pendingKey = cachePath;
    let tmpPath: string = '';
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

      tmpPath = `${cachePath}.${Date.now()}.tmp`;
      const out: fs.File = fs.openSync(tmpPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(out.fd, resp.result as ArrayBuffer);
      } finally {
        fs.closeSync(out);
      }
      // 完整落盘后再改名：避免中途被杀留下半截文件，下次误当缓存命中。
      fs.renameSync(tmpPath, cachePath);
      tmpPath = '';
      TtsService.pruneCache(dir, cachePath);
      // 期间用户可能已点了别的朗读：本次结果不再抢占播放器。
      if (callId !== TtsService.session) {
        return;
      }
      await TtsService.startPlayback(cachePath, callbacks);
    } catch (err) {
      if (tmpPath.length > 0) {
        try {
          fs.unlinkSync(tmpPath);
        } catch (_cleanupErr) {
        }
      }
      // 合成/落盘/起播任一步失败：停掉可能已起的播放器，避免泄漏。
      TtsService.stopPlayback();
      hilog.error(DOMAIN, TAG, 'tts request failed: %{public}s', String(err));
      callbacks.onError(`朗读失败：${String(err)}`);
    } finally {
      if (TtsService.pendingKey === cachePath) {
        TtsService.pendingKey = '';
      }
      req.destroy();
    }
  }

  /** 停止当前播放并释放文件句柄；缓存音频保留，重播直接复用。 */
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
    // 注意：这里**不删**缓存文件——停止后再次朗读应命中缓存，直接复用同一段音频。
    TtsService.cachePath = '';
  }

  public static isPlaying(): boolean {
    return TtsService.player !== undefined;
  }

  /** 确保缓存目录存在；建不出来时退化为 cacheDir 根目录（功能优先，缓存只影响省流量）。 */
  private static ensureCacheDir(context: common.UIAbilityContext): string {
    const dir: string = `${context.cacheDir}/${CACHE_DIR_NAME}`;
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
      return dir;
    } catch (_err) {
      return context.cacheDir;
    }
  }

  /** 缓存文件是否可用：存在且大于 WAV 头，残片一律当未命中重新合成。 */
  private static isUsable(path: string): boolean {
    try {
      if (!fs.accessSync(path)) {
        return false;
      }
      const stat: fs.Stat = fs.statSync(path);
      return stat.size > MIN_WAV_BYTES;
    } catch (_err) {
      return false;
    }
  }

  /**
   * 缓存键：FNV-1a 32 位哈希（音色 + 文本），带长度前缀降低碰撞概率。
   * Business Rule: 换音色或文本变化即换 key，不会把旧音色的音频播给新设置。
   */
  private static cacheKey(text: string, voice: string): string {
    const seed: string = `${voice}|${text}`;
    let hash: number = 0x811c9dc5;
    let i: number = 0;
    while (i < seed.length) {
      hash ^= seed.charCodeAt(i);
      hash = Math.imul(hash, 0x01000193) >>> 0;
      i += 1;
    }
    return `${voice}_${seed.length}_${hash.toString(16)}`;
  }

  /** 缓存水位控制：超过文件数或总字节上限时，按修改时间从旧到新删除（保留刚写的这条）。 */
  private static pruneCache(dir: string, keepPath: string): void {
    try {
      const names: string[] = fs.listFileSync(dir);
      const files: TtsCacheFile[] = [];
      let total: number = 0;
      let i: number = 0;
      while (i < names.length) {
        const name: string = names[i];
        i += 1;
        if (!name.endsWith('.wav')) {
          continue;
        }
        const full: string = `${dir}/${name}`;
        try {
          const stat: fs.Stat = fs.statSync(full);
          const item: TtsCacheFile = { path: full, size: stat.size, mtime: stat.mtime };
          files.push(item);
          total += stat.size;
        } catch (_statErr) {
        }
      }
      files.sort((a: TtsCacheFile, b: TtsCacheFile) => a.mtime - b.mtime);
      let count: number = files.length;
      let idx: number = 0;
      while (idx < files.length) {
        if (count <= MAX_CACHE_FILES && total <= MAX_CACHE_BYTES) {
          break;
        }
        const item: TtsCacheFile = files[idx];
        idx += 1;
        if (item.path === keepPath) {
          continue;
        }
        try {
          fs.unlinkSync(item.path);
          total -= item.size;
          count -= 1;
        } catch (_unlinkErr) {
        }
      }
    } catch (_err) {
      // 淘汰失败不影响播放。
    }
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
