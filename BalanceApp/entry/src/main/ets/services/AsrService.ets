/*
 * AsrService.ets
 *
 * DeepSeek 语音识别（POST /v1/tools/asr）：一次上传整段音频，返回完整转写文本。
 * 1. 只支持 16 位 PCM WAV 或 Ogg Opus，最大 8 MiB、最长 120 秒（由 VoiceRecorder 保证）；
 * 2. multipart 只带一个 file 字段；语种由服务端自动识别，没有语种参数；
 * 3. 转写成功后删除本地临时 WAV（录音只在内存/缓存里短暂存在）。
 *
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，捕获异常转为 Error 类型。
 */

import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'AsrService';
const ASR_URL = 'https://api.deepseek.com/v1/tools/asr';
const CONNECT_TIMEOUT = 30000;
const READ_TIMEOUT = 180000;
const MAX_BYTES = 8 * 1024 * 1024;

export class AsrService {
  /**
   * 转写一段 WAV；返回文本（可能为空），失败抛 Error。
   * Business Rule: 无论成败都删除传入的临时音频，避免缓存目录堆积录音。
   */
  public static async transcribe(context: common.UIAbilityContext, wavPath: string,
    apiKey: string): Promise<string> {
    if (apiKey.trim().length === 0) {
      throw new Error('未配置 DeepSeek API Key');
    }
    const req: http.HttpRequest = http.createHttp();
    try {
      const stat: fs.Stat = fs.statSync(wavPath);
      if (stat.size <= 44) {
        throw new Error('没有录到声音');
      }
      if (stat.size > MAX_BYTES) {
        throw new Error('录音超过 8MB，请缩短时长');
      }
      const form: http.MultiFormData[] = [];
      const filePart: http.MultiFormData = {
        name: 'file',
        contentType: 'audio/wav',
        remoteFileName: 'speech.wav',
        filePath: wavPath
      };
      form.push(filePart);

      const resp: http.HttpResponse = await req.request(ASR_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${apiKey.trim()}`,
          'Accept': 'application/json'
        },
        multiFormDataList: form,
        connectTimeout: CONNECT_TIMEOUT,
        readTimeout: READ_TIMEOUT
      });

      if (resp.responseCode !== 200) {
        throw new Error(AsrService.errorText(resp.responseCode, resp.result));
      }
      const body: ESObject = typeof resp.result === 'string' ?
        JSON.parse(resp.result as string) as ESObject : resp.result as ESObject;
      if (body === null || typeof body !== 'object') {
        throw new Error('识别结果格式异常');
      }
      const rec: Record<string, ESObject> = body as Record<string, ESObject>;
      const textVal: ESObject = rec['text'];
      if (typeof textVal !== 'string') {
        throw new Error('识别结果缺少文本');
      }
      return (textVal as string).trim();
    } catch (err) {
      const reason: string = err instanceof Error ? err.message : String(err);
      hilog.error(DOMAIN, TAG, 'asr failed: %{public}s', reason);
      throw new Error(reason);
    } finally {
      req.destroy();
      try {
        fs.unlinkSync(wavPath);
      } catch (_unlinkErr) {
      }
    }
  }

  private static errorText(code: number, result: ESObject): string {
    if (code === 400) {
      return '音频格式不支持（需 16 位 PCM WAV 或 Ogg Opus）';
    }
    if (code === 408) {
      return '上传超时，请重试';
    }
    if (code === 413) {
      return '录音文件过大';
    }
    if (code === 429) {
      return '并发请求过多，请稍后重试';
    }
    if (code === 503) {
      return '服务繁忙，请稍后重试';
    }
    if (code === 504) {
      return '识别超时，请重试';
    }
    let detail: string = '';
    if (typeof result === 'string') {
      const text: string = result as string;
      detail = text.length > 160 ? text.substring(0, 160) : text;
    }
    return `识别失败：服务返回 ${code}${detail.length > 0 ? '（' + detail + '）' : ''}`;
  }
}
