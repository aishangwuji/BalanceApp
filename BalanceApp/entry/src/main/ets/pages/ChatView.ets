/*
 * ChatView.ets
 *
 * 智能对话主界面（类似独立 DeepSeek / 智额 客户端体验）
 * 1. 禁用所有 Emoji 表情符，采用纯文本及标准图形；
 * 2. 隐藏滚动条（.scrollBar(BarState.Off)），滑动干净无多余条框；
 * 3. 严格使用厂商官方实时接口拉取真实可用模型列表。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  ChatMessage, ChatSession, CharacterCard, ModelInfo, MessageRole, UserIdentityCard
} from '../models/ChatModels';
import { ChatService, StreamCallbacks } from '../services/ChatService';
import { ModelService } from '../services/ModelService';
import { ChatStorageService } from '../services/ChatStorageService';
import { AuthService } from '../services/AuthService';
import { ChatMessageDataSource } from '../services/ChatMessageDataSource';
import { PROVIDERS, ProviderDefinition, findProvider, isThinkingSupported } from '../services/ProviderRegistry';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { ThinkingButton } from '../components/ThinkingButton';
import { MarkdownBody } from '../components/MarkdownBody';
import { MarkdownService, MdClickAction } from '../services/MarkdownService';
import { MarkdownController, ETypingMode } from 'fluid-markdown';

const DOMAIN = 0x0000;
const TAG = 'ChatView';
const PREFS_NAME = 'balance_prefs';
// 输入框固定高度（折叠态默认两行内滚动）与展开态高度，超出部分由 TextArea 内部滚动查看。
const INPUT_BASE_HEIGHT = 68;
const INPUT_EXPANDED_HEIGHT = 200;

/** 无角色卡时的中性兜底：不附带任何系统设定与开场白。 */
const EMPTY_CHARACTER: CharacterCard = {
  id: '', name: '', avatarIcon: '', description: '',
  systemPrompt: '', firstMessage: '', temperature: 0.7, knowledge: '', createdAt: 0,
};

@Component
export struct ChatView {
  // ── 核心状态 ──
  @State sessions: ChatSession[] = [];
  @State currentSessionId: string = '';
  /**
   * 草稿会话：应用启动 / 点「+ 新会话」时使用，尚未写入历史。
   * Business Rule: 空会话不落盘、不进历史抽屉；一旦产生消息（attach）立即提升为正式会话并持久化，
   *   这样「每次启动默认新会话」不会在历史里堆一堆空「新对话」。
   */
  private draftSession: ChatSession | undefined = undefined;
  @State characters: CharacterCard[] = [];
  @State currentCharacterId: string = '';
  @State currentProviderId: string = 'deepseek';
  @State currentModelId: string = '';
  @State currentApiKey: string = '';

  // 消息流与输入
  @State inputText: string = '';
  // 输入框展开态：折叠时固定两行高度内滚动，展开后可查看更全面的输入内容。
  @State inputExpanded: boolean = false;
  @State isGenerating: boolean = false;
  @State showJumpBottom: boolean = false;
  @State noticeText: string = '';
  @StorageProp('auto_collapse_thinking') autoCollapseThinking: boolean = true;
  @StorageProp('app_font_scale') appFontScale: number = 1.0;
  @StorageProp('app_appearance') appearance: string = 'system';
  // 解析后的实际深色态（system 跟随系统，由 SettingsService/EntryAbility 落存）。
  @StorageProp('app_dark') appDark: boolean = false;
  // Markdown 流式驱动：仅存活中的流式消息持有（生成开始建、结束/停止/删会话时删）。
  private mdControllers: Map<string, MarkdownController> = new Map();
  private mdTypingBegun: string[] = [];
  // Typing 就绪态：库 onMarkdownTypingReady 回调后才允许 update（Begin 不丢失）。
  private mdTypingReady: string[] = [];
  // 流式刷新节流：token 高频到达时全表重建压垮 UI 线程 → 视感"一次性"；按 tick 合并。
  private lastRefreshAt: number = 0;
  private refreshPending: boolean = false;
  @State previewImage: string = '';
  // 思考过程折叠（reasonVersion 变化强制 ForEach 按 key 刷新对应条目）
  @State reasonVersion: number = 0;
  private collapsedReasons: string[] = [];
  @State enableThinking: boolean = true;
  @State availableModels: ModelInfo[] = [];
  @State fetchingModels: boolean = false;
  @State configuredProviders: ProviderDefinition[] = [];

  // 弹窗与抽屉控制
  @State showDrawer: boolean = false;
  @State showModelPicker: boolean = false;
  @State showCharacterSheet: boolean = false;
  @State showCharEditDialog: boolean = false;

  // 消息操作（长按菜单 + 编辑重发）
  @State actionMsgId: string = '';
  @State showEditDialog: boolean = false;
  @State editMsgId: string = '';
  @State editMsgText: string = '';
  // 角色卡长按操作
  @State charActionId: string = '';
  @State showCharDeleteConfirm: boolean = false;
  // 新会话角色选择（单选，一次只绑定一个角色）
  @State pendingParticipants: string[] = [];
  // 角色卡面板模式：select=新会话选择，manage=角色管理
  @State characterSheetMode: 'select' | 'manage' = 'select';
  // 用户身份卡（我扮演谁）
  @State identities: UserIdentityCard[] = [];
  @State pendingIdentityId: string = '';
  @State showIdentityEdit: boolean = false;
  @State editingIdentityId: string = '';
  @State editingIdentityName: string = '';
  @State editingIdentityPersona: string = '';
  @State identityActionId: string = '';
  @State showIdentityDeleteConfirm: boolean = false;
  // @ 指定发言人（群聊）
  @State pendingMentions: string[] = [];
  @State showMentionPicker: boolean = false;
  // 历史会话长按操作（重命名/删除）
  @State sessActionId: string = '';
  @State showRenameDialog: boolean = false;
  @State renameText: string = '';
  @State showDeleteConfirm: boolean = false;

  // 角色卡编辑临时状态
  @State editingCharId: string = '';
  @State editingCharName: string = '';
  @State editingCharPrompt: string = '';
  @State editingCharFirstMsg: string = '';
  @State editingCharTemp: number = 0.7;

  // 消息流数据源：LazyForEach 只为视口内消息创建 Markdown 实例（见 ChatMessageDataSource 注释）。
  private msgSource: ChatMessageDataSource = new ChatMessageDataSource();

  // 滚动控制器
  private scroller: Scroller = new Scroller();
  private abortStreaming: () => void = () => {};
  private balancePrefs: preferences.Preferences | undefined = undefined;
  private seq: number = 0;
  // 顶部锚定滚动状态
  private userTookOver: boolean = false;
  private lastAnchorOffset: number = -1;
  private anchorCaptured: boolean = false;
  // 单条回复只锚定一次：记下已锚定的消息 id，防每 token 重复 scrollToIndex 把用户拖动拽回。
  private anchoredForMsgId: string = '';
  // 思考区内嵌滚动跟随：定高 380 + Scroll，流式超出后新文本沉底不可见，需在底部时跟底。
  private thinkScrollers: Map<string, Scroller> = new Map();
  // 流式诊断计数（完成时打一行 hilog，区分"服务端一次性下发"与"UI 未刷新"）。
  private reasonChunkCount: number = 0;
  private contentChunkCount: number = 0;
  // 当前流式生成的完成回调（停止时唤醒等待链，避免挂起）
  private resolveCurrent: (() => void) | undefined = undefined;

