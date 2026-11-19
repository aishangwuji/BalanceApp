/*
 * ImageGenService.ets
 *
 * 百智云生图（OpenAPI v1）：文生图任务创建 + 任务轮询 + 重试。
 * 1. 异步任务模型：create 立刻返回 task_id，图片由后台 worker 生成，需轮询 /tasks/{id}；
 * 2. 结果 URL 会过期（image_expires_at 约 1 天），因此拿到后应尽快展示，并在消息里持久化 URL；
 * 3. Key 只存本机 Preferences（key_baizhi），与资产监控的 key_<providerId> 同库不同键；
 * 4. 失败语义：HTTP 非 200 或 code !== 'ok' 抛 Error（带可展示原因），由调用方提示。
 *
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，捕获异常转为 Error 类型。
 */

import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'ImageGenService';
const BASE_URL = 'https://image-generate.app.baizhi.cloud/openapi/v1';
const CONNECT_TIMEOUT = 15000;
const READ_TIMEOUT = 30000;

/** 轮询间隔与总超时（官方：通常 1~5 分钟）。 */
export const IMAGE_POLL_INTERVAL_MS = 4000;
export const IMAGE_TASK_TIMEOUT_MS = 6 * 60 * 1000;

export interface ImageTaskStatus {
  status: string;
  imageUrls: string[];
  code: string;
  message: string;
}

export class ImageGenService {
  /** 创建文生图任务，返回 task_id。 */
  public static async createTask(prompt: string, ratio: string, resolution: string,
    count: number, apiKey: string): Promise<string> {
    const key: string = apiKey.trim();
    if (key.length === 0) {
      throw new Error('未配置百智云 API Key');
    }
    const body: Record<string, ESObject> = {
      'prompt': prompt,
      'image_count': count,
      'ratio': ratio,
      'resolution': resolution
    };
    const data: Record<string, ESObject> = await ImageGenService.post('/text_to_image', body, key);
    const taskId: ESObject = data['task_id'];
    if (typeof taskId !== 'string' || (taskId as string).length === 0) {
      throw new Error('创建生图任务失败：未返回 task_id');
    }
    return taskId as string;
  }

  /** 查询任务状态；未完成时 imageUrls 为空数组。 */
  public static async queryTask(taskId: string, apiKey: string): Promise<ImageTaskStatus> {
    const key: string = apiKey.trim();
    if (key.length === 0) {
      throw new Error('未配置百智云 API Key');
    }
    const result: Record<string, ESObject> = await ImageGenService.request('GET',
      `/tasks/${taskId}`, undefined, key);
    const dataVal: ESObject = result['data'];
    const data: Record<string, ESObject> = (dataVal !== null && typeof dataVal === 'object')
      ? dataVal as Record<string, ESObject> : {};
    const statusVal: ESObject = data['status'];
    const status: string = typeof statusVal === 'string' ? statusVal as string : '';
    const urls: string[] = ImageGenService.readUrls(data['image_urls']);
    const codeVal: ESObject = result['code'];
    const messageVal: ESObject = result['message'];
    return {
      status: status,
      imageUrls: urls,
      code: typeof codeVal === 'string' ? codeVal as string : '',
      message: typeof messageVal === 'string' ? messageVal as string : ''
    };
  }

  /** 重试失败任务（或补齐部分成功的缺失图片）。 */
  public static async retryTask(taskId: string, apiKey: string): Promise<void> {
    const key: string = apiKey.trim();
    if (key.length === 0) {
      throw new Error('未配置百智云 API Key');
    }
    await ImageGenService.request('POST', `/tasks/${taskId}/retry`, {}, key);
  }

  private static async post(path: string, body: Record<string, ESObject>,
    apiKey: string): Promise<Record<string, ESObject>> {
    const result: Record<string, ESObject> = await ImageGenService.request('POST', path, body, apiKey);
    const dataVal: ESObject = result['data'];
    if (dataVal === null || typeof dataVal !== 'object') {
      throw new Error('服务返回缺少 data');
    }
    return dataVal as Record<string, ESObject>;
  }

  private static async request(method: string, path: string, body: Record<string, ESObject> | undefined,
    apiKey: string): Promise<Record<string, ESObject>> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const header: Record<string, string> = {
        'Authorization': `Bearer ${apiKey}`,
        'Accept': 'application/json'
      };
      if (body !== undefined) {
        header['Content-Type'] = 'application/json';
      }
      const resp: http.HttpResponse = await req.request(`${BASE_URL}${path}`, {
        method: method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: header,
        extraData: body !== undefined ? JSON.stringify(body) : undefined,
        connectTimeout: CONNECT_TIMEOUT,
        readTimeout: READ_TIMEOUT
      });
      if (typeof resp.result !== 'string') {
        throw new Error(`生图服务返回异常（HTTP ${resp.responseCode}）`);
      }
      const parsed: ESObject = JSON.parse(resp.result as string) as ESObject;
      if (parsed === null || typeof parsed !== 'object') {
        throw new Error('生图服务返回格式异常');
      }
      const rec: Record<string, ESObject> = parsed as Record<string, ESObject>;
      const codeVal: ESObject = rec['code'];
      const code: string = typeof codeVal === 'string' ? codeVal as string : '';
      if (resp.responseCode !== 200 || code !== 'ok') {
        const msgVal: ESObject = rec['message'];
        const reason: string = typeof msgVal === 'string' && (msgVal as string).length > 0
          ? msgVal as string : `HTTP ${resp.responseCode}`;
        throw new Error(ImageGenService.errorText(code, reason));
      }
      return rec;
    } catch (err) {
      const reason: string = err instanceof Error ? err.message : String(err);
      hilog.error(DOMAIN, TAG, 'request %{public}s failed: %{public}s', path, reason);
      throw new Error(reason);
    } finally {
      req.destroy();
    }
  }

  private static readUrls(raw: ESObject): string[] {
    const out: string[] = [];
    if (!Array.isArray(raw)) {
      return out;
    }
    const list: ESObject[] = raw as ESObject[];
    let i: number = 0;
    while (i < list.length) {
      const item: ESObject = list[i];
      i += 1;
      if (typeof item === 'string') {
        const url: string = item as string;
        if (url.startsWith('https://') || url.startsWith('http://')) {
          out.push(url);
        }
      }
    }
    return out;
  }

  private static errorText(code: string, message: string): string {
    if (code === 'unauthorized') {
      return '百智云 API Key 无效或未配置模型';
    }
    if (code === 'not_found') {
      return '生图任务不存在或已过期';
    }
    if (code === 'payload_error') {
      return `生图参数无效：${message}`;
    }
    if (code === 'provider_error') {
      return `生图服务暂时不可用：${message}`;
    }
    if (code === 'provider_reject') {
      return `生成被拒绝：${message}`;
    }
    if (code === 'internal_error') {
      return `生图服务内部错误：${message}`;
    }
    return `生图失败：${message}`;
  }
}
