/*
 * MarkdownService.ets
 *
 * 聊天 Markdown 渲染的纯逻辑层 —— FluidMarkdown（ohpm: fluid-markdown）之上的
 * 本项目适配器。与 UI 解耦，可独立审查与单测：
 * 1. rewriteCitations：把模型输出的 [ref_N] 改写为库可渲染的链接 [N](#cite-N)，
 *    点击经 onMarkdownNodeClick 回路由到来源（引用来源列表待模型侧提供，见 handbook）；
 *    围栏代码块与行内代码段内的标记不改写（原文透传）。
 * 2. routeHref/isSafeOpenUrl：外链白名单（http/https/mailto），其余一律拦截；
 *    库本身经 StyledString 原生渲染，无脚本执行面，此处是第二道边界。
 * 3. applyTheme：字号缩放 + 深浅色映射到库主题（ITheme.document.font）。
 *
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，捕获异常转为 Error 类型。
 */

import { BaseEngine } from 'fluid-markdown';
import { LengthMetrics } from '@ohos.arkui.node';

export type MdClickKind = 'cite' | 'open' | 'ignore';

export interface MdClickAction {
  kind: MdClickKind;
  /** open 场景的 URL；cite 场景为 ''。 */
  target: string;
  /** cite 场景的引用序号（1 起）；其余为 0。 */
  index: number;
}

const CITE_HREF_PREFIX = '#cite-';

export class MarkdownService {
  /**
   * 改写引用标记：[ref_N] -> [N](#cite-N)，围栏/行内代码内不碰。
   * Business Rule: 模型原文可能把 [ref_1] 写进代码示例，改写必须 fence-aware，
   *   否则示例代码会被污染成链接。
   */
  public static rewriteCitations(src: string): string {
    if (src.length === 0 || src.indexOf('[ref_') < 0) {
      return src;
    }
    const lines: string[] = src.split('\n');
    const out: string[] = [];
    let fence: string = '';
    let i: number = 0;
    while (i < lines.length) {
      const line: string = lines[i];
      const fenceMark: string = MarkdownService.fenceOf(line);
      if (fenceMark.length > 0) {
        if (fence.length === 0) {
          fence = fenceMark;
        } else if (fenceMark === fence) {
          fence = '';
        }
        out.push(line);
      } else if (fence.length > 0) {
        out.push(line);
      } else {
        out.push(MarkdownService.rewriteLine(line));
      }
      i += 1;
    }
    return out.join('\n');
  }

  /** 行首（允许缩进）``` 或 ~~~ 视为围栏标记，返回标记符本身，否则返回 ''。 */
  private static fenceOf(line: string): string {
    let i: number = 0;
    while (i < line.length && (line.charAt(i) === ' ' || line.charAt(i) === '\t')) {
      i += 1;
    }
    if (line.indexOf('```', i) === i) {
      return '```';
    }
    if (line.indexOf('~~~', i) === i) {
      return '~~~';
    }
    return '';
  }

  /** 行内改写：跳过反引号代码段，只处理普通文本区。 */
  private static rewriteLine(line: string): string {
    let result: string = '';
    let plain: string = '';
    let i: number = 0;
    const flushPlain = (): void => {
      if (plain.length > 0) {
        result += MarkdownService.rewritePlain(plain);
        plain = '';
      }
    };
    while (i < line.length) {
      if (line.charAt(i) === '`') {
        let run: number = 0;
        while (i + run < line.length && line.charAt(i + run) === '`') {
          run += 1;
        }
        const closeAt: number = line.indexOf('`'.repeat(run), i + run);
        if (closeAt < 0) {
          // 无闭合：剩余部分按普通文本处理（流式未闭合容错）。
          plain += line.substring(i);
          break;
        }
        flushPlain();
        result += line.substring(i, closeAt + run);
        i = closeAt + run;
      } else {
        plain += line.charAt(i);
        i += 1;
      }
    }
    flushPlain();
    return result;
  }

  private static rewritePlain(segment: string): string {
    let out: string = '';
    let rest: string = segment;
    while (true) {
      const start: number = rest.indexOf('[ref_');
      if (start < 0) {
        out += rest;
        break;
      }
      let j: number = start + 5;
      let digits: string = '';
      while (j < rest.length && rest.charAt(j) >= '0' && rest.charAt(j) <= '9') {
        digits += rest.charAt(j);
        j += 1;
      }
      if (digits.length > 0 && j < rest.length && rest.charAt(j) === ']') {
        out += rest.substring(0, start) + '[' + digits + '](' + CITE_HREF_PREFIX + digits + ')';
        rest = rest.substring(j + 1);
      } else {
        out += rest.substring(0, start + 5);
        rest = rest.substring(start + 5);
      }
    }
    return out;
  }

  /** 外链白名单：仅 http/https/mailto 允许交系统打开。 */
  public static isSafeOpenUrl(url: string): boolean {
    const lower: string = url.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('mailto:');
  }

  /** '#cite-N' -> N；非引用返回 0。 */
  public static citeIndexFromHref(href: string): number {
    const h: string = href.trim();
    if (!h.startsWith(CITE_HREF_PREFIX)) {
      return 0;
    }
    const digits: string = h.substring(CITE_HREF_PREFIX.length);
    if (digits.length === 0) {
      return 0;
    }
    let i: number = 0;
    while (i < digits.length) {
      if (digits.charAt(i) < '0' || digits.charAt(i) > '9') {
        return 0;
      }
      i += 1;
    }
    const n: number = Number.parseInt(digits, 10);
    return Number.isFinite(n) ? n : 0;
  }

  /** 点击路由：引用 / 外链 / 拦截三态，调用方按 kind 执行。 */
  public static routeHref(href: string): MdClickAction {
    const cite: number = MarkdownService.citeIndexFromHref(href);
    if (cite > 0) {
      const action: MdClickAction = { kind: 'cite', target: '', index: cite };
      return action;
    }
    if (MarkdownService.isSafeOpenUrl(href)) {
      const action: MdClickAction = { kind: 'open', target: href.trim(), index: 0 };
      return action;
    }
    const action: MdClickAction = { kind: 'ignore', target: '', index: 0 };
    return action;
  }

  /**
   * 主题映射：字号跟随系统设置档，深色切换正文色。
   * Reason: 库主题经 IStyledTextValue（ArkUI TextStyleInterface）描述，
   *   只覆盖 document.font 的 size/color，不碰其余默认排版，避免破坏库内联样式级联。
   */
  public static applyTheme(engine: BaseEngine, fontScale: number, dark: boolean): void {
    try {
      const themeSvc = engine.theme;
      if (!themeSvc) {
        return;
      }
      const theme = themeSvc.theme;
      if (!theme || !theme.document) {
        return;
      }
      const scale: number = fontScale > 0 ? fontScale : 1.0;
      theme.document.font = {
        fontSize: LengthMetrics.vp(Math.round(15 * scale)),
        fontColor: dark ? '#E5E7EB' : '#111827',
      };
      // Reason: 图片样式（theme.image）本次回退不设 —— 曾尝试 textBlock 居中 + maxHeight 限高，
      //   随后出现 Markdown 整块空白，疑为普通对象不符合库内 StyledParagraphValue 级联预期、
      //   在渲染期（try/catch 之外）异常致整块不渲染。先回退保渲染，居中方案待对照库源码再定。
      //   （文档 font 的普通对象赋值是已验证安全的，保持。）
    } catch (_err) {
      // 主题为体验增强，失败不阻断渲染（库默认主题兜底）。
    }
  }
}