  async aboutToAppear(): Promise<void> {
    try {
      const uiCtx = this.getUIContext();
      const hostCtx = uiCtx.getHostContext() as common.UIAbilityContext;
      await ChatStorageService.init(hostCtx);
      this.balancePrefs = await preferences.getPreferences(hostCtx, { name: PREFS_NAME });

      // 加载角色卡
      this.characters = await ChatStorageService.loadCharacters();
      if (this.characters.length > 0) {
        this.currentCharacterId = this.characters[0].id;
      }
      // 加载用户身份卡
      this.identities = await ChatStorageService.loadIdentities();

      // 加载会话，并清理旧版本遗留的空会话（历史曾因「每次启动新建」堆入空「新对话」）。
      const loaded: ChatSession[] = await ChatStorageService.loadSessions();
      const kept: ChatSession[] = [];
      let si: number = 0;
      while (si < loaded.length) {
        if (loaded[si].messages.length > 0) {
          kept.push(loaded[si]);
        }
        si += 1;
      }
      this.sessions = kept;
      if (kept.length !== loaded.length) {
        await ChatStorageService.saveSessions(kept);
      }
      // Business Rule: 每次应用重启都进入一个全新的空白会话（草稿，不落盘），不再自动恢复上次会话；
      //   保密会话（isPrivate）也因此不会在启动时被直接展开。
      await this.createNewSession();

      // 历史会话思考过程初始化默认折叠
      this.initCollapsedReasons();

      // 加载当前 Provider Key、已配置服务商列表并拉取可用模型
      await this.reloadApiKey();
      await this.loadConfiguredProviders();
      await this.refreshModelList();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'aboutToAppear error: %{public}s', String(err));
    }
  }

  // ── 数据辅助逻辑 ──

  private getCurrentSession(): ChatSession | undefined {
    const draft: ChatSession | undefined = this.draftSession;
    if (draft !== undefined && draft.id === this.currentSessionId) {
      return draft;
    }
    let i: number = 0;
    while (i < this.sessions.length) {
      if (this.sessions[i].id === this.currentSessionId) {
        return this.sessions[i];
      }
      i += 1;
    }
    return undefined;
  }

  // ── 分支树辅助 ──

  private findMessage(sess: ChatSession, id: string): ChatMessage | undefined {
    let i: number = 0;
    while (i < sess.messages.length) {
      if (sess.messages[i].id === id) {
        return sess.messages[i];
      }
      i += 1;
    }
    return undefined;
  }

  /** 当前激活分支的完整路径（从根沿 activeChildId 走到叶）。 */
  private activePath(): ChatMessage[] {
    const sess: ChatSession | undefined = this.getCurrentSession();
    const path: ChatMessage[] = [];
    if (!sess) {
      return path;
    }
    let cur: string = sess.activeRootId;
    let guard: number = 0;
    while (cur.length > 0 && guard < 2000) {
      guard += 1;
      const node: ChatMessage | undefined = this.findMessage(sess, cur);
      if (node === undefined) {
        break;
      }
      path.push(node);
      cur = node.activeChildId;
    }
    return path;
  }

  /** 从根到指定节点的路径（沿 parent 链回溯，与激活分支无关）。 */
  private pathToNode(sess: ChatSession, targetId: string): ChatMessage[] {
    const rev: ChatMessage[] = [];
    let cur: string = targetId;
    let guard: number = 0;
    while (cur.length > 0 && guard < 2000) {
      guard += 1;
      const node: ChatMessage | undefined = this.findMessage(sess, cur);
      if (node === undefined) {
        break;
      }
      rev.push(node);
      cur = node.parentId;
    }
    const path: ChatMessage[] = [];
    let i: number = rev.length - 1;
    while (i >= 0) {
      path.push(rev[i]);
      i -= 1;
    }
    return path;
  }

  /** 请求用历史：根到 target 的路径，仅保留有内容的 user/assistant 节点。 */
  private historyTo(sess: ChatSession, targetId: string): ChatMessage[] {
    const full: ChatMessage[] = this.pathToNode(sess, targetId);
    const out: ChatMessage[] = [];
    let i: number = 0;
    while (i < full.length) {
      const m: ChatMessage = full[i];
      if ((m.role === 'user' || m.role === 'assistant') && m.content.length > 0) {
        out.push(m);
      }
      i += 1;
    }
    return out;
  }

  /** 同一父节点下的兄弟（编辑版本/重新生成版本）；根消息的兄弟即 rootIds。 */
  private siblingsOf(sess: ChatSession, msg: ChatMessage): string[] {
    if (msg.parentId.length === 0) {
      return sess.rootIds;
    }
    const p: ChatMessage | undefined = this.findMessage(sess, msg.parentId);
    if (p === undefined) {
      return [msg.id];
    }
    return p.childIds;
  }

  private siblingIndex(sess: ChatSession, msg: ChatMessage): number {
    const sibs: string[] = this.siblingsOf(sess, msg);
    let i: number = 0;
    while (i < sibs.length) {
      if (sibs[i] === msg.id) {
        return i;
      }
      i += 1;
    }
    return 0;
  }

  private nextId(role: string): string {
    this.seq += 1;
    return `msg_${role}_${Date.now()}_${this.seq}`;
  }

  private buildMessage(role: MessageRole, content: string, parentId: string): ChatMessage {
    return {
      id: this.nextId(role),
      role: role,
      content: content,
      reasoningContent: role === 'assistant' ? '' : undefined,
      createdAt: Date.now(),
      status: 'success',
      parentId: parentId,
      childIds: [],
      activeChildId: '',
      speakerId: '',
      mentionedIds: [],
    };
  }

  /**
   * 草稿转正：首次写入消息时把草稿会话加入历史并落盘。
   * Reason: 空会话不应进历史；只有真正产生内容的会话才值得持久化。
   */
  private promoteDraftIfNeeded(sess: ChatSession): void {
    const draft: ChatSession | undefined = this.draftSession;
    if (draft === undefined || draft.id !== sess.id) {
      return;
    }
    this.draftSession = undefined;
    const nextList: ChatSession[] = [sess];
    let i: number = 0;
    while (i < this.sessions.length) {
      nextList.push(this.sessions[i]);
      i += 1;
    }
    this.sessions = nextList;
    this.saveState();
  }

  /** 将 node 挂到 parent 之下并激活该分支（parent 为空则作为新根）。 */
  private attach(sess: ChatSession, node: ChatMessage): void {
    this.promoteDraftIfNeeded(sess);
    sess.messages.push(node);
    if (node.parentId.length === 0) {
      sess.rootIds.push(node.id);
      sess.activeRootId = node.id;
      return;
    }
    const parent: ChatMessage | undefined = this.findMessage(sess, node.parentId);
    if (parent === undefined) {
      // 父节点缺失（不应发生）：退化为根，保证数据自洽。
      node.parentId = '';
      sess.rootIds.push(node.id);
      sess.activeRootId = node.id;
      return;
    }
    parent.childIds.push(node.id);
    parent.activeChildId = node.id;
  }

  private getCurrentCharacter(): CharacterCard {
    // Reason: 默认会话不绑定角色（空白），未显式选择角色时不做兜底，避免自带系统设定。
    let i: number = 0;
    while (i < this.characters.length) {
      if (this.characters[i].id === this.currentCharacterId) {
        return this.characters[i];
      }
      i += 1;
    }
    return EMPTY_CHARACTER;
  }

  private characterById(id: string): CharacterCard | undefined {
    let i: number = 0;
    while (i < this.characters.length) {
      if (this.characters[i].id === id) {
        return this.characters[i];
      }
      i += 1;
    }
    return undefined;
  }

  private characterName(id: string): string {
    const c: CharacterCard | undefined = this.characterById(id);
    return c !== undefined ? c.name : '';
  }

  /** 当前会话的群聊成员（按 participantIds 顺序）。 */
  private participantCards(): CharacterCard[] {
    const sess: ChatSession | undefined = this.getCurrentSession();
    const out: CharacterCard[] = [];
    if (!sess) {
      return out;
    }
    let i: number = 0;
    while (i < sess.participantIds.length) {
      const c: CharacterCard | undefined = this.characterById(sess.participantIds[i]);
      if (c !== undefined) {
        out.push(c);
      }
      i += 1;
    }
    return out;
  }

  private isGroupChat(): boolean {
    // [群聊下线已注释]
    /*
    const sess: ChatSession | undefined = this.getCurrentSession();
    return sess !== undefined && sess.sceneMode === 'group' && sess.participantIds.length > 0;
    */
    return false;
  }

  private toggleMention(id: string): void {
    const c: CharacterCard | undefined = this.characterById(id);
    if (c === undefined) {
      return;
    }
    const marker: string = `@${c.name}`;
    const next: string[] = [];
    let found: boolean = false;
    let i: number = 0;
    while (i < this.pendingMentions.length) {
      if (this.pendingMentions[i] === id) {
        found = true;
      } else {
        next.push(this.pendingMentions[i]);
      }
      i += 1;
    }
    if (found) {
      // 取消 @：同步去掉输入框中的标记。
      this.inputText = this.inputText.split(marker).join('').trim();
      this.pendingMentions = next;
      return;
    }
    next.push(id);
    this.pendingMentions = next;
    if (!this.inputText.includes(marker)) {
      this.inputText = this.inputText.length > 0 ? `${this.inputText} ${marker} ` : `${marker} `;
    }
  }

  private removeMention(id: string): void {
    const c: CharacterCard | undefined = this.characterById(id);
    const next: string[] = [];
    let i: number = 0;
    while (i < this.pendingMentions.length) {
      if (this.pendingMentions[i] !== id) {
        next.push(this.pendingMentions[i]);
      }
      i += 1;
    }
    this.pendingMentions = next;
    if (c !== undefined) {
      this.inputText = this.inputText.split(`@${c.name}`).join('').trim();
    }
  }

  private isCjkChar(ch: string): boolean {
    if (ch.length === 0) {
      return false;
    }
    const code: number = ch.charCodeAt(0);
    return code >= 0x4e00 && code <= 0x9fff;
  }

  /**
   * 从文本中扫描 `@名字` 补齐 @（兼容手输，不依赖选择器）。
   * Reason: 手输 @ 若不识别会落到默认发言人，内容虽合理但名字对不上造成混淆；
   *   要求名字后紧跟非中文或结尾，避免短名误吞长名（如“姚”吞“姚瑶”）。
   */
  private extractMentions(sess: ChatSession, text: string): string[] {
    const out: string[] = [];
    let i: number = 0;
    while (i < sess.participantIds.length) {
      const pid: string = sess.participantIds[i];
      const pname: string = this.characterName(pid);
      if (pname.length > 0) {
        const marker: string = `@${pname}`;
        let from: number = 0;
        let hit: boolean = false;
        while (from <= text.length - marker.length) {
          const idx: number = text.indexOf(marker, from);
          if (idx < 0) {
            break;
          }
          const after: number = idx + marker.length;
          if (after >= text.length || !this.isCjkChar(text.charAt(after))) {
            hit = true;
            break;
          }
          from = idx + 1;
        }
        if (hit && !out.includes(pid)) {
          out.push(pid);
        }
      }
      i += 1;
    }
    return out;
  }

  private mentionText(msg: ChatMessage): string {
    let out: string = '';
    let i: number = 0;
    while (i < msg.mentionedIds.length) {
      const n: string = this.characterName(msg.mentionedIds[i]);
      if (n.length > 0) {
        if (out.length > 0) {
          out += ' ';
        }
        out += `@${n}`;
      }
      i += 1;
    }
    return out;
  }

  /** 群聊默认发言人：激活分支最后一位参与者，否则首位参与者，否则 ''。 */
  private defaultSpeaker(sess: ChatSession): string {
    const path: ChatMessage[] = this.activePath();
    let i: number = path.length - 1;
    while (i >= 0) {
      const m: ChatMessage = path[i];
      if (m.role === 'assistant' && m.speakerId.length > 0 && sess.participantIds.includes(m.speakerId)) {
        return m.speakerId;
      }
      i -= 1;
    }
    if (sess.participantIds.length > 0 && this.characterById(sess.participantIds[0]) !== undefined) {
      return sess.participantIds[0];
    }
    return '';
  }

  private currentProviderSupportsThinking(): boolean {
    return isThinkingSupported(this.currentProviderId, this.currentModelId);
  }



  private openSettings(): void {
    try {
      const ctx = this.getUIContext();
      ctx.getRouter().pushUrl({ url: 'pages/Settings' }).catch((e: Error) => {
        hilog.error(DOMAIN, TAG, 'push Settings failed: %{public}s', String(e));
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'push Settings error: %{public}s', String(err));
    }
  }

  private async reloadApiKey(): Promise<void> {
    if (!this.balancePrefs) {
      return;
    }
    try {
      const keyVal: preferences.ValueType = await this.balancePrefs.get(`key_${this.currentProviderId}`, '');
      if (typeof keyVal === 'string') {
        this.currentApiKey = keyVal as string;
      } else {
        this.currentApiKey = '';
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to reload API key: %{public}s', String(err));
    }
  }

  private async refreshModelList(): Promise<void> {
    this.fetchingModels = true;
    try {
      this.availableModels = await ModelService.fetchModels(this.currentProviderId, this.currentApiKey);
      if (this.availableModels.length > 0) {
        // 校验当前选中的 model 是否在拉取列表中，不在则默认第一个
        let found: boolean = false;
        let i: number = 0;
        while (i < this.availableModels.length) {
          if (this.availableModels[i].id === this.currentModelId) {
            found = true;
            break;
          }
          i += 1;
        }
        if (!found) {
          this.currentModelId = this.availableModels[0].id;
          const cur: ChatSession | undefined = this.getCurrentSession();
          if (cur) {
            cur.modelId = this.currentModelId;
          }
          this.saveState();
        }
      } else {
        this.currentModelId = '选择模型';
      }
    } finally {
      this.fetchingModels = false;
    }
  }

  /** 仅列出本地已配置 API Key 的服务商（未填 Key 的不展示）。 */
  private async loadConfiguredProviders(): Promise<void> {
    const out: ProviderDefinition[] = [];
    if (this.balancePrefs) {
      let i: number = 0;
      while (i < PROVIDERS.length) {
        const p: ProviderDefinition = PROVIDERS[i];
        i += 1;
        try {
          const kv: preferences.ValueType = await this.balancePrefs.get(`key_${p.id}`, '');
          if (typeof kv === 'string' && (kv as string).trim().length > 0) {
            out.push(p);
          }
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'read key failed for %{public}s', p.id);
        }
      }
    }
    this.configuredProviders = out;
  }

  private async saveState(): Promise<void> {
    await ChatStorageService.saveSessions(this.sessions);
    await ChatStorageService.saveActiveSessionId(this.currentSessionId);
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 80);
  }

  // ── 流式顶部锚定滚动（Auto Scroll Top Anchor） ──
  // Business Rule: 流式生成时不跟随底部，而是把当前回答首行推到容器顶部后停住；
  //   后续 token 只增加内容高度，视口不动。用户手动滚动则暂停锚定。

  private scheduleAnchor(msgId: string): void {
    // Business Rule: 非生成态（历史浏览/图片后加载）一律不锚定；用户接管后不锚定；
    //   同一条回复只锚定一次 —— 顶部固定后内容向下生长视口自然不动，无需每 token 重推。
    //   异步时序推演：若顺序颠倒（用户先拖动、首 token 后到），userTookOver 已置 true，
    //   本次锚定跳过，用户停留在自己的位置，不会被拽回。
    if (!this.isGenerating || this.userTookOver || msgId.length === 0 || this.anchoredForMsgId === msgId) {
      return;
    }
    const targetId: string = msgId;
    setTimeout(() => {
      this.anchorStreamingReply(targetId);
    }, 0);
  }

  private anchorStreamingReply(msgId: string): void {
    if (!this.isGenerating || this.userTookOver || this.anchoredForMsgId === msgId) {
      return;
    }
    const path: ChatMessage[] = this.activePath();
    if (path.length === 0) {
      return;
    }
    const idx: number = path.length - 1;
    try {
      // ScrollAlign.START：把末条（当前回答）首行对齐容器顶部；内容不足时自动收敛为跟底。
      this.scroller.scrollToIndex(idx, false, ScrollAlign.START);
      // 锚定成功才落标记：抛异常则不记，下个 token 可重试。
      this.anchoredForMsgId = msgId;
      hilog.info(DOMAIN, TAG, 'anchored reply to index %{public}d', idx);
      this.anchorCaptured = false;
      setTimeout(() => {
        try {
          this.lastAnchorOffset = this.scroller.currentOffset().yOffset;
          this.anchorCaptured = true;
        } catch (_e) {
        }
      }, 24);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'anchor failed: %{public}s', String(err));
    }
  }

  private handleScrollIndex(start: number, end: number): void {
    const totalCount: number = this.activePath().length;
    if (totalCount <= 1) {
      if (this.showJumpBottom) {
        this.showJumpBottom = false;
      }
      return;
    }

    // end 是当前屏幕中可见的最末一条消息的索引
    const isAtBottom: boolean = end >= totalCount - 1;

    if (isAtBottom) {
      // 当前视口已显示最后一条消息（处于最底部）：立即隐藏按钮
      if (this.showJumpBottom) {
        this.showJumpBottom = false;
      }
      if (this.userTookOver) {
        this.userTookOver = false;
      }
    } else {
      // 最后一条消息已被滚出视口下方（用户往上翻阅历史）：显示“回到底部”
      if (!this.showJumpBottom) {
        this.showJumpBottom = true;
      }
      this.userTookOver = true;
    }
  }

  private onChatScrollStop(): void {
    try {
      if (this.scroller.isAtEnd()) {
        this.showJumpBottom = false;
        this.userTookOver = false;
        return;
      }
      // 条目内接管检测：onScrollIndex 只能感知条目间滚动（end < total-1），
      //   在超长单条气泡内部拖动时 end 恒为末条，必须用 offset 差值判定，
      //   否则流式中用户在回答内部的任何拖动都会被下一次锚定拽回（体感"拉不动"）。
      if (this.anchorCaptured && this.anchoredForMsgId.length > 0) {
        const cur: number = this.scroller.currentOffset().yOffset;
        const drift: number = Math.abs(cur - this.lastAnchorOffset);
        if (drift > 30) {
          this.userTookOver = true;
          this.showJumpBottom = true;
        }
      }
    } catch (_e) {
    }
  }

  private jumpToBottom(): void {
    this.userTookOver = false;
    this.showJumpBottom = false;
    this.scroller.scrollEdge(Edge.Bottom);
  }

  /** 输入框获焦：键盘弹起后最新内容可能被遮挡，把列表底到底（生成中保持锚定不动）。 */
  private onInputFocus(): void {
    if (this.isGenerating) {
      return;
    }
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 120);
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 380);
  }

  // ── 会话管理 ──

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'showToast failed: %{public}s', String(err));
    }
  }

  private async createNewSession(): Promise<void> {
    // Business Rule: 新会话默认空白、不绑定角色；角色只能在“新会话”时选择，选中后锁定。
    const newId: string = `session_${Date.now()}`;
    const newSession: ChatSession = {
      id: newId,
      title: '新对话',
      characterId: '',
      providerId: this.currentProviderId,
      modelId: this.currentModelId,
      updatedAt: Date.now(),
      messages: [],
      rootIds: [],
      activeRootId: '',
      participantIds: [],
      sceneMode: 'single',
      joinMap: {},
      userIdentityId: '',
      isPrivate: false,
    };
    this.currentCharacterId = '';

    // Business Rule: 空会话作为草稿存在，不进历史、不落盘；产生首条消息时才转正（见 promoteDraftIfNeeded）。
    this.draftSession = newSession;
    this.currentSessionId = newId;
    this.pendingMentions = [];
    this.showMentionPicker = false;
    this.anchoredForMsgId = '';
    this.anchorCaptured = false;
    this.syncMessageSource();
    this.scrollToBottom();
  }

  /**
   * 切换当前会话。
   * @param sessionId 目标任务会话 id。
   * @param closeDrawer 是否收起历史抽屉（删除会话时为 false，便于连续删除）。
   */
  private async switchSession(sessionId: string, closeDrawer: boolean = true): Promise<void> {
    // 切到正式会话时丢弃未使用的空草稿（有内容的草稿已在 attach 时转正）。
    if (this.draftSession !== undefined && this.draftSession.id !== sessionId) {
      this.draftSession = undefined;
    }
    this.currentSessionId = sessionId;
    this.pendingMentions = [];
    this.showMentionPicker = false;
    const cur: ChatSession | undefined = this.getCurrentSession();
    if (cur) {
      this.currentProviderId = cur.providerId;
      this.currentModelId = cur.modelId;
      this.currentCharacterId = cur.characterId;
      await this.reloadApiKey();
      await this.refreshModelList();
    }
    if (closeDrawer) {
      this.showDrawer = false;
    }
    this.initCollapsedReasons();
    this.anchoredForMsgId = '';
    this.anchorCaptured = false;
    this.syncMessageSource();
    await ChatStorageService.saveActiveSessionId(sessionId);
    this.scrollToBottom();
  }

  private async deleteSession(sessionId: string): Promise<void> {
    let victim: ChatSession | undefined = undefined;
    let vi: number = 0;
    while (vi < this.sessions.length) {
      if (this.sessions[vi].id === sessionId) {
        victim = this.sessions[vi];
        break;
      }
      vi += 1;
    }
    if (victim !== undefined) {
      this.dropSessionControllers(victim);
    }
    const nextList: ChatSession[] = [];
    let i: number = 0;
    while (i < this.sessions.length) {
      if (this.sessions[i].id !== sessionId) {
        nextList.push(this.sessions[i]);
      }
      i += 1;
    }
    this.sessions = nextList;

    if (this.currentSessionId === sessionId) {
      // Business Rule: 保密会话不能在删除当前会话后被自动展开（绕过认证）；
      //   优先切到最近的非保密会话，若全部为保密则新建空白会话。
      const nextId: string = this.firstNonPrivateSessionId();
      if (nextId.length > 0) {
        // Reason: 删除当前会话后必须像 switchSession 一样重同步 provider/model/key，
        //   否则头部仍显示被删会话的模型、发送会用错厂商（见 switchSession 同构逻辑）。
        //   传入 closeDrawer=false：删除后保留历史抽屉，便于用户连续删除其他会话。
        await this.switchSession(nextId, false);
      } else {
        await this.createNewSession();
      }
    }
    await this.saveState();
  }

  private firstNonPrivateSessionId(): string {
    let i: number = 0;
    while (i < this.sessions.length) {
      if (!this.sessions[i].isPrivate) {
        return this.sessions[i].id;
      }
      i += 1;
    }
    return '';
  }

  // ── 角色卡选择与编辑 ──

  private togglePendingParticipant(id: string): void {
    // Business Rule: 群聊已下线，新会话只绑定单个角色（单选）；再次点已选中的角色即取消。
    if (this.pendingParticipants.length === 1 && this.pendingParticipants[0] === id) {
      this.pendingParticipants = [];
    } else {
      this.pendingParticipants = [id];
    }
  }

  private isPendingParticipant(id: string): boolean {
    return this.pendingParticipants.includes(id);
  }

  /** 确认建联：绑定单个角色（含开场白）；群聊已下线，只支持单聊。 */
  private async confirmParticipants(): Promise<void> {
    if (this.pendingParticipants.length === 0) {
      return;
    }
    const cur: ChatSession | undefined = this.getCurrentSession();
    if (!cur) {
      this.showCharacterSheet = false;
      return;
    }
    // Business Rule: 角色与身份只能绑定一次；会话已有绑定则锁定，不可更改。
    if (cur.characterId.length > 0 || cur.participantIds.length > 0 || cur.userIdentityId.length > 0) {
      this.showCharacterSheet = false;
      this.pendingParticipants = [];
      this.toast('该会话已绑定角色，无法更改');
      return;
    }
    const ids: string[] = [];
    let i: number = 0;
    while (i < this.pendingParticipants.length) {
      if (this.characterById(this.pendingParticipants[i]) !== undefined) {
        ids.push(this.pendingParticipants[i]);
      }
      i += 1;
    }
    if (ids.length === 0) {
      return;
    }
    cur.participantIds = ids;
    // 用户身份随建联一次选定，之后锁定（与角色卡同规则）。
    let identityId: string = '';
    if (this.pendingIdentityId.length > 0 && this.identityById(this.pendingIdentityId) !== undefined) {
      identityId = this.pendingIdentityId;
    }
    cur.userIdentityId = identityId;
    // [群聊下线已注释] 始终进入单聊模式
    /*
    if (ids.length >= 2) {
      cur.sceneMode = 'group';
      cur.characterId = '';
      this.currentCharacterId = '';
    } else {
    */
    cur.sceneMode = 'single';
    cur.characterId = ids[0];
    this.currentCharacterId = ids[0];
    const c: CharacterCard | undefined = this.characterById(ids[0]);
    if (c !== undefined && cur.messages.length === 0 && c.firstMessage.trim().length > 0) {
      const welcomeMsg: ChatMessage = this.buildMessage('assistant', c.firstMessage, '');
      this.attach(cur, welcomeMsg);
    }
    // }
    this.pendingParticipants = [];
    this.pendingIdentityId = '';
    this.showCharacterSheet = false;
    this.rebuildSessionReference();
    await this.saveState();
    this.scrollToBottom();
  }

  private openCharEdit(char?: CharacterCard): void {
    if (char) {
      this.editingCharId = char.id;
      this.editingCharName = char.name;
      this.editingCharPrompt = char.systemPrompt;
      this.editingCharFirstMsg = char.firstMessage;
      this.editingCharTemp = char.temperature;
    } else {
      this.editingCharId = '';
      this.editingCharName = '';
      this.editingCharPrompt = '你是一个人工智能助手。';
      this.editingCharFirstMsg = '你好！有什么我可以为你效劳的？';
      this.editingCharTemp = 0.7;
    }
    this.showCharEditDialog = true;
  }

  private async saveCharacterEdit(): Promise<void> {
    if (this.editingCharName.trim().length === 0) {
      return;
    }
    const nextChars: CharacterCard[] = [];
    const isNew: boolean = this.editingCharId.length === 0;

    let i: number = 0;
    while (i < this.characters.length) {
      const c: CharacterCard = this.characters[i];
      if (c.id === this.editingCharId) {
        const updated: CharacterCard = {
          id: c.id,
          name: this.editingCharName.trim(),
          avatarIcon: c.avatarIcon,
          description: c.description,
          systemPrompt: this.editingCharPrompt.trim(),
          firstMessage: this.editingCharFirstMsg.trim(),
          temperature: this.editingCharTemp,
          createdAt: c.createdAt
        };
        nextChars.push(updated);
      } else {
        nextChars.push(c);
      }
      i += 1;
    }

    if (isNew) {
      const created: CharacterCard = {
        id: `char_${Date.now()}`,
        name: this.editingCharName.trim(),
        avatarIcon: 'custom',
        description: '',
        systemPrompt: this.editingCharPrompt.trim(),
        firstMessage: this.editingCharFirstMsg.trim(),
        temperature: this.editingCharTemp,
        createdAt: Date.now()
      };
      nextChars.unshift(created);
      this.currentCharacterId = created.id;
      // 选择模式下，新建角色直接作为本次建联选择（单选）。
      if (this.characterSheetMode === 'select') {
        this.pendingParticipants = [created.id];
      }
    }

    this.characters = nextChars;
    this.showCharEditDialog = false;
    await ChatStorageService.saveCharacters(this.characters);
  }

  // ── 历史会话长按操作 ──

  private openSessActions(id: string): void {
    if (this.isGenerating) {
      return;
    }
    this.sessActionId = id;
  }

  private closeSessActions(): void {
    this.sessActionId = '';
  }

  private sessActionTitle(): string {
    const target: ChatSession | undefined = this.sessionById(this.sessActionId);
    return target !== undefined ? target.title : '';
  }

  private sessionById(id: string): ChatSession | undefined {
    let i: number = 0;
    while (i < this.sessions.length) {
      if (this.sessions[i].id === id) {
        return this.sessions[i];
      }
      i += 1;
    }
    return undefined;
  }

  private sessActionIsPrivate(): boolean {
    const target: ChatSession | undefined = this.sessionById(this.sessActionId);
    return target !== undefined ? target.isPrivate : false;
  }

  /** 从历史抽屉打开会话：保密会话需先通过人脸/指纹认证。 */
  private async openSessionWithPrivacy(sess: ChatSession): Promise<void> {
    if (sess.isPrivate) {
      const ok: boolean = await AuthService.authenticate('解锁保密对话');
      if (!ok) {
        this.toast('身份验证未通过，无法打开该对话');
        return;
      }
    }
    await this.switchSession(sess.id);
  }

  /**
   * 切换会话保密标记。
   * Business Rule: 关闭保密必须重新通过人脸/指纹认证，否则可在不打开会话的前提下
   *   直接解除保密再打开，形成绕过路径；开启保密无需认证。
   */
  private async toggleSessPrivacy(): Promise<void> {
    const target: ChatSession | undefined = this.sessionById(this.sessActionId);
    if (target === undefined) {
      this.sessActionId = '';
      return;
    }
    if (target.isPrivate) {
      const ok: boolean = await AuthService.authenticate('取消保密需要验证身份');
      if (!ok) {
        this.toast('身份验证未通过');
        return;
      }
      target.isPrivate = false;
      this.toast('已取消保密');
    } else {
      target.isPrivate = true;
      this.toast('已设为保密会话，下次打开需验证身份');
    }
    this.sessActionId = '';
    this.rebuildSessionReference();
    await this.saveState();
  }

  private beginRename(): void {
    const title: string = this.sessActionTitle();
    if (title.length === 0) {
      this.sessActionId = '';
      return;
    }
    // 保留 sessActionId 作为重命名目标；菜单用 showRenameDialog 隐藏。
    this.renameText = title;
    this.showRenameDialog = true;
  }

  private cancelRename(): void {
    this.showRenameDialog = false;
    this.renameText = '';
    this.sessActionId = '';
  }

  private confirmRename(): void {
    const text: string = this.renameText.trim();
    if (text.length === 0) {
      return;
    }
    let i: number = 0;
    while (i < this.sessions.length) {
      if (this.sessions[i].id === this.sessActionId) {
        this.sessions[i].title = text;
        break;
      }
      i += 1;
    }
    this.showRenameDialog = false;
    this.renameText = '';
    this.sessActionId = '';
    this.rebuildSessionReference();
    this.saveState();
  }

  private askDeleteSession(): void {
    // 保留 sessActionId 作为删除目标；菜单用 showDeleteConfirm 隐藏。
    this.showDeleteConfirm = true;
  }

  private cancelDeleteSession(): void {
    this.showDeleteConfirm = false;
    this.sessActionId = '';
  }

  private async confirmDeleteSession(): Promise<void> {
    const id: string = this.sessActionId;
    this.showDeleteConfirm = false;
    this.sessActionId = '';
    if (id.length === 0) {
      return;
    }
    await this.deleteSession(id);
  }

  private openCharActions(id: string): void {
    this.charActionId = id;
  }

  private closeCharActions(): void {
    this.charActionId = '';
  }

  private charActionCard(): CharacterCard | undefined {
    let i: number = 0;
    while (i < this.characters.length) {
      if (this.characters[i].id === this.charActionId) {
        return this.characters[i];
      }
      i += 1;
    }
    return undefined;
  }

  private charActionName(): string {
    const c: CharacterCard | undefined = this.charActionCard();
    return c !== undefined ? c.name : '';
  }

  private editFromCharActions(): void {
    const c: CharacterCard | undefined = this.charActionCard();
    this.charActionId = '';
    if (c !== undefined) {
      this.openCharEdit(c);
    }
  }

  private askDeleteChar(): void {
    // 保留 charActionId 作为删除目标；菜单用 showCharDeleteConfirm 隐藏。
    this.showCharDeleteConfirm = true;
  }

  private cancelDeleteChar(): void {
    this.showCharDeleteConfirm = false;
    this.charActionId = '';
  }

  private async confirmDeleteChar(): Promise<void> {
    const id: string = this.charActionId;
    this.showCharDeleteConfirm = false;
    this.charActionId = '';
    if (id.length === 0) {
      return;
    }
    const kept: CharacterCard[] = [];
    let i: number = 0;
    while (i < this.characters.length) {
      if (this.characters[i].id !== id) {
        kept.push(this.characters[i]);
      }
      i += 1;
    }
    this.characters = kept;
    if (this.currentCharacterId === id) {
      this.currentCharacterId = '';
      const cur: ChatSession | undefined = this.getCurrentSession();
      if (cur) {
        cur.characterId = '';
      }
    }
    await ChatStorageService.saveCharacters(this.characters);
    this.rebuildSessionReference();
    await this.saveState();
  }

  // ── 用户身份卡 ──

  private identityById(id: string): UserIdentityCard | undefined {
    let i: number = 0;
    while (i < this.identities.length) {
      if (this.identities[i].id === id) {
        return this.identities[i];
      }
      i += 1;
    }
    return undefined;
  }

  /** 当前会话的用户身份名；无身份返回 ''。 */
  private currentIdentityName(): string {
    const sess: ChatSession | undefined = this.getCurrentSession();
    if (!sess || sess.userIdentityId.length === 0) {
      return '';
    }
    const idn: UserIdentityCard | undefined = this.identityById(sess.userIdentityId);
    return idn !== undefined ? idn.name : '';
  }

  private openIdentityEdit(idn?: UserIdentityCard): void {
    if (idn) {
      this.editingIdentityId = idn.id;
      this.editingIdentityName = idn.name;
      this.editingIdentityPersona = idn.persona;
    } else {
      this.editingIdentityId = '';
      this.editingIdentityName = '';
      this.editingIdentityPersona = '';
    }
    this.showIdentityEdit = true;
  }

  private cancelIdentityEdit(): void {
    this.showIdentityEdit = false;
    this.editingIdentityId = '';
    this.editingIdentityName = '';
    this.editingIdentityPersona = '';
  }

  private async saveIdentityEdit(): Promise<void> {
    if (this.editingIdentityName.trim().length === 0) {
      return;
    }
    const next: UserIdentityCard[] = [];
    let isNew: boolean = this.editingIdentityId.length === 0;
    let i: number = 0;
    while (i < this.identities.length) {
      const c: UserIdentityCard = this.identities[i];
      if (c.id === this.editingIdentityId) {
        next.push({
          id: c.id,
          name: this.editingIdentityName.trim(),
          persona: this.editingIdentityPersona.trim(),
          createdAt: c.createdAt,
        });
      } else {
        next.push(c);
      }
      i += 1;
    }
    if (isNew) {
      next.unshift({
        id: `identity_${Date.now()}`,
        name: this.editingIdentityName.trim(),
        persona: this.editingIdentityPersona.trim(),
        createdAt: Date.now(),
      });
    }
    this.identities = next;
    this.showIdentityEdit = false;
    await ChatStorageService.saveIdentities(this.identities);
  }

  private askDeleteIdentity(id: string): void {
    this.identityActionId = id;
    this.showIdentityDeleteConfirm = true;
  }

  private cancelDeleteIdentity(): void {
    this.showIdentityDeleteConfirm = false;
    this.identityActionId = '';
  }

  private identityActionName(): string {
    const c: UserIdentityCard | undefined = this.identityById(this.identityActionId);
    return c !== undefined ? c.name : '';
  }

  private async confirmDeleteIdentity(): Promise<void> {
    const id: string = this.identityActionId;
    this.showIdentityDeleteConfirm = false;
    this.identityActionId = '';
    if (id.length === 0) {
      return;
    }
    const kept: UserIdentityCard[] = [];
    let i: number = 0;
    while (i < this.identities.length) {
      if (this.identities[i].id !== id) {
        kept.push(this.identities[i]);
      }
      i += 1;
    }
    this.identities = kept;
    // 被删身份若正被会话引用，引用悬空按无身份处理（lookup 兜底）。
    await ChatStorageService.saveIdentities(this.identities);
    this.rebuildSessionReference();
  }

  // ── 发送与流式输出 ──

  private rebuildSessionReference(): void {
    const list: ChatSession[] = [];
    let i: number = 0;
    while (i < this.sessions.length) {
      list.push(this.sessions[i]);
      i += 1;
    }
    this.sessions = list;
    this.syncMessageSource();
  }

  /**
   * 单条消息的渲染键：ForEach 时代决定同 key 复用旧快照、异 key 重建；
   * LazyForEach 时代同时作为数据源增量刷新的判据（见 ChatMessageDataSource.sync）。
   * Business Rule: 有正文后恒为 'C' 稳定实例，流式增量交给 MarkdownController，不重建防闪。
   */
  private msgRenderKey(msg: ChatMessage): string {
    const collapsed: string = this.isReasonCollapsed(msg.id) ? 'c' : 'e';
    return `${msg.id}_${msg.status}_${collapsed}_${this.reasonVersion}_${Math.round(this.appFontScale * 100)}_${this.appDark ? 'd' : 'l'}_${this.msgContentPhaseKey(msg)}`;
  }

  /** 把当前激活分支与渲染键推给 LazyForEach 数据源（结构性/局部刷新由数据源内部判定）。 */
  private syncMessageSource(): void {
    const path: ChatMessage[] = this.activePath();
    const keys: string[] = [];
    let i: number = 0;
    while (i < path.length) {
      keys.push(this.msgRenderKey(path[i]));
      i += 1;
    }
    this.msgSource.sync(path, keys);
  }

  // ── Markdown 渲染接入（FluidMarkdown） ──

  private isDarkMode(): boolean {
    return this.appDark;
  }

  /**
   * Reason: ForEach 同 key 会复用旧快照不刷新，流式期必须让相关条目重建。
   *   正文未出现前把思考字数纳入 key（'R<n>'），使思考文本随 token 逐帧刷新
   *   （此时 MarkdownBody 尚未挂载，重建无副作用）；正文一旦出现即切换为固定的 'C'，
   *   key 从此稳定，MarkdownBody 只挂载一次、后续增量由 controller 驱动（不重建防闪）。
   * Business Rule: 有正文后思考内容按约定冻结，key 不再随思考长度变化。
   */
  private msgContentPhaseKey(msg: ChatMessage): string {
    if (msg.content.length > 0) {
      return 'C';
    }
    const rLen: number = msg.reasoningContent ? msg.reasoningContent.length : 0;
    return rLen > 0 ? `R${rLen}` : 'E';
  }

  /** 仅当消息仍在流式且驱动器存活时走 Typing；否则一律 Normal（防僵尸流式）。 */
  private isLiveStreaming(msg: ChatMessage): boolean {
    return msg.status === 'streaming' && this.mdControllers.has(msg.id);
  }

  /** 思考区内嵌 Scroller（懒建随消息 id 存活，删会话时清理，防泄漏）。 */
  private thinkScrollerFor(id: string): Scroller {
    const existed: Scroller | undefined = this.thinkScrollers.get(id);
    if (existed !== undefined) {
      return existed;
    }
    const created: Scroller = new Scroller();
    this.thinkScrollers.set(id, created);
    return created;
  }

  /**
   * 思考区跟底：仅当内滚动已在底部时跟随（用户上翻查看旧思考时不动，
   *   否则就是外层锚定"拽回" bug 在小框里的重演）。
   */
  private followThinking(msgId: string): void {
    const sc: Scroller | undefined = this.thinkScrollers.get(msgId);
    if (sc === undefined) {
      return;
    }
    try {
      // Reason: 思考文本经 ForEach key（R<n>）变化会重建条目，内嵌 Scroll 的滚动位置随之重置，
      //   isAtEnd() 判断会误判为"不在底部"而放弃跟随，导致长思考沉底不可见。
      //   生成期间（本方法仅在 onToken 路径被调）统一贴底即可；生成结束不再调用，用户可自由翻阅。
      sc.scrollEdge(Edge.Bottom);
    } catch (_e) {
    }
  }

  /** 库 Typing 就绪：只记标记，Begin 由下一拍 driveMarkdown 用累计文本发出（无损）。 */
  private onMarkdownReady(msgId: string): void {
    // 完成/停止后 controller 已删，天然忽略迟到就绪。
    if (this.mdControllers.has(msgId) && !this.mdTypingReady.includes(msgId)) {
      this.mdTypingReady.push(msgId);
    }
  }

  /**
   * 流式刷新节流（~8fps）：driveMarkdown + 整表重建 + 思考跟随统一压到 tick。
   * Reason: token 可达百 Hz，直驱全表重建会压垮 UI 线程致刷新合并成"一次性"；
   *   喂给库的永远是累计文本，合并无损。完成/停止走直接重建，不经此门。
   */
  private refreshStreamView(msg: ChatMessage): void {
    const now: number = Date.now();
    if (now - this.lastRefreshAt < 120) {
      if (!this.refreshPending) {
        this.refreshPending = true;
        const targetId: string = msg.id;
        setTimeout(() => {
          this.refreshPending = false;
          this.lastRefreshAt = Date.now();
          const target: ChatMessage | undefined = this.findLiveMessage(targetId);
          if (target !== undefined) {
            this.driveMarkdown(target);
          }
          this.rebuildSessionReference();
          this.followThinking(targetId);
        }, 120);
      }
      return;
    }
    this.lastRefreshAt = now;
    this.driveMarkdown(msg);
    this.rebuildSessionReference();
    this.followThinking(msg.id);
  }

  /** 跨会话按 id 找存活消息（节流 tick 触发时原对象引用仍有效，此为兜底）。 */
  private findLiveMessage(id: string): ChatMessage | undefined {
    let si: number = 0;
    while (si < this.sessions.length) {
      const sess: ChatSession = this.sessions[si];
      let mi: number = 0;
      while (mi < sess.messages.length) {
        if (sess.messages[mi].id === id) {
          return sess.messages[mi];
        }
        mi += 1;
      }
      si += 1;
    }
    return undefined;
  }
  private driveMarkdown(msg: ChatMessage): void {
    // 库契约：update 只能在 TypingReady 之后；就绪前跳过（不记 begun），就绪后首帧即 Begin。
    if (!this.mdTypingReady.includes(msg.id)) {
      return;
    }
    const ctl: MarkdownController | undefined = this.mdControllers.get(msg.id);
    if (ctl === undefined) {
      return;
    }
    const full: string = MarkdownService.rewriteCitations(msg.content);
    try {
      if (!this.mdTypingBegun.includes(msg.id)) {
        this.mdTypingBegun.push(msg.id);
        ctl.typing.update(full, ETypingMode.Begin, true);
      } else {
        ctl.typing.update(full, ETypingMode.Append, true);
      }
    } catch (_e) {
    }
  }

  /** 收尾：正常结束刷 End 帧吐完 pacing 队列；中断则直接停。随后删驱动器防泄漏。 */
  private finishMarkdown(msg: ChatMessage, stopped: boolean): void {
    const ctl: MarkdownController | undefined = this.mdControllers.get(msg.id);
    // 未 Begin（就绪前即完成）则不发 End，无会话可收尾。
    if (ctl !== undefined && !stopped && this.mdTypingBegun.includes(msg.id)) {
      try {
        ctl.typing.update(MarkdownService.rewriteCitations(msg.content), ETypingMode.End, false);
      } catch (_e) {
      }
    }
    this.mdControllers.delete(msg.id);
    this.mdTypingReady = this.withoutId(this.mdTypingReady, msg.id);
    this.mdTypingBegun = this.withoutId(this.mdTypingBegun, msg.id);
  }

  private withoutId(list: string[], id: string): string[] {
    const kept: string[] = [];
    let i: number = 0;
    while (i < list.length) {
      if (list[i] !== id) {
        kept.push(list[i]);
      }
      i += 1;
    }
    return kept;
  }

  private dropSessionControllers(sess: ChatSession): void {
    let i: number = 0;
    while (i < sess.messages.length) {
      const id: string = sess.messages[i].id;
      this.mdControllers.delete(id);
      this.thinkScrollers.delete(id);
      i += 1;
    }
    const kept: string[] = [];
    let j: number = 0;
    while (j < this.mdTypingBegun.length) {
      if (!this.mdControllers.has(this.mdTypingBegun[j])) {
        // 已删驱动的 begun 标记一并清理（has 判空，无额外查找）。
      } else {
        kept.push(this.mdTypingBegun[j]);
      }
      j += 1;
    }
    this.mdTypingBegun = kept;
    const keptReady: string[] = [];
    let k: number = 0;
    while (k < this.mdTypingReady.length) {
      if (this.mdControllers.has(this.mdTypingReady[k])) {
        keptReady.push(this.mdTypingReady[k]);
      }
      k += 1;
    }
    this.mdTypingReady = keptReady;
  }

  private onMarkdownLink(href: string): void {
    const action: MdClickAction = MarkdownService.routeHref(href);
    if (action.kind === 'cite') {
      // @DeferDecision: 引用来源列表待模型侧提供 URL，当前仅落 toast + 日志不断链。
      this.toast(`引用来源 [${action.index}]（来源列表待模型侧提供）`);
      hilog.info(DOMAIN, TAG, 'citation clicked: %{public}d', action.index);
      return;
    }
    if (action.kind === 'open') {
      this.openExternalUrl(action.target);
      return;
    }
    this.toast('该链接暂不支持打开');
    hilog.warn(DOMAIN, TAG, 'blocked unsafe link');
  }

  private onMarkdownImage(src: string): void {
    this.previewImage = src;
  }

  private async openExternalUrl(url: string): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await hostCtx.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url,
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'open url failed: %{public}s', String(err));
      this.toast('无法打开链接');
    }
  }

  private canSend(): boolean {
    if (this.currentApiKey.trim().length === 0) {
      this.noticeText = `未配置 [${this.getProviderName(this.currentProviderId)}] 的 API Key，请先在设置中添加`;
      return false;
    }
    if (this.currentModelId.trim().length === 0 || this.currentModelId === '选择模型') {
      this.noticeText = '请先点击右上角选择一个有效模型';
      return false;
    }
    return true;
  }

  private currentLeafId(sess: ChatSession): string {
    const path: ChatMessage[] = this.activePath();
    return path.length > 0 ? path[path.length - 1].id : '';
  }

  private async sendMessage(): Promise<void> {
    const text: string = this.inputText.trim();
    if (text.length === 0 || this.isGenerating) {
      return;
    }

    const sess: ChatSession | undefined = this.getCurrentSession();
    if (!sess) {
      return;
    }
    if (!this.canSend()) {
      return;
    }

    this.inputText = '';
    this.inputExpanded = false;
    this.noticeText = '';

    if (sess.title === '新对话') {
      sess.title = text.length > 14 ? `${text.substring(0, 14)}...` : text;
    }

    // 新消息挂在当前激活分支的叶节点之下；@ 以选择器+文本扫描双通道校对后落库。
    const parentId: string = this.currentLeafId(sess);
    const userMsg: ChatMessage = this.buildMessage('user', text, parentId);
    let mi: number = 0;
    while (mi < this.pendingMentions.length) {
      const mid: string = this.pendingMentions[mi];
      const mName: string = this.characterName(mid);
      if (mName.length > 0 && text.includes(`@${mName}`)) {
        userMsg.mentionedIds.push(mid);
      }
      mi += 1;
    }
    if (sess.sceneMode === 'group') {
      const scanned: string[] = this.extractMentions(sess, text);
      let si: number = 0;
      while (si < scanned.length) {
        if (!userMsg.mentionedIds.includes(scanned[si])) {
          userMsg.mentionedIds.push(scanned[si]);
        }
        si += 1;
      }
    }
    this.pendingMentions = [];
    this.attach(sess, userMsg);
    sess.updatedAt = Date.now();
    this.rebuildSessionReference();
    this.scrollToBottom();

    // [群聊下线已注释] 无群聊模式，一律走单聊生成
    /*
    if (sess.sceneMode === 'group' && sess.participantIds.length > 0) {
      this.isGenerating = true;
      try {
        await this.sendGroup(sess, userMsg);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'sendGroup failed: %{public}s', String(err));
      } finally {
        this.isGenerating = false;
        this.rebuildSessionReference();
      }
      return;
    }
    */
    this.generateReply(sess, userMsg, this.getCurrentCharacter());
  }

  /* [群聊下线已注释]
  private async sendGroup(sess: ChatSession, userMsg: ChatMessage): Promise<void> {
    // 群聊路由与链式生成代码已下线
  }
  */

  /** 为 parentMsg 挂 assistant 占位并流式生成；历史取根->parentMsg 的分支路径。 */
  private generateReply(sess: ChatSession, parentMsg: ChatMessage, speaker: CharacterCard): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      const assistantMsg: ChatMessage = this.buildMessage('assistant', '', parentMsg.id);
      assistantMsg.status = 'streaming';
      assistantMsg.speakerId = speaker.id;
      this.attach(sess, assistantMsg);
      sess.updatedAt = Date.now();
      this.rebuildSessionReference();
      this.isGenerating = true;
      // 新一轮生成：重置锚定，先跟随到底，再由锚定逻辑把首行推顶（首 token 到达时一次性执行）。
      this.userTookOver = false;
      this.showJumpBottom = false;
      this.anchorCaptured = false;
      this.anchoredForMsgId = '';
      this.reasonChunkCount = 0;
      this.contentChunkCount = 0;
      this.lastRefreshAt = 0;
      this.refreshPending = false;
      this.scrollToBottom();

      const finish = (): void => {
        this.resolveCurrent = undefined;
        resolve();
      };
      this.resolveCurrent = finish;

      // Reason: 历史仅取该分支路径（historyTo 沿 parent 链），编辑/切分支后互不污染。
      const rawHistory: ChatMessage[] = this.historyTo(sess, parentMsg.id);
      const personaName: string = this.currentIdentityName();
      const history: ChatMessage[] = [];

      let hi: number = 0;
      while (hi < rawHistory.length) {
        const h: ChatMessage = rawHistory[hi];
        let content: string = h.content;
        if (h.role === 'user' && personaName.length > 0 && content.length > 0) {
          content = `${personaName}：${content}`;
        }
        const tagged: ChatMessage = {
          id: h.id,
          role: h.role,
          content: content,
          reasoningContent: h.reasoningContent,
          createdAt: h.createdAt,
          status: h.status,
          errorMessage: h.errorMessage,
          parentId: h.parentId,
          childIds: [],
          activeChildId: h.activeChildId,
          speakerId: h.speakerId,
          mentionedIds: [],
        };
        history.push(tagged);
        hi += 1;
      }

      const thinkingStartTime: number = Date.now();
      let thinkingEndTime: number = 0;

      // 流式 Markdown 驱动器：随本轮回复创建，随完成/失败/停止销毁。
      const mdCtl: MarkdownController = new MarkdownController({});
      this.mdControllers.set(assistantMsg.id, mdCtl);

      const callbacks: StreamCallbacks = {
        onToken: (token: string, reasoningChunk?: string) => {
          if (reasoningChunk && reasoningChunk.length > 0) {
            assistantMsg.reasoningContent = (assistantMsg.reasoningContent || '') + reasoningChunk;
            this.reasonChunkCount += 1;
            // 思考生成中：确保不处于折叠状态，保持展开
            const cIdx: number = this.collapsedReasons.indexOf(assistantMsg.id);
            if (cIdx >= 0) {
              this.collapsedReasons.splice(cIdx, 1);
            }
            // 思考跟随在节流 tick 内统一做（refreshStreamView），此处只做数据追加。
          }
          if (token && token.length > 0) {
            this.contentChunkCount += 1;
            if (thinkingEndTime === 0 && assistantMsg.reasoningContent && assistantMsg.reasoningContent.length > 0) {
              thinkingEndTime = Date.now();
              const elapsedSec: number = Math.max(1, Math.round((thinkingEndTime - thinkingStartTime) / 1000));
              assistantMsg.thinkingDuration = elapsedSec;
              // 思考完毕，正文开始：自动折叠为已思考
              // Reason: 只 push 不 bump reasonVersion —— 折叠态 e→c 已在 ForEach key 中，
              //   本条目照常刷新；bump 会改全表 key 致 List 整表重建、滚动归零（流式中跳顶）。
              if (this.autoCollapseThinking) {
                if (!this.collapsedReasons.includes(assistantMsg.id)) {
                  this.collapsedReasons.push(assistantMsg.id);
                }
              }
            }
            assistantMsg.content += token;
          }
          // 高频刷新节流：driveMarkdown/重建/跟随统一压到 tick（~8fps），累计文本无损。
          this.refreshStreamView(assistantMsg);
          // 顶部锚定：首 token 把回答首行推到容器顶部即停住（单条只一次），而非持续跟底。
          this.scheduleAnchor(assistantMsg.id);
        },
        onComplete: () => {
          assistantMsg.status = 'success';
          this.isGenerating = false;
          this.finishMarkdown(assistantMsg, false);
          const rLen: number = assistantMsg.reasoningContent ? assistantMsg.reasoningContent.length : 0;
          hilog.info(DOMAIN, TAG, 'stream done: reasoning %{public}d chunks/%{public}d chars, content %{public}d chunks/%{public}d chars',
            this.reasonChunkCount, rLen, this.contentChunkCount, assistantMsg.content.length);
          if (assistantMsg.reasoningContent && assistantMsg.reasoningContent.length > 0) {
            if (!assistantMsg.thinkingDuration) {
              const dur: number = Math.max(1, Math.round(((thinkingEndTime > 0 ? thinkingEndTime : Date.now()) - thinkingStartTime) / 1000));
              assistantMsg.thinkingDuration = dur;
            }
            if (this.autoCollapseThinking) {
              if (!this.collapsedReasons.includes(assistantMsg.id)) {
                this.collapsedReasons.push(assistantMsg.id);
              }
            }
          }
          // Reason: 此处不 bump reasonVersion —— status streaming→success 已在 ForEach key 中，
          //   本条目会重建并切到 Normal 全量渲染；bump 会改全表 key 致 List 整表重建、
          //   滚动归零到顶部、新回复沉底不可见（体感"回复消失"）。
          //   注意 toggleReason 的 bump 必须保留：collapsedReasons 非 @State，
          //   那里靠 reasonVersion 本身触发渲染（本两处都有 rebuildSessionReference 兜底）。
          this.rebuildSessionReference();
          this.saveState();
          finish();
        },
        onError: (errMsg: string) => {
          assistantMsg.status = 'error';
          assistantMsg.errorMessage = errMsg;
          this.isGenerating = false;
          this.finishMarkdown(assistantMsg, true);
          this.rebuildSessionReference();
          this.saveState();
          finish();
        }
      };

      this.abortStreaming = ChatService.streamChat({
        providerId: this.currentProviderId,
        apiKey: this.currentApiKey,
        model: this.currentModelId,
        temperature: speaker.temperature,
        messages: history,
        systemPrompt: this.systemPromptFor(sess, speaker),
        enableThinking: this.enableThinking,
        reasoningEffort: 'high'
      }, callbacks);
    });
  }

  /**
   * 构建单聊系统提示词：以角色自身人设设定为主体，融入用户剧中身份。
   */
  private systemPromptFor(sess: ChatSession, speaker: CharacterCard): string {
    const base: string = speaker.systemPrompt.trim();

    let userPersonaBlock: string = '';
    if (sess.userIdentityId.length > 0) {
      const idn: UserIdentityCard | undefined = this.identityById(sess.userIdentityId);
      if (idn !== undefined) {
        userPersonaBlock = idn.persona.trim().length > 0 ?
          `【与你对话的用户在剧中身份】：「${idn.name}」—— ${idn.persona.trim()}` :
          `【与你对话的用户在剧中身份】：「${idn.name}」`;
      }
    }

    let prompt: string = base;
    if (userPersonaBlock.length > 0) {
      prompt = prompt.length > 0 ? `${prompt}\n\n${userPersonaBlock}` : userPersonaBlock;
    }
    return prompt;
  }

  // ── 消息编辑 / 重新生成 / 分支切换 ──

  private openMsgActions(msgId: string): void {
    if (this.isGenerating) {
      return;
    }
    this.actionMsgId = msgId;
  }

  private closeMsgActions(): void {
    this.actionMsgId = '';
  }

  private actionMsg(): ChatMessage | undefined {
    const sess: ChatSession | undefined = this.getCurrentSession();
    if (!sess || this.actionMsgId.length === 0) {
      return undefined;
    }
    return this.findMessage(sess, this.actionMsgId);
  }

  /** 长按后点「编辑并重发」：打开编辑框并预填原文。 */
  private beginEdit(): void {
    const msg: ChatMessage | undefined = this.actionMsg();
    if (msg === undefined) {
      this.closeMsgActions();
      return;
    }
    this.editMsgId = msg.id;
    this.editMsgText = msg.content;
    this.actionMsgId = '';
    this.showEditDialog = true;
  }

  private cancelEdit(): void {
    this.showEditDialog = false;
    this.editMsgId = '';
    this.editMsgText = '';
  }

  /** 提交编辑：在原文同父下新建兄弟 user 节点（保留原分支），并生成新回复。 */
  private async confirmEdit(): Promise<void> {
    const sess: ChatSession | undefined = this.getCurrentSession();
    const newText: string = this.editMsgText.trim();
    if (!sess || this.editMsgId.length === 0 || newText.length === 0) {
      return;
    }
    if (!this.canSend()) {
      this.showEditDialog = false;
      return;
    }
    const original: ChatMessage | undefined = this.findMessage(sess, this.editMsgId);
    if (original === undefined) {
      this.cancelEdit();
      return;
    }
    const userMsg: ChatMessage = this.buildMessage('user', newText, original.parentId);
    let oi: number = 0;
    while (oi < original.mentionedIds.length) {
      userMsg.mentionedIds.push(original.mentionedIds[oi]);
      oi += 1;
    }
    this.attach(sess, userMsg);
    sess.updatedAt = Date.now();
    this.showEditDialog = false;
    this.editMsgId = '';
    this.editMsgText = '';
    this.rebuildSessionReference();
    this.scrollToBottom();
    /* [群聊下线已注释]
    if (sess.sceneMode === 'group' && sess.participantIds.length > 0) {
      await this.sendGroup(sess, userMsg);
      return;
    }
    */
    this.generateReply(sess, userMsg, this.getCurrentCharacter());
  }

  /** 长按 assistant 点「重新生成」：同一 user 下新建助手兄弟分支。 */
  private async regenerate(): Promise<void> {
    const sess: ChatSession | undefined = this.getCurrentSession();
    const assistantMsg: ChatMessage | undefined = this.actionMsg();
    this.closeMsgActions();
    if (!sess || assistantMsg === undefined || assistantMsg.role !== 'assistant') {
      return;
    }
    if (!this.canSend()) {
      return;
    }
    const userMsg: ChatMessage | undefined = this.findMessage(sess, assistantMsg.parentId);
    if (userMsg === undefined) {
      return;
    }
    let speaker: CharacterCard = this.getCurrentCharacter();
    const bySpeaker: CharacterCard | undefined = this.characterById(assistantMsg.speakerId);
    if (bySpeaker !== undefined) {
      speaker = bySpeaker;
    }
    this.generateReply(sess, userMsg, speaker);
  }

  private switchBranch(msg: ChatMessage, delta: number): void {
    if (this.isGenerating) {
      return;
    }
    const sess: ChatSession | undefined = this.getCurrentSession();
    if (!sess) {
      return;
    }
    const sibs: string[] = this.siblingsOf(sess, msg);
    if (sibs.length <= 1) {
      return;
    }
    let idx: number = this.siblingIndex(sess, msg);
    idx += delta;
    if (idx < 0 || idx >= sibs.length) {
      return;
    }
    const targetId: string = sibs[idx];
    if (msg.parentId.length === 0) {
      sess.activeRootId = targetId;
    } else {
      const parent: ChatMessage | undefined = this.findMessage(sess, msg.parentId);
      if (parent === undefined) {
        return;
      }
      parent.activeChildId = targetId;
    }
    sess.updatedAt = Date.now();
    this.rebuildSessionReference();
    this.saveState();
    this.scrollToBottom();
  }

  private stopGenerating(): void {
    if (this.isGenerating) {
      this.abortStreaming();
      this.isGenerating = false;
      const path: ChatMessage[] = this.activePath();
      if (path.length > 0) {
        const lastMsg: ChatMessage = path[path.length - 1];
        if (lastMsg.status === 'streaming') {
          lastMsg.status = 'success';
          const ctl: MarkdownController | undefined = this.mdControllers.get(lastMsg.id);
          if (ctl !== undefined) {
            try {
              ctl.typing.stop();
            } catch (_e) {
            }
          }
          this.finishMarkdown(lastMsg, true);
        }
      }
      this.rebuildSessionReference();
      this.saveState();
      if (this.resolveCurrent !== undefined) {
        const done: () => void = this.resolveCurrent;
        this.resolveCurrent = undefined;
        done();
      }
    }
  }

  private branchCount(msg: ChatMessage): number {
    const sess: ChatSession | undefined = this.getCurrentSession();
    return sess ? this.siblingsOf(sess, msg).length : 1;
  }

  private branchIndex(msg: ChatMessage): number {
    const sess: ChatSession | undefined = this.getCurrentSession();
    return sess ? this.siblingIndex(sess, msg) : 0;
  }

  private isReasonCollapsed(id: string): boolean {
    return this.collapsedReasons.includes(id);
  }

  private isMsgThinkingStreaming(msg: ChatMessage): boolean {
    return msg.status === 'streaming' && (!msg.content || msg.content.length === 0);
  }

  private reasonDisplayTitle(msg: ChatMessage): string {
    if (this.isMsgThinkingStreaming(msg)) {
      return '正在思考...';
    }
    const sec: number = msg.thinkingDuration && msg.thinkingDuration > 0 ? msg.thinkingDuration : 1;
    return `已思考（用时 ${sec} 秒）`;
  }

  private toggleReason(id: string): void {
    const idx: number = this.collapsedReasons.indexOf(id);
    try {
      this.getUIContext().animateTo({ duration: 250, curve: Curve.FastOutSlowIn }, () => {
        if (idx >= 0) {
          this.collapsedReasons.splice(idx, 1);
        } else {
          this.collapsedReasons.push(id);
        }
        this.reasonVersion += 1;
      });
    } catch (_e) {
      if (idx >= 0) {
        this.collapsedReasons.splice(idx, 1);
      } else {
        this.collapsedReasons.push(id);
      }
      this.reasonVersion += 1;
    }

    try {
      this.lastAnchorOffset = this.scroller.currentOffset().yOffset;
    } catch (_e) {
    }
  }

  private onThinkingAreaChange(msgId: string, oldH: number, newH: number): void {
    if (oldH === 0 && newH === 0) {
      return;
    }
    const delta: number = newH - oldH;
    if (Math.abs(delta) < 1) {
      return;
    }
    this.handleScrollAnchorOnHeightChange(msgId, delta);
  }

  private handleScrollAnchorOnHeightChange(msgId: string, delta: number): void {
    // Reason: 高度变化只做 offset 记账，不再 bump reasonVersion（否则 ForEach key 全变致整表重建、滚动跳变），
    //   也不再每 token 重锚定（首 token 的一次性锚定已足够，重复 scrollToIndex 会与用户拖动互斥致页面拉不动）。
    //   参数保留签名供未来阈值策略使用（ArkTS 允许形参暂不读取）。

    // 浏览模式下平滑同步滚动锚点，防止视口异常跳变
    try {
      const currentOffset: number = this.scroller.currentOffset().yOffset;
      this.lastAnchorOffset = currentOffset;
    } catch (_e) {
    }
  }

  private initCollapsedReasons(): void {
    const cur: ChatSession | undefined = this.getCurrentSession();
    if (!cur) {
      return;
    }
    let i: number = 0;
    while (i < cur.messages.length) {
      const m: ChatMessage = cur.messages[i];
      if (m.reasoningContent && m.reasoningContent.length > 0) {
        if (!this.collapsedReasons.includes(m.id)) {
          this.collapsedReasons.push(m.id);
        }
      }
      i += 1;
    }
  }

  private actionIsUser(): boolean {
    const m: ChatMessage | undefined = this.actionMsg();
    return m !== undefined && m.role === 'user';
  }

  private copyText(text: string): void {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setDataSync(data);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'copy failed: %{public}s', String(err));
    }
  }

  private copyActionMsg(): void {
    const m: ChatMessage | undefined = this.actionMsg();
    this.closeMsgActions();
    if (m !== undefined && m.content.length > 0) {
      this.copyText(m.content);
    }
  }

  private getProviderName(id: string): string {
    const def: ProviderDefinition | undefined = findProvider(id);
    return def ? def.name : id;
  }

  // ── UI 渲染 ──

  build() {
    Stack() {
      // 主对话内容
      Column() {
        // 顶部导航与状态栏
        Row() {
          // 左侧：三横杠，打开会话抽屉（内含设置入口）
          Column() {
            Row().width(16).height(2).backgroundColor($r('app.color.text_primary'))
            Row().width(16).height(2).backgroundColor($r('app.color.text_primary')).margin({ top: 3 })
            Row().width(16).height(2).backgroundColor($r('app.color.text_primary')).margin({ top: 3 })
          }
          .width(34)
          .height(34)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.fill'))
          .borderRadius(17)
          .onClick(() => {
            this.showDrawer = true;
          })

          Blank()

          // 右侧：模型选择器入口
          Row() {
            Text(this.currentModelId.length > 0 ? this.currentModelId : '选择模型')
              .fontSize(12)
              .fontColor('#4D6BFE')
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(' 选模型')
              .fontSize(10)
              .fontColor('#7C3AED')
              .margin({ left: 4 })
          }
          .padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .backgroundColor($r('app.color.accent_soft'))
          .borderRadius(16)
          .onClick(async () => {
            await this.loadConfiguredProviders();
            this.showModelPicker = true;
          })
        }
        .width('94%')
        .margin({ top: 12, bottom: 8 })

        // 提示条（仅有提示时展示）
        if (this.noticeText.length > 0) {
          Row() {
            Text(this.noticeText)
              .fontSize(11)
              .fontColor('#EF4444')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
          }
          .width('94%')
          .margin({ bottom: 6 })
        }

        Divider().color($r('app.color.divider')).width('100%')

        // 对话气泡消息流（仅渲染当前激活分支；LazyForEach 只为视口内消息建 Markdown 实例）
        List({ scroller: this.scroller }) {
          LazyForEach(this.msgSource, (msg: ChatMessage) => {
            ListItem() {
              this.MessageBubble(msg)
            }
            .margin({ top: 10, bottom: 10 })
          }, (msg: ChatMessage) => this.msgRenderKey(msg))
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 14, right: 14 })
        .cachedCount(2)
        .scrollBar(BarState.Off)
        .onScrollIndex((start: number, end: number) => {
          this.handleScrollIndex(start, end);
        })
        .onScrollStop(() => {
          this.onChatScrollStop();
        })
        .onReachEnd(() => {
          // 用户回到底部附近：恢复底部跟随。
          this.userTookOver = false;
          this.showJumpBottom = false;
        })

        // 底部输入区域
        Column() {
          // 已 @ 对象 chips（点移除）
          if (this.pendingMentions.length > 0) {
            Scroll() {
              Row() {
                ForEach(this.pendingMentions, (mid: string) => {
                  Row() {
                    Text(`@${this.characterName(mid)}`)
                      .fontSize(12)
                      .fontColor('#4D6BFE')
                    Text('  ×')
                      .fontSize(12)
                      .fontColor($r('app.color.text_muted'))
                  }
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .backgroundColor($r('app.color.accent_soft'))
                  .borderRadius(12)
                  .margin({ right: 6 })
                  .onClick(() => {
                    this.removeMention(mid);
                  })
                }, (mid: string) => mid)
              }
              .padding({ left: 12, right: 12 })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('96%')
            .margin({ bottom: 6 })
          }

          Row() {
            // @ 按钮：仅群聊展示，点击弹成员选择
            if (this.isGroupChat()) {
              Text('@')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#4D6BFE')
                .width(40)
                .height(40)
                .textAlign(TextAlign.Center)
                .backgroundColor($r('app.color.accent_soft'))
                .borderRadius(20)
                .margin({ right: 8 })
                .onClick(() => {
                  this.showMentionPicker = true;
                })
            }
            // 多行输入：折叠态默认两行高度、超出内滚动，展开态加高以查看更全面的内容
            Stack({ alignContent: Alignment.BottomEnd }) {
              TextArea({ placeholder: '输入您的问题...', text: this.inputText })
                .width('100%')
                .height(this.inputExpanded ? INPUT_EXPANDED_HEIGHT : INPUT_BASE_HEIGHT)
                .borderRadius(this.inputExpanded ? 16 : 23)
                .backgroundColor($r('app.color.input_bg'))
                .fontSize(15)
                .padding({ left: 16, right: 46, top: 12, bottom: 12 })
                .onChange((val: string) => {
                  this.inputText = val;
                })
                .onFocus(() => {
                  this.onInputFocus();
                })

              Stack() {
                Image(this.inputExpanded ? $r('app.media.ic_collapse') : $r('app.media.ic_expand'))
                  .width(15)
                  .height(15)
              }
              .width(26)
              .height(26)
              .backgroundColor($r('app.color.accent_soft'))
              .borderRadius(13)
              .margin({ right: 10, bottom: 10 })
              .onClick(() => {
                this.inputExpanded = !this.inputExpanded;
              })
            }
            .layoutWeight(1)

            if (this.isGenerating) {
              Button('停止')
                .fontSize(13)
                .backgroundColor('#EF4444')
                .fontColor('#FFFFFF')
                .height(40)
                .borderRadius(20)
                .margin({ left: 8 })
                .onClick(() => {
                  this.stopGenerating();
                })
            } else {
              Button('发送')
                .fontSize(13)
                .backgroundColor('#4D6BFE')
                .fontColor('#FFFFFF')
                .height(40)
                .borderRadius(20)
                .margin({ left: 8 })
                .onClick(() => {
                  this.sendMessage();
                })
            }
          }
          .width('96%')
          .alignItems(this.inputExpanded ? VerticalAlign.Bottom : VerticalAlign.Center)

          // 深度思考开关：复用通用 ThinkingButton 组件（支持 DeepSeek、小米 MiMo、Kimi 等）
          ThinkingButton({
            isEnabled: this.enableThinking,
            providerId: this.currentProviderId,
            modelId: this.currentModelId,
            onToggle: (val: boolean) => {
              this.enableThinking = val;
            }
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 8, bottom: 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.surface'))

      // ── 图片预览浮层（Markdown 图片点击，全屏深底 + 点空白/按钮关闭） ──
      if (this.previewImage.length > 0) {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              this.previewImage = '';
            })
          Image(this.previewImage)
            .width('92%')
            .objectFit(ImageFit.Contain)
            .constraintSize({ maxHeight: '70%' })
            .borderRadius(12)
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              this.previewImage = '';
            })
          Button('关闭')
            .margin({ bottom: 28 })
            .onClick(() => {
              this.previewImage = '';
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
      }

      // ── 0. 回到底部浮动按钮（视口离开底部时优雅浮现） ──
      if (this.showJumpBottom) {
        Row() {
          Text('↓')
            .fontSize(13)
            .fontColor('#4D6BFE')
            .fontWeight(FontWeight.Bold)
            .margin({ right: 4 })
          Text('回到底部')
            .fontSize(12)
            .fontColor('#4D6BFE')
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 12, right: 14, top: 7, bottom: 7 })
        .borderRadius(18)
        .backgroundColor($r('app.color.surface'))
        .border({ width: 1, color: '#E0E7FF' })
        .shadow({ radius: 10, color: 'rgba(77,107,254,0.15)', offsetX: 0, offsetY: 3 })
        .position({ right: 16, bottom: 135 })
        .transition(TransitionEffect.opacity(0).combine(TransitionEffect.translate({ y: 16 })).animation({ duration: 200, curve: Curve.FastOutSlowIn }))
        .onClick(() => {
          this.jumpToBottom();
        })
      }

      // ── 1. 侧边历史会话抽屉 ──
      if (this.showDrawer) {
        Column() {
          Row() {
            Column() {
              // 抽屉头部
              Row() {
                Text('历史会话')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                Blank()
                Button('+ 新会话')
                  .fontSize(12)
                  .height(30)
                  .borderRadius(15)
                  .onClick(async () => {
                    await this.createNewSession();
                    this.showDrawer = false;
                    this.pendingParticipants = [];
                    this.pendingIdentityId = '';
                    this.characterSheetMode = 'select';
                    this.showCharacterSheet = true;
                  })
              }
              .width('90%')
              .margin({ top: 20, bottom: 14 })

              Divider().color($r('app.color.divider')).width('100%')

              // 会话列表
              List() {
                ForEach(this.sessions, (sess: ChatSession) => {
                  ListItem() {
                    Row() {
                      Column() {
                        Row() {
                          if (sess.isPrivate) {
                            Image($r('app.media.ic_lock'))
                              .width(13)
                              .height(13)
                              .margin({ right: 4 })
                          }
                          Text(sess.title)
                            .fontSize(15)
                            .fontWeight(sess.id === this.currentSessionId ? FontWeight.Bold : FontWeight.Normal)
                            .fontColor(sess.id === this.currentSessionId ? '#4D6BFE' : $r('app.color.text_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .layoutWeight(1)
                        }
                        .width('100%')
                        Text(`${this.getProviderName(sess.providerId)} · ${sess.messages.length} 条消息`)
                          .fontSize(11)
                          .fontColor($r('app.color.text_muted'))
                          .margin({ top: 4 })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Text('›')
                        .fontSize(20)
                        .fontColor($r('app.color.icon_muted'))
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                    .backgroundColor(sess.id === this.currentSessionId ? $r('app.color.accent_soft_selected') : $r('app.color.surface'))
                    .borderRadius(10)
                    .onClick(() => {
                      this.openSessionWithPrivacy(sess);
                    })
                    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
                      this.openSessActions(sess.id);
                    }))
                  }
                  .margin({ bottom: 6 })
                }, (sess: ChatSession) => `${sess.id}_${sess.title}_${sess.updatedAt}_${sess.isPrivate ? 1 : 0}`)
              }
              .width('94%')
              .layoutWeight(1)
              .margin({ top: 10 })
              .scrollBar(BarState.Off)

              // 底部：角色管理 + 设置入口
              Divider().color($r('app.color.divider')).width('100%')
              Row() {
                Image($r('app.media.ic_character'))
                  .width(20)
                  .height(20)
                Text('角色管理')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .margin({ left: 8 })
                Blank()
                Text('›')
                  .fontSize(20)
                  .fontColor($r('app.color.icon_muted'))
              }
              .width('90%')
              .padding({ top: 14, bottom: 6 })
              .onClick(() => {
                this.showDrawer = false;
                this.characterSheetMode = 'manage';
                this.pendingParticipants = [];
                this.showCharacterSheet = true;
              })
              Row() {
                Image($r('app.media.ic_settings'))
                  .width(20)
                  .height(20)
                Text('设置')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .margin({ left: 8 })
                Blank()
                Text('›')
                  .fontSize(20)
                  .fontColor($r('app.color.icon_muted'))
              }
              .width('90%')
              .padding({ top: 6, bottom: 18 })
              .onClick(() => {
                this.showDrawer = false;
                this.openSettings();
              })
            }
            .width('80%')
            .height('100%')
            .backgroundColor($r('app.color.surface'))
            .shadow({ radius: 20, color: 'rgba(0,0,0,0.1)' })
            .transition(TransitionEffect.translate({ x: -260 }).animation({ duration: 320, curve: Curve.ExtremeDeceleration }))

            // 蒙层空白点击收回
            Blank()
              .layoutWeight(1)
              .height('100%')
              .onClick(() => {
                this.showDrawer = false;
              })
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .transition(TransitionEffect.opacity(0).animation({ duration: 280, curve: Curve.EaseOut }))
      }

      // ── 2. 模型与供应商选择弹窗 ──
      if (this.showModelPicker) {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              this.showModelPicker = false;
            })

          Column() {
            Row() {
              Text('选择服务商与模型')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
              Blank()
              if (this.fetchingModels) {
                Text('拉取中...')
                  .fontSize(12)
                  .fontColor('#4D6BFE')
              } else {
                Text('刷新列表')
                  .fontSize(12)
                  .fontColor('#4D6BFE')
                  .onClick(async () => {
                    await this.loadConfiguredProviders();
                    await this.refreshModelList();
                  })
              }
            }
            .width('92%')
            .margin({ top: 18, bottom: 12 })

            // 厂商横向选择器（仅展示已配置 API Key 的服务商，禁用滚动条）
            if (this.configuredProviders.length === 0) {
              Text('尚未配置服务商 API Key，请到「设置 > 资产监控」添加')
                .fontSize(13)
                .fontColor($r('app.color.text_muted'))
                .width('92%')
                .margin({ bottom: 12 })
            } else {
              Scroll() {
                Row() {
                  ForEach(this.configuredProviders, (p: ProviderDefinition) => {
                    Button(p.name)
                      .fontSize(12)
                      .height(32)
                      .backgroundColor(p.id === this.currentProviderId ? '#4D6BFE' : $r('app.color.fill'))
                      .fontColor(p.id === this.currentProviderId ? '#FFFFFF' : $r('app.color.text_primary'))
                      .margin({ right: 8 })
                      .onClick(async () => {
                        this.currentProviderId = p.id;
                        const cur: ChatSession | undefined = this.getCurrentSession();
                        if (cur) {
                          cur.providerId = p.id;
                        }
                        await this.reloadApiKey();
                        await this.refreshModelList();
                        if (isThinkingSupported(this.currentProviderId, this.currentModelId)) {
                          this.enableThinking = true;
                        }
                      })
                  }, (p: ProviderDefinition) => p.id)
                }
                .padding({ left: 16, right: 16 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .margin({ bottom: 12 })
            }

            Divider().color($r('app.color.divider')).width('92%')

            // 实时可用模型列表
            if (this.availableModels.length === 0 && !this.fetchingModels) {
              Column() {
                Text('未探测到可用模型')
                  .fontSize(14)
                  .fontColor($r('app.color.text_muted'))
                  .margin({ top: 40, bottom: 6 })
                Text('请确认已在「设置 > 资产监控」配置对应厂商的正确 API Key')
                  .fontSize(12)
                  .fontColor($r('app.color.text_faint'))
              }
              .width('100%')
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Center)
            } else {
              List() {
                ForEach(this.availableModels, (m: ModelInfo) => {
                  ListItem() {
                    Row() {
                      Text(m.id)
                        .fontSize(14)
                        .fontColor(m.id === this.currentModelId ? '#4D6BFE' : $r('app.color.text_primary'))
                        .fontWeight(m.id === this.currentModelId ? FontWeight.Bold : FontWeight.Normal)
                        .layoutWeight(1)

                      if (isThinkingSupported(this.currentProviderId, m.id)) {
                        Text('深度思考')
                          .fontSize(10)
                          .fontColor('#4D6BFE')
                          .backgroundColor($r('app.color.accent_soft'))
                          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                          .borderRadius(8)
                          .margin({ right: 8 })
                      }

                      if (m.id === this.currentModelId) {
                        Text('已选')
                          .fontSize(12)
                          .fontColor('#4D6BFE')
                      }
                    }
                    .width('100%')
                    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
                    .borderRadius(8)
                    .backgroundColor(m.id === this.currentModelId ? $r('app.color.accent_soft_selected') : $r('app.color.surface'))
                    .onClick(() => {
                      this.currentModelId = m.id;
                      const cur: ChatSession | undefined = this.getCurrentSession();
                      if (cur) {
                        cur.modelId = m.id;
                      }
                      if (isThinkingSupported(this.currentProviderId, m.id)) {
                        this.enableThinking = true;
                      }
                      this.saveState();
                      this.showModelPicker = false;
                    })
                  }
                }, (m: ModelInfo) => m.id)
              }
              .width('92%')
              .layoutWeight(1)
              .margin({ top: 8, bottom: 12 })
              .scrollBar(BarState.Off)
            }

            Button('关闭')
              .width('92%')
              .margin({ bottom: 20 })
              .onClick(() => {
                this.showModelPicker = false;
              })
          }
          .width('100%')
          .height('65%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius({ topLeft: 24, topRight: 24 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
      }

      // ── 3. 角色卡配置抽屉 ──
      if (this.showCharacterSheet) {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              this.showCharacterSheet = false;
            })

          Column() {
            // 顶部拖动条（视觉提示下拉关闭）
            Row()
              .width(36)
              .height(4)
              .backgroundColor($r('app.color.border_card'))
              .borderRadius(2)
              .margin({ top: 10, bottom: 14 })

            Row() {
              Column() {
                Text(this.characterSheetMode === 'manage' ? '角色管理' : '选择角色')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_title'))
                Text(this.characterSheetMode === 'manage' ? '管理你的角色卡与身份' : '选择一个角色开始对话')
                  .fontSize(12)
                  .fontColor($r('app.color.text_muted'))
                  .margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (this.characterSheetMode === 'manage') {
                Button('+ 新建角色')
                  .fontSize(12)
                  .height(30)
                  .borderRadius(15)
                  .backgroundColor($r('app.color.accent_soft'))
                  .fontColor('#4D6BFE')
                  .margin({ right: 10 })
                  .onClick(() => {
                    this.openCharEdit();
                  })
              }
              Text('✕')
                .fontSize(15)
                .fontColor($r('app.color.text_secondary'))
                .width(30)
                .height(30)
                .textAlign(TextAlign.Center)
                .backgroundColor($r('app.color.fill'))
                .borderRadius(15)
                .onClick(() => {
                  this.showCharacterSheet = false;
                })
            }
            .width('92%')
            .alignItems(VerticalAlign.Center)
            .margin({ bottom: 14 })

            // 我扮演（可选，仅建联时选择；锁定后不可更改）
            if (this.characterSheetMode === 'select') {
              Text('我扮演（可选）')
                .fontSize(12)
                .fontColor($r('app.color.text_muted'))
                .width('92%')
                .margin({ bottom: 6 })
              Scroll() {
                Row() {
                  Text('无')
                    .fontSize(12)
                    .fontColor(this.pendingIdentityId.length === 0 ? '#FFFFFF' : $r('app.color.text_primary'))
                    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                    .backgroundColor(this.pendingIdentityId.length === 0 ? '#4D6BFE' : $r('app.color.fill'))
                    .borderRadius(12)
                    .margin({ right: 6 })
                    .onClick(() => {
                      this.pendingIdentityId = '';
                    })
                  ForEach(this.identities, (idn: UserIdentityCard) => {
                    Text(idn.name)
                      .fontSize(12)
                      .fontColor(this.pendingIdentityId === idn.id ? '#FFFFFF' : $r('app.color.text_primary'))
                      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                      .backgroundColor(this.pendingIdentityId === idn.id ? '#4D6BFE' : $r('app.color.fill'))
                      .borderRadius(12)
                      .margin({ right: 6 })
                      .onClick(() => {
                        this.pendingIdentityId = idn.id;
                      })
                  }, (idn: UserIdentityCard) => idn.id)
                }
                .padding({ left: 16, right: 16 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .margin({ bottom: 10 })
            }

            if (this.characters.length === 0) {
              Column() {
                Text('暂无角色卡')
                  .fontSize(14)
                  .fontColor($r('app.color.text_muted'))
                  .margin({ top: 30, bottom: 6 })
                Text(this.characterSheetMode === 'manage' ? '点击右上角“新建角色”创建你的第一个角色' : '请先到历史抽屉“角色管理”中新建角色卡')
                  .fontSize(12)
                  .fontColor($r('app.color.text_faint'))
              }
              .width('100%')
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Center)
            } else {
            List() {
              ForEach(this.characters, (char: CharacterCard) => {
                ListItem() {
                  Row() {
                    Column() {
                      Text(char.name)
                        .fontSize(15)
                        .fontWeight(this.isPendingParticipant(char.id) ? FontWeight.Bold : FontWeight.Medium)
                        .fontColor(this.isPendingParticipant(char.id) ? '#4D6BFE' : $r('app.color.text_primary'))
                      if (char.description.trim().length > 0) {
                        Text(char.description)
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                          .margin({ top: 4 })
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    if (this.characterSheetMode === 'manage') {
                      Text('›')
                        .fontSize(20)
                        .fontColor($r('app.color.icon_muted'))
                        .margin({ left: 8 })
                    } else if (this.isPendingParticipant(char.id)) {
                      Text('✓')
                        .fontSize(13)
                        .fontColor('#FFFFFF')
                        .width(22)
                        .height(22)
                        .textAlign(TextAlign.Center)
                        .backgroundColor('#4D6BFE')
                        .borderRadius(11)
                        .margin({ left: 8 })
                    } else {
                      Row()
                        .width(22)
                        .height(22)
                        .borderRadius(11)
                        .border({ width: 1.5, color: $r('app.color.border_card') })
                        .margin({ left: 8 })
                    }
                  }
                  .width('100%')
                  .padding(14)
                  .borderRadius(12)
                  .backgroundColor(this.isPendingParticipant(char.id) ? $r('app.color.accent_soft_selected') : $r('app.color.surface_alt'))
                  .border({
                    width: this.characterSheetMode === 'select' && this.isPendingParticipant(char.id) ? 1.5 : 0,
                    color: '#4D6BFE'
                  })
                  .onClick(() => {
                    if (this.characterSheetMode === 'manage') {
                      this.openCharEdit(char);
                    } else {
                      this.togglePendingParticipant(char.id);
                    }
                  })
                  .gesture(LongPressGesture({ repeat: false }).onAction(() => {
                    this.openCharActions(char.id);
                  }))
                }
                .margin({ bottom: 8 })
              }, (char: CharacterCard) => `${char.id}_${char.name}`)
            }
            .width('92%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            }

            // 我的身份（仅管理模式；与角色卡区分）
            if (this.characterSheetMode === 'manage') {
              Divider().color($r('app.color.divider')).width('92%').margin({ top: 6, bottom: 8 })
              Row() {
                Text('我的身份')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                Blank()
                Button('+ 新建身份')
                  .fontSize(12)
                  .height(30)
                  .borderRadius(15)
                  .onClick(() => {
                    this.openIdentityEdit();
                  })
              }
              .width('92%')
              .margin({ bottom: 8 })
              if (this.identities.length === 0) {
                Text('暂无身份卡，点右上角新建')
                  .fontSize(12)
                  .fontColor($r('app.color.text_faint'))
                  .width('92%')
                  .margin({ bottom: 8 })
              } else {
                Scroll() {
                  Column() {
                    ForEach(this.identities, (idn: UserIdentityCard) => {
                      Row() {
                        Column() {
                          Text(idn.name)
                            .fontSize(14)
                            .fontWeight(FontWeight.Medium)
                          if (idn.persona.trim().length > 0) {
                            Text(idn.persona)
                              .fontSize(12)
                              .fontColor($r('app.color.text_secondary'))
                              .margin({ top: 2 })
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                          }
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)
                        Text('›')
                          .fontSize(20)
                          .fontColor($r('app.color.icon_muted'))
                          .margin({ left: 8 })
                      }
                      .width('100%')
                      .padding(12)
                      .borderRadius(10)
                      .backgroundColor($r('app.color.surface_alt'))
                      .margin({ bottom: 6 })
                      .onClick(() => {
                        this.openIdentityEdit(idn);
                      })
                      .gesture(LongPressGesture({ repeat: false }).onAction(() => {
                        this.askDeleteIdentity(idn.id);
                      }))
                    }, (idn: UserIdentityCard) => idn.id)
                  }
                  .width('100%')
                }
                .width('92%')
                .constraintSize({ maxHeight: 190 })
                .scrollBar(BarState.Off)
                .margin({ bottom: 8 })
              }
            }

            if (this.characterSheetMode === 'select') {
              Button('开始对话')
                .width('92%')
                .height(46)
                .fontSize(15)
                .borderRadius(23)
                .backgroundColor(this.pendingParticipants.length > 0 ? '#4D6BFE' : $r('app.color.fill'))
                .fontColor(this.pendingParticipants.length > 0 ? '#FFFFFF' : $r('app.color.text_muted'))
                .margin({ top: 12, bottom: 22 })
                .enabled(this.pendingParticipants.length > 0)
                .onClick(() => {
                  this.confirmParticipants();
                })
            } else {
              Blank().height(22)
            }
          }
          .width('100%')
          .height('70%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius({ topLeft: 24, topRight: 24 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
      }

      // ── 4. 角色卡新建/编辑弹窗 ──
      if (this.showCharEditDialog) {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              this.showCharEditDialog = false;
            })

          Column() {
            Text(this.editingCharId.length > 0 ? '编辑角色卡' : '新建角色卡')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .margin({ top: 18, bottom: 12 })

            Scroll() {
              Column() {
                Text('角色名称')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('92%')
                  .margin({ bottom: 4 })
                TextInput({ placeholder: '例如: 编程助手', text: this.editingCharName })
                  .width('92%')
                  .margin({ bottom: 12 })
                  .onChange((v: string) => {
                    this.editingCharName = v;
                  })

                Text('系统设定')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('92%')
                  .margin({ bottom: 4 })
                TextArea({ placeholder: '设定角色的语气、行为模式、知识范畴...', text: this.editingCharPrompt })
                  .width('92%')
                  .height(110)
                  .margin({ bottom: 12 })
                  .onChange((v: string) => {
                    this.editingCharPrompt = v;
                  })

                Text('初次问候语')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('92%')
                  .margin({ bottom: 4 })
                TextInput({ placeholder: '第一句主动打招呼的消息', text: this.editingCharFirstMsg })
                  .width('92%')
                  .margin({ bottom: 16 })
                  .onChange((v: string) => {
                    this.editingCharFirstMsg = v;
                  })
              }
              .width('100%')
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)

            Row() {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor($r('app.color.fill'))
                .fontColor($r('app.color.text_primary'))
                .margin({ right: 8 })
                .onClick(() => {
                  this.showCharEditDialog = false;
                })
              Button('保存')
                .layoutWeight(1)
                .backgroundColor('#4D6BFE')
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.saveCharacterEdit();
                })
            }
            .width('92%')
            .margin({ bottom: 20 })
          }
          .width('100%')
          .height('80%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius({ topLeft: 24, topRight: 24 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
      }

      // ── 5. 消息长按操作菜单 ──
      if (this.actionMsgId !== '') {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              this.closeMsgActions();
            })
          Column() {
            Text(this.actionIsUser() ? '编辑消息' : '回复操作')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .margin({ top: 18, bottom: 10 })
            if (this.actionIsUser()) {
              this.MsgActionRow('编辑并重发', () => {
                this.beginEdit();
              })
            } else {
              this.MsgActionRow('重新生成', () => {
                this.regenerate();
              })
            }
            this.MsgActionRow('复制', () => {
              this.copyActionMsg();
            })
            Button('取消')
              .width('92%')
              .margin({ top: 8, bottom: 16 })
              .onClick(() => {
                this.closeMsgActions();
              })
          }
          .width('100%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius({ topLeft: 24, topRight: 24 })
          .transition(TransitionEffect.translate({ y: 360 }).animation({ duration: 320, curve: Curve.ExtremeDeceleration }))
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
        .transition(TransitionEffect.opacity(0).animation({ duration: 280, curve: Curve.EaseOut }))
      }

      // ── 5.5 @ 成员选择小弹窗（轻量快速选择） ──
      if (this.showMentionPicker) {
        Column() {
          Blank()
            .onClick(() => {
              this.showMentionPicker = false;
            })
          Column() {
            Text('@ 谁来回答')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .margin({ top: 14, bottom: 8 })
            List() {
              ForEach(this.participantCards(), (pc: CharacterCard) => {
                ListItem() {
                  Row() {
                    Text(pc.name)
                      .fontSize(14)
                      .fontWeight(this.pendingMentions.includes(pc.id) ? FontWeight.Bold : FontWeight.Normal)
                      .fontColor(this.pendingMentions.includes(pc.id) ? '#4D6BFE' : $r('app.color.text_primary'))
                      .layoutWeight(1)
                    if (this.pendingMentions.includes(pc.id)) {
                      Text('✓')
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#4D6BFE')
                    }
                  }
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                  .borderRadius(8)
                  .backgroundColor(this.pendingMentions.includes(pc.id) ? $r('app.color.accent_soft_selected') : $r('app.color.surface'))
                  .onClick(() => {
                    this.toggleMention(pc.id);
                  })
                }
              }, (pc: CharacterCard) => pc.id)
            }
            .width('90%')
            .scrollBar(BarState.Off)
            .constraintSize({ maxHeight: 260 })
            Button('完成')
              .width('90%')
              .margin({ top: 8, bottom: 14 })
              .onClick(() => {
                this.showMentionPicker = false;
              })
          }
          .width('76%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius(16)
          Blank()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
      }

      // ── 6. 编辑并重发弹窗 ──
      if (this.showEditDialog) {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              this.cancelEdit();
            })
          Column() {
            Text('编辑并重发')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .margin({ top: 18, bottom: 4 })
            Text('修改后将作为新分支发送，原对话会保留')
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))
              .margin({ bottom: 12 })
            TextArea({ placeholder: '修改消息内容...', text: this.editMsgText })
              .width('92%')
              .height(120)
              .margin({ bottom: 16 })
              .onChange((v: string) => {
                this.editMsgText = v;
              })
            Row() {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor($r('app.color.fill'))
                .fontColor($r('app.color.text_primary'))
                .margin({ right: 8 })
                .onClick(() => {
                  this.cancelEdit();
                })
              Button('发送')
                .layoutWeight(1)
                .backgroundColor('#4D6BFE')
                .fontColor('#FFFFFF')
                .enabled(this.editMsgText.trim().length > 0)
                .onClick(() => {
                  this.confirmEdit();
                })
            }
            .width('92%')
            .margin({ bottom: 20 })
          }
          .width('100%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius({ topLeft: 24, topRight: 24 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
      }

      // ── 8. 历史会话长按操作菜单 ──
      if (this.sessActionId !== '' && !this.showRenameDialog && !this.showDeleteConfirm) {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              this.closeSessActions();
            })
          Column() {
            Text(this.sessActionTitle())
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 18, bottom: 10 })
            this.MsgActionRow(this.sessActionIsPrivate() ? '取消保密' : '保密', () => {
              this.toggleSessPrivacy();
            })
            this.MsgActionRow('重命名', () => {
              this.beginRename();
            })
            this.MsgActionRow('删除', () => {
              this.askDeleteSession();
            })
            Button('取消')
              .width('92%')
              .margin({ top: 8, bottom: 16 })
              .onClick(() => {
                this.closeSessActions();
              })
          }
          .width('100%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius({ topLeft: 24, topRight: 24 })
          .transition(TransitionEffect.translate({ y: 360 }).animation({ duration: 320, curve: Curve.ExtremeDeceleration }))
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
        .transition(TransitionEffect.opacity(0).animation({ duration: 280, curve: Curve.EaseOut }))
      }

      // ── 9. 会话重命名弹窗 ──
      if (this.showRenameDialog) {
        Column() {
          Blank()
          Column() {
            Text('重命名会话')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .margin({ top: 20, bottom: 12 })
            TextInput({ placeholder: '输入新名称', text: this.renameText })
              .width('90%')
              .margin({ bottom: 16 })
              .onChange((v: string) => {
                this.renameText = v;
              })
            Row() {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor($r('app.color.fill'))
                .fontColor($r('app.color.text_primary'))
                .margin({ right: 8 })
                .onClick(() => {
                  this.cancelRename();
                })
              Button('保存')
                .layoutWeight(1)
                .backgroundColor('#4D6BFE')
                .fontColor('#FFFFFF')
                .enabled(this.renameText.trim().length > 0)
                .onClick(() => {
                  this.confirmRename();
                })
            }
            .width('90%')
            .margin({ bottom: 20 })
          }
          .width('88%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius(16)
          Blank()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
      }

      // ── 10. 会话删除二次确认（复用组件） ──
      ConfirmDialog({
        show: this.showDeleteConfirm,
        title: '确认删除该会话？',
        message: this.sessActionTitle(),
        confirmText: '删除',
        danger: true,
        onConfirm: () => {
          this.confirmDeleteSession();
        },
        onCancel: () => {
          this.cancelDeleteSession();
        }
      })

      // ── 7. 角色卡长按操作菜单 ──
      if (this.charActionId !== '' && !this.showCharDeleteConfirm) {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              this.closeCharActions();
            })
          Column() {
            Text(this.charActionName())
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .margin({ top: 18, bottom: 10 })
            this.MsgActionRow('编辑', () => {
              this.editFromCharActions();
            })
            this.MsgActionRow('删除', () => {
              this.askDeleteChar();
            })
            Button('取消')
              .width('92%')
              .margin({ top: 8, bottom: 16 })
              .onClick(() => {
                this.closeCharActions();
              })
          }
          .width('100%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius({ topLeft: 24, topRight: 24 })
          .transition(TransitionEffect.translate({ y: 360 }).animation({ duration: 320, curve: Curve.ExtremeDeceleration }))
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
        .transition(TransitionEffect.opacity(0).animation({ duration: 280, curve: Curve.EaseOut }))
      }

      // ── 11. 角色卡删除二次确认（复用组件） ──
      ConfirmDialog({
        show: this.showCharDeleteConfirm,
        title: '确认删除该角色卡？',
        message: this.charActionName(),
        confirmText: '删除',
        danger: true,
        onConfirm: () => {
          this.confirmDeleteChar();
        },
        onCancel: () => {
          this.cancelDeleteChar();
        }
      })

      // ── 12. 身份卡新建/编辑弹窗 ──
      if (this.showIdentityEdit) {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              this.cancelIdentityEdit();
            })
          Column() {
            Text(this.editingIdentityId.length > 0 ? '编辑身份卡' : '新建身份卡')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .margin({ top: 18, bottom: 4 })
            Text('描述你在剧中扮演的身份；区别于 AI 扮演的角色卡')
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))
              .margin({ bottom: 12 })
            Text('身份名称')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('92%')
              .margin({ bottom: 4 })
            TextInput({ placeholder: '例如: 林晚', text: this.editingIdentityName })
              .width('92%')
              .margin({ bottom: 12 })
              .onChange((v: string) => {
                this.editingIdentityName = v;
              })
            Text('身份描述')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('92%')
              .margin({ bottom: 4 })
            TextArea({ placeholder: '背景、性格、职业……', text: this.editingIdentityPersona })
              .width('92%')
              .height(90)
              .margin({ bottom: 16 })
              .onChange((v: string) => {
                this.editingIdentityPersona = v;
              })
            Row() {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor($r('app.color.fill'))
                .fontColor($r('app.color.text_primary'))
                .margin({ right: 8 })
                .onClick(() => {
                  this.cancelIdentityEdit();
                })
              Button('保存')
                .layoutWeight(1)
                .backgroundColor('#4D6BFE')
                .fontColor('#FFFFFF')
                .enabled(this.editingIdentityName.trim().length > 0)
                .onClick(() => {
                  this.saveIdentityEdit();
                })
            }
            .width('92%')
            .margin({ bottom: 20 })
          }
          .width('100%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius({ topLeft: 24, topRight: 24 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
      }

      // ── 13. 身份卡删除二次确认（复用组件） ──
      ConfirmDialog({
        show: this.showIdentityDeleteConfirm,
        title: '确认删除该身份卡？',
        message: this.identityActionName(),
        confirmText: '删除',
        danger: true,
        onConfirm: () => {
          this.confirmDeleteIdentity();
        },
        onCancel: () => {
          this.cancelDeleteIdentity();
        }
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  MsgActionRow(title: string, onTap: () => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.icon_muted'))
    }
    .width('92%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .margin({ bottom: 6 })
    .backgroundColor($r('app.color.surface_row'))
    .borderRadius(12)
    .onClick(onTap)
  }

  // ── 消息气泡子组件（高度对齐 DeepSeek 官方设计） ──
  @Builder
  MessageBubble(msg: ChatMessage) {
    if (msg.role === 'user') {
      Row() {
        Blank()
        Column() {
          // 用户剧中身份名
          if (this.currentIdentityName().length > 0) {
            Text(this.currentIdentityName())
              .fontSize(11)
              .fontColor($r('app.color.reasoning_muted'))
              .margin({ bottom: 4 })
          }
          // 用户气泡：DeepSeek 风格淡蓝紫色圆润胶囊气泡 (#EEF2FF) + 深灰蓝文本
          Text(msg.content)
            .fontSize(15 * this.appFontScale)
            .fontColor($r('app.color.user_bubble_text'))
            .lineHeight(22 * this.appFontScale)
            .padding({ left: 16, right: 16, top: 11, bottom: 11 })
            .backgroundColor($r('app.color.accent_soft'))
            .borderRadius(18)
          // @ 对象
          if (msg.mentionedIds.length > 0) {
            Text(this.mentionText(msg))
              .fontSize(11)
              .fontColor($r('app.color.reasoning_muted'))
              .margin({ top: 4 })
          }
          // 分支切换
          if (this.branchCount(msg) > 1) {
            Row() {
              Blank()
              this.BranchSwitcher(msg)
            }
            .width('100%')
            .margin({ top: 4 })
          }
        }
        .alignItems(HorizontalAlign.End)
        .constraintSize({ maxWidth: '82%' })
        .gesture(LongPressGesture({ repeat: false }).onAction(() => {
          this.openMsgActions(msg.id);
        }))
      }
      .width('100%')
    } else {
      Row() {
        Column() {
          // 深度思考折叠条（纯净 DeepSeek 风格：灰字「已思考（用时 X 秒）」+ 旋转小三角 + 展开左侧竖线装饰）
          if (msg.reasoningContent && msg.reasoningContent.length > 0) {
            Column() {
              // 标题栏：整行可点（44px 级触区），负责状态展示和点击切换
              Row() {
                if (this.isMsgThinkingStreaming(msg)) {
                  LoadingProgress()
                    .width(14)
                    .height(14)
                    .color($r('app.color.reasoning_text'))
                    .margin({ right: 6 })
                }
                Text(this.reasonDisplayTitle(msg))
                  .fontSize(13)
                  .fontColor($r('app.color.reasoning_text'))
                  .fontWeight(FontWeight.Normal)

                // 箭头旋转动效（折叠 0 度指向右，展开 90 度指向下）；加大内边距保触区
                Text('›')
                  .fontSize(16)
                  .fontColor($r('app.color.reasoning_muted'))
                  .fontWeight(FontWeight.Medium)
                  .margin({ left: 4 })
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .rotate({ angle: this.isReasonCollapsed(msg.id) ? 0 : 90 })
                  .animation({ duration: 250, curve: Curve.FastOutSlowIn })
              }
              .alignItems(VerticalAlign.Center)
              .width('100%')
              .padding({ top: 10, bottom: 10 })
              .onClick(() => {
                this.toggleReason(msg.id);
              })

              // 内容区：带高度过渡动画与左侧装饰线，使用 onAreaChange 监听尺寸变化
              Row() {
                Column()
                  .width(2)
                  .backgroundColor($r('app.color.reasoning_bar'))
                  .borderRadius(1)
                  .margin({ right: 10, top: 4, bottom: 4 })

                Scroll(this.thinkScrollerFor(msg.id)) {
                  Text(msg.reasoningContent)
                    .fontSize(13 * this.appFontScale)
                    .fontColor($r('app.color.reasoning_text'))
                    .lineHeight(20 * this.appFontScale)
                    .width('100%')
                }
                .scrollBar(BarState.Auto)
                .constraintSize({ maxHeight: 380 })
                .layoutWeight(1)
              }
              .width('100%')
              .padding({
                left: 2,
                right: 6,
                top: this.isReasonCollapsed(msg.id) ? 0 : 6,
                bottom: this.isReasonCollapsed(msg.id) ? 0 : 10
              })
              .alignItems(VerticalAlign.Top)
              .clip(true)
              .opacity(this.isReasonCollapsed(msg.id) ? 0 : 1)
              .constraintSize({ maxHeight: this.isReasonCollapsed(msg.id) ? 0 : 450 })
              .animation({ duration: 250, curve: Curve.FastOutSlowIn })
              .onAreaChange((oldArea: Area, newArea: Area) => {
                this.onThinkingAreaChange(msg.id, Number(oldArea.height), Number(newArea.height));
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .margin({ bottom: 8 })
          }

          // 正文回复：FluidMarkdown 原生渲染（GFM）；流式中走 Typing 增量，完成后走 Normal。
          // Reason: key 已去掉 content/reasoning 长度（稳定实例防闪烁），文本经父重建下发，
          //   流式帧由库内 hash 差量 + 打字机 pacing 消化。
          if (msg.content.length > 0) {
            MarkdownBody({
              content: MarkdownService.rewriteCitations(msg.content),
              streaming: this.isLiveStreaming(msg),
              fontScale: this.appFontScale,
              darkMode: this.isDarkMode(),
              controller: this.mdControllers.get(msg.id),
              onLinkClick: (href: string) => {
                this.onMarkdownLink(href);
              },
              onImageClick: (src: string) => {
                this.onMarkdownImage(src);
              },
              onMdResize: () => {
                // 门控在 scheduleAnchor 内：非生成态/已接管/已锚定一律直接返回，不拽视口。
                this.scheduleAnchor(msg.id);
              },
              onTypingReady: () => {
                this.onMarkdownReady(msg.id);
              },
            })
            .width('100%')
          } else if (msg.status === 'streaming') {
            Row() {
              LoadingProgress().width(18).height(18).color('#4D6BFE')
              Text('  思考中...')
                .fontSize(13)
                .fontColor($r('app.color.reasoning_text'))
            }
          }

          // 错误信息显示
          if (msg.status === 'error' && msg.errorMessage) {
            Text(`失败: ${msg.errorMessage}`)
              .fontSize(12)
              .fontColor('#EF4444')
              .margin({ top: 6 })
          }

          // 分支切换
          if (this.branchCount(msg) > 1) {
            Row() {
              Blank()
              this.BranchSwitcher(msg)
            }
            .width('100%')
            .margin({ top: 6 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 4, right: 4, top: 4, bottom: 6 })
        .gesture(LongPressGesture({ repeat: false }).onAction(() => {
          this.openMsgActions(msg.id);
        }))
      }
      .width('100%')
    }
  }

  // 分支切换控件：< i/n >，仅在存在多个版本时由调用方渲染；箭头加大内边距保触区。
  @Builder
  BranchSwitcher(msg: ChatMessage) {
    Row() {
      Text('‹')
        .fontSize(18)
        .fontColor('#4D6BFE')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          this.switchBranch(msg, -1);
        })
      Text(`${this.branchIndex(msg) + 1}/${this.branchCount(msg)}`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      Text('›')
        .fontSize(18)
        .fontColor('#4D6BFE')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          this.switchBranch(msg, 1);
        })
    }
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
  }
}
