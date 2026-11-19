/*
 * UpdateService.ets
 *
 * 应用内更新检查：GitHub / Gitee 双源，按语义化版本比较，只提示不强制。
 * 1. 版本以运行时 BundleInfo.versionName 为准（与 AppScope/app.json5 同源，避免两份常量漂移）；
 * 2. 源顺序 Gitee → GitHub：Gitee API 在国内可直连，GitHub API 常被墙，作兜底；
 * 3. release tag 形如 v1.2.3，资产优先取 .hap（Gitee/GitHub 都放在 assets 里）；
 * 4. 静默检查按 12 小时节流（Preferences 记录上次检查时间），不打扰使用；
 * 5. 只负责「发现新版本」，安装交给系统浏览器打开下载链接（HarmonyOS 不允许应用静默安装 HAP）。
 *
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，捕获异常转为 Error 类型。
 */

import { http } from '@kit.NetworkKit';
import { bundleManager } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'UpdateService';

/** 仓库坐标：公开发布后固定，改仓只需改这两组。 */
const GITEE_OWNER = 'aishangwuji';
const GITEE_REPO = 'openchat';
const GITHUB_OWNER = 'aishangwuji';
const GITHUB_REPO = 'openchat';
const GITEE_API = `https://gitee.com/api/v5/repos/${GITEE_OWNER}/${GITEE_REPO}/releases/latest`;
const GITHUB_API = `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`;

const PREFS_NAME = 'update_prefs';
const KEY_LAST_CHECK = 'last_check_ts';
const CHECK_INTERVAL_MS = 12 * 60 * 60 * 1000;
/** release 说明最多展示 600 字，避免弹窗被长文淹没。 */
const MAX_NOTES_CHARS = 600;
const CONNECT_TIMEOUT = 8000;
const READ_TIMEOUT = 12000;

export interface UpdateInfo {
  /** 版本号（已去掉前缀 v），如 1.2.0 */
  version: string;
  /** release 说明（截断到 600 字，避免弹窗过长） */
  notes: string;
  /** release 页面，用于「查看详情」 */
  pageUrl: string;
  /** HAP 直链；没有资产时为空，下载按钮退回 pageUrl */
  downloadUrl: string;
  /** 来源，仅用于日志与文案 */
  source: string;
}

