/*
 * BaizhiWebSearchService.ets
 *
 * 百智云联网搜索（OpenAPI）：POST /openapi/search。
 * 1. 与 DeepSeek 服务端工具不同，这里由客户端先检索、再把摘要注入上下文，
 *    因此「是否联网」在发送前就确定，来源也能直接挂在消息上；
 * 2. 每次成功调用按积分计费（2.5 积分/次），失败不计费；空结果同样计费；
 * 3. Key 单独存（key_baizhi_web），与生图 Key 分开授权。
 *
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，捕获异常转为 Error 类型。
 */

import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SearchSource } from '../models/ChatModels';

const DOMAIN = 0x0000;
const TAG = 'BaizhiWebSearchService';
const SEARCH_URL = 'https://websearch.app.baizhi.cloud/openapi/search';
const CONNECT_TIMEOUT = 12000;
const READ_TIMEOUT = 25000;
const MAX_RESULTS = 8;

export class BaizhiWebSearchService {
  /** 检索网页，返回去重后的来源列表；失败抛 Error（调用方降级为「不联网」）。 */
  public static async search(query: string, apiKey: string, count: number): Promise<SearchSource[]> {
    const key: string = apiKey.trim();
    if (key.length === 0) {
      throw new Error('未配置百智云搜索 Key');
    }
    const n: number = Math.max(1, Math.min(MAX_RESULTS, count));
    const body: Record<string, ESObject> = {
      'query': query,
      'count': n,
      'time_range': 'month',
      'need_summary': true
    };
    const req: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await req.request(SEARCH_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        extraData: JSON.stringify(body),
        connectTimeout: CONNECT_TIMEOUT,
        readTimeout: READ_TIMEOUT
      });
      if (typeof resp.result !== 'string') {
        throw new Error(`搜索服务返回异常（HTTP ${resp.responseCode}）`);
      }
      const parsed: ESObject = JSON.parse(resp.result as string) as ESObject;
      if (parsed === null || typeof parsed !== 'object') {
        throw new Error('搜索服务返回格式异常');
      }
      const rec: Record<string, ESObject> = parsed as Record<string, ESObject>;
      const codeVal: ESObject = rec['code'];
      if (typeof codeVal !== 'number' || (codeVal as number) !== 0) {
        const msgVal: ESObject = rec['message'];
        throw new Error(typeof msgVal === 'string' ? msgVal as string : `搜索失败（code=${codeVal}）`);
      }
      return BaizhiWebSearchService.readResults(rec['data']);
    } catch (err) {
      const reason: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'search failed: %{public}s', reason);
      throw new Error(reason);
    } finally {
      req.destroy();
    }
  }

  /**
   * 把来源拼成注入给模型的上下文段落（编号与来源列表顺序一致，便于回答里引用）。
   * Business Rule: 只放标题 + 站点 + 摘要 + 链接，控制 token；不做二次总结。
   */
  public static buildContextMessage(sources: SearchSource[]): string {
    if (sources.length === 0) {
      return '';
    }
    const lines: string[] = [];
    lines.push('以下是通过联网搜索得到的参考资料（可能不完整，请结合常识判断）：');
    let i: number = 0;
    while (i < sources.length) {
      const s: SearchSource = sources[i];
      const site: string = s.siteName !== undefined && s.siteName.length > 0 ? s.siteName : s.url;
      const snippet: string = s.snippet !== undefined ? s.snippet : '';
      lines.push(`[${i + 1}] ${s.title}（${site}）`);
      if (snippet.length > 0) {
        lines.push(snippet);
      }
      lines.push(s.url);
      i += 1;
    }
    lines.push('回答时如使用了上述资料，请在句末用 [编号] 标注来源。');
    return lines.join('\n');
  }

  private static readResults(dataVal: ESObject): SearchSource[] {
    if (dataVal === null || typeof dataVal !== 'object') {
      return [];
    }
    const data: Record<string, ESObject> = dataVal as Record<string, ESObject>;
    const listVal: ESObject = data['results'];
    if (!Array.isArray(listVal)) {
      return [];
    }
    const list: ESObject[] = listVal as ESObject[];
    const out: SearchSource[] = [];
    const seen: string[] = [];
    let i: number = 0;
    while (i < list.length) {
      const item: ESObject = list[i];
      i += 1;
      if (item === null || typeof item !== 'object') {
        continue;
      }
      const rec: Record<string, ESObject> = item as Record<string, ESObject>;
      const urlVal: ESObject = rec['url'];
      if (typeof urlVal !== 'string') {
        continue;
      }
      const url: string = urlVal as string;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        continue;
      }
      if (seen.includes(url)) {
        continue;
      }
      seen.push(url);
      const titleVal: ESObject = rec['title'];
      const summaryVal: ESObject = rec['summary'];
      const siteVal: ESObject = rec['site_name'];
      const publishedVal: ESObject = rec['published_at'];
      const source: SearchSource = {
        url: url,
        title: typeof titleVal === 'string' && (titleVal as string).length > 0
          ? titleVal as string : url,
        snippet: typeof summaryVal === 'string' ? summaryVal as string : '',
        siteName: typeof siteVal === 'string' ? siteVal as string : '',
        publishedAt: typeof publishedVal === 'string' ? publishedVal as string : ''
      };
      out.push(source);
    }
    return out;
  }
}
