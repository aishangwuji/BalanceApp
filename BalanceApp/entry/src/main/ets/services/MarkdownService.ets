/*
 * MarkdownService.ets
 *
 * 聊天 Markdown 渲染的纯逻辑层 —— FluidMarkdown（ohpm: fluid-markdown）之上的
 * 本项目适配器。与 UI 解耦，可独立审查与单测：
 * 1. rewriteCitations：把模型输出的 [ref_N] 改写为库可渲染的链接 [N](#cite-N)，
 *    点击经 onMarkdownNodeClick 回路由到来源（来源已由 annotations 提供）；围栏代码块与
 *    行内代码段内的标记不改写（原文透传）。
 * 1.1 injectCitations：按服务端 annotations 的引用区间（Unicode 码点）在正文相应位置插入
 *    [N](#cite-N) 角标；围栏代码块内不插，从后往前插避免下标位移。
 * 2. routeHref/isSafeOpenUrl：外链白名单（http/https/mailto），其余一律拦截；
 *    库本身经 StyledString 原生渲染，无脚本执行面，此处是第二道边界。
 * 3. applyTheme：字号缩放 + 深浅色映射到库主题（ITheme.document.font）。
 *
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，捕获异常转为 Error 类型。
 */

import { BaseEngine } from 'fluid-markdown';
import { LengthMetrics } from '@ohos.arkui.node';
import { CitationRange } from '../models/ChatModels';

export type MdClickKind = 'cite' | 'open' | 'ignore';

export interface MdClickAction {
  kind: MdClickKind;
  /** open 场景的 URL；cite 场景为 ''。 */
  target: string;
  /** cite 场景的引用序号（1 起）；其余为 0。 */
  index: number;
}

const CITE_HREF_PREFIX = '#cite-';

/** 待插入的引用角标（内部结构，按 at 降序插回正文）。 */
interface CiteMarker {
  at: number;
  /** 来源序号（1 起）：同一位置多个角标时按序号升序排列。 */
  index: number;
  text: string;
}

export class MarkdownService {
  /**
   * 在正文按引用区间插入可点角标 [N](#cite-N)。
   * Business Rule:
   *   1. 区间是 Unicode 码点下标，必须先换算成 UTF-16 下标；
   *   2. 角标插在区间末尾（引用文本之后），与官方 App 的角标位置一致；
   *   3. 落在围栏代码块内的区间不插（避免污染示例代码），
   *   4. 从后往前插，避免前面的插入改变后面的下标。
   * @param citeIndex url -> 来源序号（1 起）；未收录的 url 跳过。
   */
  public static injectCitations(src: string, citations: CitationRange[] | undefined,
    citeIndex: Map<string, number>): string {
    if (src.length === 0 || citations === undefined || citations.length === 0) {
      return src;
    }
    const markers: CiteMarker[] = [];
    let i: number = 0;
    while (i < citations.length) {
      const cite: CitationRange = citations[i];
      i += 1;
      const index: number | undefined = citeIndex.get(cite.url);
      if (index === undefined || index <= 0) {
        continue;
      }
      const at: number = MarkdownService.codePointToUtf16Offset(src, cite.end);
      if (at <= 0 || at > src.length) {
        continue;
      }
      if (MarkdownService.inFencedLine(src, at)) {
        continue;
      }
      const marker: CiteMarker = {
        at: at,
        index: index,
        text: `[${index}](${CITE_HREF_PREFIX}${index})`
      };
      markers.push(marker);
    }
    // 插入位置降序：先改靠后的位置，前面的下标才不会被挤动；
    // 同一位置的多个角标先插大序号，最终呈现为 [1][2] 的升序。
    markers.sort((a: CiteMarker, b: CiteMarker) => {
      if (b.at !== a.at) {
        return b.at - a.at;
      }
      return b.index - a.index;
    });
    let out: string = src;
    let mi: number = 0;
    while (mi < markers.length) {
      const m: CiteMarker = markers[mi];
      out = out.substring(0, m.at) + m.text + out.substring(m.at);
      mi += 1;
    }
    return out;
  }

  /** 码点下标 -> UTF-16 下标；码点越界返回 -1（调用方跳过）。 */
  private static codePointToUtf16Offset(text: string, cp: number): number {
    let i: number = 0;
    let count: number = 0;
    while (i < text.length && count < cp) {
      const code: number = text.charCodeAt(i);
      const isHighSurrogate: boolean = code >= 0xD800 && code <= 0xDBFF;
      if (isHighSurrogate && i + 1 < text.length) {
        i += 2;
      } else {
        i += 1;
      }
      count += 1;
    }
    if (count < cp) {
      return -1;
    }
    return i;
  }

  /** 该下标是否落在围栏代码块（含围栏标记行）内。 */
  private static inFencedLine(src: string, at: number): boolean {
    let line: number = 0;
    let i: number = 0;
    while (i < at) {
      if (src.charCodeAt(i) === 10) {
        line += 1;
      }
      i += 1;
    }
    const lines: string[] = src.split('\n');
    let fence: string = '';
    let li: number = 0;
    while (li < lines.length) {
      const mark: string = MarkdownService.fenceOf(lines[li]);
      const isFencedBefore: boolean = fence.length > 0;
      if (mark.length > 0) {
        if (fence.length === 0) {
          fence = mark;
        } else if (mark === fence) {
          fence = '';
        }
        if (li === line) {
          return true;
        }
      } else if (li === line) {
        return isFencedBefore;
      }
      li += 1;
    }
    return false;
  }

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
        fontColor: dark ? '#E9E4D9' : '#292822',
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