export class UpdateService {
  /** 当前版本（运行时读取，失败回退 1.0.0）。 */
  public static currentVersion(): string {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'read version failed: %{public}s', String(err));
      return '1.0.0';
    }
  }

  /**
   * 检查更新；无更新或检查失败返回 null。
   * Business Rule: 网络失败不抛错——调用方要么静默忽略，要么提示「检查失败」。
   */
  public static async check(context: common.UIAbilityContext): Promise<UpdateInfo | null> {
    const current: string = UpdateService.currentVersion();
    let info: UpdateInfo | null = await UpdateService.fetchGitee();
    if (info === null) {
      info = await UpdateService.fetchGithub();
    }
    if (info === null) {
      return null;
    }
    const newer: boolean = UpdateService.compareVersions(info.version, current) > 0;
    hilog.info(DOMAIN, TAG, 'check: current=%{public}s latest=%{public}s newer=%{public}s',
      current, info.version, String(newer));
    return newer ? info : null;
  }

  /** 静默检查：12 小时内只查一次；返回新版本信息供界面提示。 */
  public static async checkIfDue(context: common.UIAbilityContext): Promise<UpdateInfo | null> {
    try {
      const prefs: preferences.Preferences = await preferences.getPreferences(context, { name: PREFS_NAME });
      const lastVal: preferences.ValueType = await prefs.get(KEY_LAST_CHECK, 0);
      let last: number = 0;
      if (typeof lastVal === 'number') {
        last = lastVal as number;
      }
      if (Date.now() - last < CHECK_INTERVAL_MS) {
        return null;
      }
      await prefs.put(KEY_LAST_CHECK, Date.now());
      await prefs.flush();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'throttle read failed: %{public}s', String(err));
    }
    return UpdateService.check(context);
  }

  /** 版本比较：1.2.10 > 1.2.9；非法段按 0 处理。 */
  public static compareVersions(a: string, b: string): number {
    const pa: number[] = UpdateService.versionParts(a);
    const pb: number[] = UpdateService.versionParts(b);
    let i: number = 0;
    while (i < Math.max(pa.length, pb.length)) {
      const va: number = i < pa.length ? pa[i] : 0;
      const vb: number = i < pb.length ? pb[i] : 0;
      if (va > vb) {
        return 1;
      }
      if (va < vb) {
        return -1;
      }
      i += 1;
    }
    return 0;
  }

  private static versionParts(v: string): number[] {
    const text: string = v.trim().replace(/^v/i, '');
    const parts: string[] = text.split('.');
    const out: number[] = [];
    let i: number = 0;
    while (i < parts.length) {
      const n: number = parseInt(parts[i], 10);
      out.push(isNaN(n) ? 0 : n);
      i += 1;
    }
    return out;
  }

  private static async fetchGitee(): Promise<UpdateInfo | null> {
    const body: Record<string, ESObject> | null = await UpdateService.getJson(GITEE_API, 'gitee');
    if (body === null) {
      return null;
    }
    return UpdateService.parseRelease(body, 'gitee');
  }

  private static async fetchGithub(): Promise<UpdateInfo | null> {
    const body: Record<string, ESObject> | null = await UpdateService.getJson(GITHUB_API, 'github');
    if (body === null) {
      return null;
    }
    return UpdateService.parseRelease(body, 'github');
  }

  private static async getJson(url: string, source: string): Promise<Record<string, ESObject> | null> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json',
          'User-Agent': 'openchat-UpdateChecker'
        },
        connectTimeout: CONNECT_TIMEOUT,
        readTimeout: READ_TIMEOUT,
        usingCache: false
      });
      if (resp.responseCode !== 200 || typeof resp.result !== 'string') {
        hilog.warn(DOMAIN, TAG, '%{public}s http %{public}d', source, resp.responseCode);
        return null;
      }
      const parsed: ESObject = JSON.parse(resp.result as string) as ESObject;
      if (parsed === null || typeof parsed !== 'object') {
        return null;
      }
      return parsed as Record<string, ESObject>;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '%{public}s fetch failed: %{public}s', source, String(err));
      return null;
    } finally {
      req.destroy();
    }
  }

  private static parseRelease(body: Record<string, ESObject>, source: string): UpdateInfo | null {
    const tagRaw: ESObject = body['tag_name'];
    if (typeof tagRaw !== 'string' || (tagRaw as string).length === 0) {
      return null;
    }
    const version: string = (tagRaw as string).replace(/^v/i, '');
    const pageRaw: ESObject = body['html_url'];
    const pageUrl: string = typeof pageRaw === 'string' ? pageRaw as string : '';
    const bodyRaw: ESObject = body['body'];
    let notes: string = typeof bodyRaw === 'string' ? bodyRaw as string : '';
    if (notes.length > MAX_NOTES_CHARS) {
      notes = notes.substring(0, MAX_NOTES_CHARS) + '…';
    }
    const downloadUrl: string = UpdateService.pickAsset(body['assets']);
    return {
      version: version,
      notes: notes,
      pageUrl: pageUrl,
      downloadUrl: downloadUrl.length > 0 ? downloadUrl : pageUrl,
      source: source
    };
  }

  /** 资产优先级：.hap > .app > 第一个可下载链接。 */
  private static pickAsset(raw: ESObject): string {
    if (!Array.isArray(raw)) {
      return '';
    }
    const list: ESObject[] = raw as ESObject[];
    let hap: string = '';
    let apk: string = '';
    let first: string = '';
    let i: number = 0;
    while (i < list.length) {
      const item: ESObject = list[i];
      i += 1;
      if (item === null || typeof item !== 'object') {
        continue;
      }
      const rec: Record<string, ESObject> = item as Record<string, ESObject>;
      const urlVal: ESObject = rec['browser_download_url'];
      if (typeof urlVal !== 'string') {
        continue;
      }
      const url: string = urlVal as string;
      if (first.length === 0) {
        first = url;
      }
      if (url.toLowerCase().endsWith('.hap') && hap.length === 0) {
        hap = url;
      }
      if (url.toLowerCase().endsWith('.apk') && apk.length === 0) {
        apk = url;
      }
    }
    return hap.length > 0 ? hap : (apk.length > 0 ? apk : first);
  }
}



