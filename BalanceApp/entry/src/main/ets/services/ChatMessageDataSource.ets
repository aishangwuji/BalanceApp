/*
 * ChatMessageDataSource.ets
 *
 * 消息列表的 LazyForEach 数据源 —— 只为视口内的消息创建 Markdown 组件实例。
 * Reason: List + ForEach 会一次性实例化整条激活分支（实测 55 条会话同时建 55 个
 *   BaseEngine 并触发 55 次异步 Markdown 解析），开会话时卡顿且可见内容长时间空白；
 *   改为 LazyForEach 后只挂载视口附近几条。
 *
 * 同步策略（性能关键）：
 * - 数量/顺序/身份（id）变化 -> onDataReloaded 全量重建（发送新消息、切会话、切分支）；
 * - 仅个别条目渲染键变化（流式思考字数、状态、折叠、字号/主题）-> onDataChanged
 *   精准刷新该条，避免流式期整表重建把 MarkdownBody 打回空白。
 *
 * 遵循 ArkTS 严格模式规范：无 any/unknown，无解构，强类型定义。
 */

import { ChatMessage } from '../models/ChatModels';

export class ChatMessageDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: ChatMessage[] = [];
  private keys: string[] = [];

  public totalCount(): number {
    return this.items.length;
  }

  public getData(index: number): ChatMessage {
    return this.items[index];
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  /**
   * 用新的分支路径与对应的渲染键同步数据源。
   * @param next 新的激活分支消息（与 activePath 一致）。
   * @param nextKeys 与 next 一一对应的渲染键（由调用方的 msgRenderKey 生成）。
   */
  public sync(next: ChatMessage[], nextKeys: string[]): void {
    const structural: boolean = this.isStructuralChange(next);
    this.items = next;

    if (structural) {
      this.keys = nextKeys;
      this.notifyReload();
      return;
    }

    // 先统计变化面：大面积变化（折叠态/字号/主题等影响全表 key）走整表 reload，
    // 避免逐个 notifyDataChange 造成 N 次条目重建。
    let changed: number = 0;
    let i: number = 0;
    while (i < nextKeys.length) {
      if (this.keys[i] !== nextKeys[i]) {
        changed += 1;
      }
      i += 1;
    }
    if (changed >= 8) {
      this.keys = nextKeys;
      this.notifyReload();
      return;
    }

    i = 0;
    while (i < nextKeys.length) {
      if (this.keys[i] !== nextKeys[i]) {
        this.keys[i] = nextKeys[i];
        this.notifyChange(i);
      }
      i += 1;
    }
  }

  /** 数量、顺序或消息身份变化视为结构性变更（需要全量重建）。 */
  private isStructuralChange(next: ChatMessage[]): boolean {
    if (next.length !== this.items.length) {
      return true;
    }
    let i: number = 0;
    while (i < next.length) {
      if (next[i].id !== this.items[i].id) {
        return true;
      }
      i += 1;
    }
    return false;
  }

  private notifyReload(): void {
    let i: number = 0;
    while (i < this.listeners.length) {
      this.listeners[i].onDataReloaded();
      i += 1;
    }
  }

  private notifyChange(index: number): void {
    let i: number = 0;
    while (i < this.listeners.length) {
      this.listeners[i].onDataChanged(index);
      i += 1;
    }
  }
}
