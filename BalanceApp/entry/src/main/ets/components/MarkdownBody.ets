/*
 * MarkdownBody.ets
 *
 * FluidMarkdown 的 V1 包装器 —— 把库（@ComponentV2）的接入细节收敛在一处，
 * ChatView 只与本组件打交道：
 * - streaming=false：Normal 模式一次性渲染（历史消息 / 已完成回复）；
 * - streaming=true：Typing 模式，ChatView 经 controller 逐 token 喂累计文本，
 *   库内按节点 hash 差量更新 + 打字机 pacing，零闪烁；
 * - controller/engine 由本实例字段持有（随实例创建，随实例销毁），mode 切换
 *   靠父级 key 更换实例（库 mode 为 @Once，不支持实例内切换）；
 * - 点击经 onLinkClick/onImageClick 回调上抛原始 href/src，安全策略由
 *   MarkdownService.routeHref 统一裁决，本组件不直接开外链。
 *
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，函数类型用普通成员。
 */

import {
  Markdown, EMarkdownMode, MarkdownController, BaseEngine,
  ENode, Link, Image,
  type IMarkdownNodeClickEvent, type IMarkdownEvent, type Node,
} from 'fluid-markdown';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MarkdownService } from '../services/MarkdownService';

const DOMAIN = 0x0000;
const TAG = 'MarkdownBody';

@Component
export struct MarkdownBody {
  @Prop content: string = '';
  /** true=Typing 流式；false=Normal 全量。实例内不可切换，靠父级 key 重建。 */
  streaming: boolean = false;
  /** Reason: 父级以 @StorageProp 下发字号，普通成员接不住联动，必须 @Prop。 */
  @Prop fontScale: number = 1.0;
  darkMode: boolean = false;
  /** 流式驱动器：由父级（ChatView）持有并透传，实例销毁即释放。 */
  controller: MarkdownController | undefined = undefined;
  /** 点击回调：外链 href / 图片 src，调用方裁决后执行。 */
  onLinkClick: (href: string) => void = () => {};
  onImageClick: (src: string) => void = () => {};
  /** 尺寸变化（流式长高时父级做锚定滚动）与打字完成通知。 */
  onMdResize: () => void = () => {};
  onTypingDone: () => void = () => {};

  private engine: BaseEngine = new BaseEngine();
  private innerController: MarkdownController = new MarkdownController({});

  private activeController(): MarkdownController {
    return this.controller !== undefined ? this.controller : this.innerController;
  }

  aboutToAppear(): void {
    MarkdownService.applyTheme(this.engine, this.fontScale, this.darkMode);
  }

  private handleNodeClick(e: IMarkdownNodeClickEvent): void {
    try {
      const node: Node = e.node;
      if (node.is(ENode.Link)) {
        const href: string = (node as Link).href ?? '';
        if (href.length > 0) {
          this.onLinkClick(href);
        }
        return;
      }
      if (node.is(ENode.Image)) {
        const src: string = (node as Image).src ?? '';
        if (src.length > 0) {
          this.onImageClick(src);
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'node click handle failed: %{public}s', String(err));
    }
  }

  private handleTypingDone(_e: IMarkdownEvent): void {
    this.onTypingDone();
  }

  build() {
    if (this.streaming) {
      Markdown({
        controller: this.activeController(),
        engine: this.engine,
        mode: EMarkdownMode.Typing,
        onMarkdownNodeClick: (e: IMarkdownNodeClickEvent) => {
          this.handleNodeClick(e);
        },
        onMarkdownAreaChange: () => {
          this.onMdResize();
        },
        onMarkdownTypingCompleted: (e: IMarkdownEvent) => {
          this.handleTypingDone(e);
        },
      })
    } else {
      Markdown({
        content: this.content,
        engine: this.engine,
        mode: EMarkdownMode.Normal,
        onMarkdownNodeClick: (e: IMarkdownNodeClickEvent) => {
          this.handleNodeClick(e);
        },
        onMarkdownAreaChange: () => {
          this.onMdResize();
        },
      })
    }
  }
}
