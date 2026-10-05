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
import { ChatMessage, ChatSession, CharacterCard, ModelInfo, MessageRole } from '../models/ChatModels';
import { ChatService, StreamCallbacks } from '../services/ChatService';
import { ModelService } from '../services/ModelService';
import { ChatStorageService } from '../services/ChatStorageService';
import { PROVIDERS, ProviderDefinition, findProvider } from '../services/ProviderRegistry';

const DOMAIN = 0x0000;
const TAG = 'ChatView';
const PREFS_NAME = 'balance_prefs';

/** 无角色卡时的中性兜底：不附带任何系统设定与开场白。 */
const EMPTY_CHARACTER: CharacterCard = {
  id: '', name: '', avatarIcon: '', description: '',
  systemPrompt: '', firstMessage: '', temperature: 0.7, createdAt: 0,
};

@Component
export struct ChatView {
  // ── 核心状态 ──
  @State sessions: ChatSession[] = [];
  @State currentSessionId: string = '';
  @State characters: CharacterCard[] = [];
  @State currentCharacterId: string = '';
  @State currentProviderId: string = 'deepseek';
  @State currentModelId: string = '';
  @State currentApiKey: string = '';

  // 消息流与输入
  @State inputText: string = '';
  @State isGenerating: boolean = false;
  @State showJumpBottom: boolean = false;
  @State noticeText: string = '';
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

  // 角色卡编辑临时状态
  @State editingCharId: string = '';
  @State editingCharName: string = '';
  @State editingCharPrompt: string = '';
  @State editingCharFirstMsg: string = '';
  @State editingCharTemp: number = 0.7;

  // 滚动控制器
  private scroller: Scroller = new Scroller();
  private abortStreaming: () => void = () => {};
  private balancePrefs: preferences.Preferences | undefined = undefined;
  private seq: number = 0;
  // 顶部锚定滚动状态
  private userTookOver: boolean = false;
  private lastAnchorOffset: number = -1;
  private anchorCaptured: boolean = false;

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

      // 加载会话
      this.sessions = await ChatStorageService.loadSessions();
      const lastSessionId: string = await ChatStorageService.loadActiveSessionId();
      if (lastSessionId.length > 0 && this.hasSession(lastSessionId)) {
        this.currentSessionId = lastSessionId;
        const cur: ChatSession | undefined = this.getCurrentSession();
        if (cur) {
          this.currentProviderId = cur.providerId;
          this.currentModelId = cur.modelId;
          this.currentCharacterId = cur.characterId;
        }
      } else if (this.sessions.length > 0) {
        this.currentSessionId = this.sessions[0].id;
        this.currentProviderId = this.sessions[0].providerId;
        this.currentModelId = this.sessions[0].modelId;
        this.currentCharacterId = this.sessions[0].characterId;
      } else {
        // 创建初始默认会话
        await this.createNewSession();
      }

      // 加载当前 Provider Key、已配置服务商列表并拉取可用模型
      await this.reloadApiKey();
      await this.loadConfiguredProviders();
      await this.refreshModelList();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'aboutToAppear error: %{public}s', String(err));
    }
  }

  // ── 数据辅助逻辑 ──

  private hasSession(id: string): boolean {
    let i: number = 0;
    while (i < this.sessions.length) {
      if (this.sessions[i].id === id) {
        return true;
      }
      i += 1;
    }
    return false;
  }

  private getCurrentSession(): ChatSession | undefined {
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
    };
  }

  /** 将 node 挂到 parent 之下并激活该分支（parent 为空则作为新根）。 */
  private attach(sess: ChatSession, node: ChatMessage): void {
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

  private currentProviderSupportsThinking(): boolean {
    const def: ProviderDefinition | undefined = findProvider(this.currentProviderId);
    return def !== undefined && def.supportsThinking === true;
  }

  private currentCharacterName(): string {
    const c: CharacterCard = this.getCurrentCharacter();
    return c.name.length > 0 ? c.name : '角色';
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

  private scheduleAnchor(): void {
    setTimeout(() => {
      this.anchorStreamingReply();
    }, 0);
  }

  private anchorStreamingReply(): void {
    if (this.userTookOver) {
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

  private onChatScrollStop(): void {
    if (!this.anchorCaptured) {
      return;
    }
    try {
      const off: number = this.scroller.currentOffset().yOffset;
      if (Math.abs(off - this.lastAnchorOffset) > 8) {
        // 用户接管滚动：暂停自动锚定，露出“回到底部”。
        this.userTookOver = true;
        this.showJumpBottom = true;
      }
    } catch (_e) {
    }
  }

  private jumpToBottom(): void {
    this.userTookOver = false;
    this.showJumpBottom = false;
    this.scroller.scrollEdge(Edge.Bottom);
  }

  // ── 会话管理 ──

  private async createNewSession(): Promise<void> {
    // Business Rule: 新会话默认空白、不绑定角色；角色在“新会话”时由用户选择。
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
    };

    const nextList: ChatSession[] = [newSession];
    let i: number = 0;
    while (i < this.sessions.length) {
      nextList.push(this.sessions[i]);
      i += 1;
    }
    this.sessions = nextList;
    this.currentSessionId = newId;
    await this.saveState();
    this.scrollToBottom();
  }

  private async switchSession(sessionId: string): Promise<void> {
    this.currentSessionId = sessionId;
    const cur: ChatSession | undefined = this.getCurrentSession();
    if (cur) {
      this.currentProviderId = cur.providerId;
      this.currentModelId = cur.modelId;
      this.currentCharacterId = cur.characterId;
      await this.reloadApiKey();
      await this.refreshModelList();
    }
    this.showDrawer = false;
    await ChatStorageService.saveActiveSessionId(sessionId);
    this.scrollToBottom();
  }

  private async deleteSession(sessionId: string): Promise<void> {
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
      if (this.sessions.length > 0) {
        this.currentSessionId = this.sessions[0].id;
      } else {
        await this.createNewSession();
      }
    }
    await this.saveState();
  }

  // ── 角色卡选择与编辑 ──

  private async selectCharacter(char: CharacterCard): Promise<void> {
    this.currentCharacterId = char.id;
    const cur: ChatSession | undefined = this.getCurrentSession();
    if (cur) {
      cur.characterId = char.id;
      if (cur.messages.length === 0 && char.firstMessage.trim().length > 0) {
        const welcomeMsg: ChatMessage = this.buildMessage('assistant', char.firstMessage, '');
        this.attach(cur, welcomeMsg);
      }
      this.rebuildSessionReference();
    }
    this.showCharacterSheet = false;
    await this.saveState();
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
    let isNew: boolean = this.editingCharId.length === 0;

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
    }

    this.characters = nextChars;
    this.showCharEditDialog = false;
    await ChatStorageService.saveCharacters(this.characters);
  }

  // ── 角色卡长按操作 ──

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

  private async deleteFromCharActions(): Promise<void> {
    const id: string = this.charActionId;
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

  // ── 发送与流式输出 ──

  private rebuildSessionReference(): void {
    const list: ChatSession[] = [];
    let i: number = 0;
    while (i < this.sessions.length) {
      list.push(this.sessions[i]);
      i += 1;
    }
    this.sessions = list;
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
    this.noticeText = '';

    if (sess.title === '新对话') {
      sess.title = text.length > 14 ? `${text.substring(0, 14)}...` : text;
    }

    // 新消息挂在当前激活分支的叶节点之下。
    const parentId: string = this.currentLeafId(sess);
    const userMsg: ChatMessage = this.buildMessage('user', text, parentId);
    this.attach(sess, userMsg);
    sess.updatedAt = Date.now();
    this.rebuildSessionReference();
    this.scrollToBottom();
    this.generateReply(sess, userMsg);
  }

  /** 为某个 user 节点挂 assistant 占位并流式生成；历史取该分支根->user 的路径。 */
  private generateReply(sess: ChatSession, userMsg: ChatMessage): void {
    const assistantMsg: ChatMessage = this.buildMessage('assistant', '', userMsg.id);
    assistantMsg.status = 'streaming';
    this.attach(sess, assistantMsg);
    sess.updatedAt = Date.now();
    this.rebuildSessionReference();
    this.isGenerating = true;
    // 新一轮生成：重置锚定，先跟随到底，再由锚定逻辑把首行推顶。
    this.userTookOver = false;
    this.showJumpBottom = false;
    this.anchorCaptured = false;
    this.scrollToBottom();

    // Reason: 历史仅取该分支路径（historyTo 沿 parent 链），编辑/切分支后互不污染。
    const history: ChatMessage[] = this.historyTo(sess, userMsg.id);
    const char: CharacterCard = this.getCurrentCharacter();
    const callbacks: StreamCallbacks = {
      onToken: (token: string, reasoningChunk?: string) => {
        if (reasoningChunk && reasoningChunk.length > 0) {
          assistantMsg.reasoningContent = (assistantMsg.reasoningContent || '') + reasoningChunk;
        }
        if (token && token.length > 0) {
          assistantMsg.content += token;
        }
        this.rebuildSessionReference();
        // 顶部锚定：把回答首行推到容器顶部即停住，而非持续跟底。
        this.scheduleAnchor();
      },
      onComplete: () => {
        assistantMsg.status = 'success';
        this.isGenerating = false;
        this.rebuildSessionReference();
        this.saveState();
      },
      onError: (errMsg: string) => {
        assistantMsg.status = 'error';
        assistantMsg.errorMessage = errMsg;
        this.isGenerating = false;
        this.rebuildSessionReference();
        this.saveState();
      }
    };

    this.abortStreaming = ChatService.streamChat({
      providerId: this.currentProviderId,
      apiKey: this.currentApiKey,
      model: this.currentModelId,
      temperature: char.temperature,
      messages: history,
      systemPrompt: char.systemPrompt,
      enableThinking: this.enableThinking,
      reasoningEffort: 'high'
    }, callbacks);
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
    this.attach(sess, userMsg);
    sess.updatedAt = Date.now();
    this.showEditDialog = false;
    this.editMsgId = '';
    this.editMsgText = '';
    this.rebuildSessionReference();
    this.scrollToBottom();
    this.generateReply(sess, userMsg);
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
    this.generateReply(sess, userMsg);
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
        }
      }
      this.rebuildSessionReference();
      this.saveState();
    }
  }

  private clearSessionMessages(): void {
    const cur: ChatSession | undefined = this.getCurrentSession();
    if (cur) {
      cur.messages = [];
      cur.rootIds = [];
      cur.activeRootId = '';
      const char: CharacterCard = this.getCurrentCharacter();
      if (char.firstMessage.trim().length > 0) {
        const welcomeMsg: ChatMessage = this.buildMessage('assistant', char.firstMessage, '');
        this.attach(cur, welcomeMsg);
      }
      this.rebuildSessionReference();
      this.saveState();
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
            Row().width(16).height(2).backgroundColor('#333333')
            Row().width(16).height(2).backgroundColor('#333333').margin({ top: 3 })
            Row().width(16).height(2).backgroundColor('#333333').margin({ top: 3 })
          }
          .width(34)
          .height(34)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor('#F1F3F5')
          .borderRadius(17)
          .onClick(() => {
            this.showDrawer = true;
          })

          Blank()

          // 中间：角色卡切换入口
          Row() {
            Text(this.currentCharacterName())
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(' 切换')
              .fontSize(11)
              .fontColor('#666666')
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor('#F3F4F6')
          .borderRadius(16)
          .onClick(() => {
            this.showCharacterSheet = true;
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
          .backgroundColor('#EEF2FF')
          .borderRadius(16)
          .onClick(async () => {
            await this.loadConfiguredProviders();
            this.showModelPicker = true;
          })
        }
        .width('94%')
        .margin({ top: 12, bottom: 8 })

        // 提示与辅助状态栏
        Row() {
          if (this.noticeText.length > 0) {
            Text(this.noticeText)
              .fontSize(10)
              .fontColor('#EF4444')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
          }

          Blank()

          Text('清空对话')
            .fontSize(11)
            .fontColor('#999999')
            .onClick(() => {
              this.clearSessionMessages();
            })
        }
        .width('94%')
        .margin({ bottom: 6 })

        Divider().color('#EEEEEE').width('100%')

        // 对话气泡消息流（仅渲染当前激活分支）
        List({ scroller: this.scroller }) {
          ForEach(this.activePath(), (msg: ChatMessage) => {
            ListItem() {
              this.MessageBubble(msg)
            }
            .margin({ top: 10, bottom: 10 })
          }, (msg: ChatMessage) => `${msg.id}_${msg.content.length}_${msg.status}_${msg.reasoningContent || ''}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 14, right: 14 })
        .scrollBar(BarState.Off)
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
          // 深度思考开关：参考 DeepSeek 对话窗口，仅对支持思考模式的厂商展示。
          if (this.currentProviderSupportsThinking()) {
            Row() {
              Text('深度思考')
                .fontSize(13)
                .fontColor(this.enableThinking ? '#4D6BFE' : '#666666')
                .fontWeight(this.enableThinking ? FontWeight.Medium : FontWeight.Normal)
            }
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .backgroundColor(this.enableThinking ? '#EEF2FF' : '#F3F4F6')
            .borderRadius(16)
            .borderWidth(1)
            .borderColor(this.enableThinking ? '#C7D2FE' : '#00000000')
            .margin({ bottom: 8 })
            .onClick(() => {
              this.enableThinking = !this.enableThinking;
            })
          }

          Row() {
            TextInput({ placeholder: '输入您的问题...', text: this.inputText })
              .layoutWeight(1)
              .height(44)
              .borderRadius(22)
              .backgroundColor('#F5F6F8')
              .padding({ left: 16, right: 16 })
              .onChange((val: string) => {
                this.inputText = val;
              })
              .onSubmit(() => {
                this.sendMessage();
              })

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
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 8, bottom: 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF')

      // ── 0. 回到底部浮动按钮（用户接管滚动时出现） ──
      if (this.showJumpBottom) {
        Button('回到底部')
          .fontSize(12)
          .height(34)
          .borderRadius(17)
          .backgroundColor('#FFFFFF')
          .fontColor('#4D6BFE')
          .border({ width: 1, color: '#E5E7EB' })
          .shadow({ radius: 8, color: 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 2 })
          .position({ right: 16, bottom: 150 })
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
                    this.showCharacterSheet = true;
                  })
              }
              .width('90%')
              .margin({ top: 20, bottom: 14 })

              Divider().color('#EEEEEE').width('100%')

              // 会话列表
              List() {
                ForEach(this.sessions, (sess: ChatSession) => {
                  ListItem() {
                    Row() {
                      Column() {
                        Text(sess.title)
                          .fontSize(15)
                          .fontWeight(sess.id === this.currentSessionId ? FontWeight.Bold : FontWeight.Normal)
                          .fontColor(sess.id === this.currentSessionId ? '#4D6BFE' : '#222222')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`${this.getProviderName(sess.providerId)} · ${sess.messages.length} 条消息`)
                          .fontSize(11)
                          .fontColor('#999999')
                          .margin({ top: 4 })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Button('删除')
                        .fontSize(11)
                        .height(24)
                        .backgroundColor('#FEE2E2')
                        .fontColor('#EF4444')
                        .onClick(() => {
                          this.deleteSession(sess.id);
                        })
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                    .backgroundColor(sess.id === this.currentSessionId ? '#F4F7FF' : '#FFFFFF')
                    .borderRadius(10)
                    .onClick(() => {
                      this.switchSession(sess.id);
                    })
                  }
                  .margin({ bottom: 6 })
                }, (sess: ChatSession) => `${sess.id}_${sess.title}_${sess.updatedAt}`)
              }
              .width('94%')
              .layoutWeight(1)
              .margin({ top: 10 })
              .scrollBar(BarState.Off)

              // 底部：设置入口（资产监控并入设置页）
              Divider().color('#EEEEEE').width('100%')
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
                  .fontColor('#CCCCCC')
              }
              .width('90%')
              .padding({ top: 14, bottom: 18 })
              .onClick(() => {
                this.showDrawer = false;
                this.openSettings();
              })
            }
            .width('80%')
            .height('100%')
            .backgroundColor('#FFFFFF')
            .shadow({ radius: 20, color: 'rgba(0,0,0,0.1)' })

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
        .transition(TransitionEffect.opacity(0).animation({ duration: 200 }))
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
                .fontColor('#999999')
                .width('92%')
                .margin({ bottom: 12 })
            } else {
              Scroll() {
                Row() {
                  ForEach(this.configuredProviders, (p: ProviderDefinition) => {
                    Button(p.name)
                      .fontSize(12)
                      .height(32)
                      .backgroundColor(p.id === this.currentProviderId ? '#4D6BFE' : '#F1F3F5')
                      .fontColor(p.id === this.currentProviderId ? '#FFFFFF' : '#333333')
                      .margin({ right: 8 })
                      .onClick(async () => {
                        this.currentProviderId = p.id;
                        const cur: ChatSession | undefined = this.getCurrentSession();
                        if (cur) {
                          cur.providerId = p.id;
                        }
                        await this.reloadApiKey();
                        await this.refreshModelList();
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

            Divider().color('#EEEEEE').width('92%')

            // 实时可用模型列表
            if (this.availableModels.length === 0 && !this.fetchingModels) {
              Column() {
                Text('未探测到可用模型')
                  .fontSize(14)
                  .fontColor('#888888')
                  .margin({ top: 40, bottom: 6 })
                Text('请确认已在「设置 > 资产监控」配置对应厂商的正确 API Key')
                  .fontSize(12)
                  .fontColor('#AAAAAA')
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
                        .fontColor(m.id === this.currentModelId ? '#4D6BFE' : '#222222')
                        .fontWeight(m.id === this.currentModelId ? FontWeight.Bold : FontWeight.Normal)
                        .layoutWeight(1)
                      if (m.id === this.currentModelId) {
                        Text('已选')
                          .fontSize(12)
                          .fontColor('#4D6BFE')
                      }
                    }
                    .width('100%')
                    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
                    .borderRadius(8)
                    .backgroundColor(m.id === this.currentModelId ? '#F4F7FF' : '#FFFFFF')
                    .onClick(() => {
                      this.currentModelId = m.id;
                      const cur: ChatSession | undefined = this.getCurrentSession();
                      if (cur) {
                        cur.modelId = m.id;
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
          .backgroundColor('#FFFFFF')
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
            Row() {
              Text('角色卡设定')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
              Blank()
              Button('+ 新建角色')
                .fontSize(12)
                .height(30)
                .borderRadius(15)
                .onClick(() => {
                  this.openCharEdit();
                })
            }
            .width('92%')
            .margin({ top: 18, bottom: 14 })

            if (this.characters.length === 0) {
              Column() {
                Text('暂无角色卡')
                  .fontSize(14)
                  .fontColor('#888888')
                  .margin({ top: 30, bottom: 6 })
                Text('点击右上角“新建角色”创建你的第一个角色')
                  .fontSize(12)
                  .fontColor('#AAAAAA')
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
                        .fontWeight(char.id === this.currentCharacterId ? FontWeight.Bold : FontWeight.Normal)
                        .fontColor(char.id === this.currentCharacterId ? '#4D6BFE' : '#222222')
                      Text(char.description)
                        .fontSize(12)
                        .fontColor('#777777')
                        .margin({ top: 4 })
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Text('›')
                      .fontSize(20)
                      .fontColor('#CCCCCC')
                      .margin({ left: 8 })
                  }
                  .width('100%')
                  .padding(14)
                  .borderRadius(12)
                  .backgroundColor(char.id === this.currentCharacterId ? '#F4F7FF' : '#F9FAFB')
                  .onClick(() => {
                    this.selectCharacter(char);
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

            Button('关闭')
              .width('92%')
              .margin({ top: 10, bottom: 20 })
              .onClick(() => {
                this.showCharacterSheet = false;
              })
          }
          .width('100%')
          .height('70%')
          .backgroundColor('#FFFFFF')
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
                  .fontColor('#666666')
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
                  .fontColor('#666666')
                  .width('92%')
                  .margin({ bottom: 4 })
                TextArea({ placeholder: '设定角色的语气、行为模式、知识范畴...', text: this.editingCharPrompt })
                  .width('92%')
                  .height(100)
                  .margin({ bottom: 12 })
                  .onChange((v: string) => {
                    this.editingCharPrompt = v;
                  })

                Text('初次问候语')
                  .fontSize(12)
                  .fontColor('#666666')
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
                .backgroundColor('#F3F4F6')
                .fontColor('#333333')
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
          .backgroundColor('#FFFFFF')
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
          .backgroundColor('#FFFFFF')
          .borderRadius({ topLeft: 24, topRight: 24 })
          .transition(TransitionEffect.translate({ y: 360 }).animation({ duration: 260, curve: Curve.EaseOut }))
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
        .transition(TransitionEffect.opacity(0).animation({ duration: 200 }))
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
              .fontColor('#999999')
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
                .backgroundColor('#F3F4F6')
                .fontColor('#333333')
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
          .backgroundColor('#FFFFFF')
          .borderRadius({ topLeft: 24, topRight: 24 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
      }

      // ── 7. 角色卡长按操作菜单 ──
      if (this.charActionId !== '') {
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
              this.deleteFromCharActions();
            })
            Button('取消')
              .width('92%')
              .margin({ top: 8, bottom: 16 })
              .onClick(() => {
                this.closeCharActions();
              })
          }
          .width('100%')
          .backgroundColor('#FFFFFF')
          .borderRadius({ topLeft: 24, topRight: 24 })
          .transition(TransitionEffect.translate({ y: 360 }).animation({ duration: 260, curve: Curve.EaseOut }))
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
        .transition(TransitionEffect.opacity(0).animation({ duration: 200 }))
      }
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
        .fontColor('#CCCCCC')
    }
    .width('92%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .margin({ bottom: 6 })
    .backgroundColor('#F7F7F8')
    .borderRadius(12)
    .onClick(onTap)
  }

  // ── 消息气泡子组件 ──
  @Builder
  MessageBubble(msg: ChatMessage) {
    if (msg.role === 'user') {
      Row() {
        Blank()
        Column() {
          Text(msg.content)
            .fontSize(15)
            .fontColor('#FFFFFF')
            .lineHeight(22)
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .backgroundColor('#4D6BFE')
            .borderRadius({ topLeft: 16, topRight: 4, bottomLeft: 16, bottomRight: 16 })
          // 分支切换（编辑后的多个版本）
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
        .gesture(LongPressGesture({ repeat: false }).onAction(() => {
          this.openMsgActions(msg.id);
        }))
      }
      .width('100%')
    } else {
      Row() {
        Column() {
          // 深度思考过程（针对 DeepSeek-Reasoner / Kimi 等思考模型）
          if (msg.reasoningContent && msg.reasoningContent.length > 0) {
            Column() {
              Text('思考过程：')
                .fontSize(11)
                .fontColor('#6B7280')
                .fontWeight(FontWeight.Bold)
                .margin({ bottom: 4 })
              Text(msg.reasoningContent)
                .fontSize(12)
                .fontColor('#4B5563')
                .lineHeight(18)
            }
            .width('100%')
            .padding(10)
            .backgroundColor('#F9FAFB')
            .borderRadius(8)
            .borderWidth(1)
            .borderColor('#E5E7EB')
            .margin({ bottom: 8 })
          }

          // 正文回复
          if (msg.content.length > 0) {
            Text(msg.content)
              .fontSize(15)
              .fontColor('#1F2937')
              .lineHeight(23)
          } else if (msg.status === 'streaming') {
            Row() {
              LoadingProgress().width(18).height(18).color('#4D6BFE')
              Text('  生成中...')
                .fontSize(13)
                .fontColor('#6B7280')
            }
          }

          // 错误信息显示
          if (msg.status === 'error' && msg.errorMessage) {
            Text(`失败: ${msg.errorMessage}`)
              .fontSize(12)
              .fontColor('#EF4444')
              .margin({ top: 6 })
          }

          // 分支切换（重新生成的多个版本）
          if (this.branchCount(msg) > 1) {
            Row() {
              Blank()
              this.BranchSwitcher(msg)
            }
            .width('100%')
            .margin({ top: 4 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor('#F3F4F6')
        .borderRadius({ topLeft: 4, topRight: 16, bottomLeft: 16, bottomRight: 16 })
        .constraintSize({ maxWidth: '88%' })
        .gesture(LongPressGesture({ repeat: false }).onAction(() => {
          this.openMsgActions(msg.id);
        }))

        Blank()
      }
      .width('100%')
    }
  }

  // 分支切换控件：< i/n >，仅在存在多个版本时由调用方渲染。
  @Builder
  BranchSwitcher(msg: ChatMessage) {
    Row() {
      Text('‹')
        .fontSize(18)
        .fontColor('#4D6BFE')
        .padding({ left: 10, right: 10 })
        .onClick(() => {
          this.switchBranch(msg, -1);
        })
      Text(`${this.branchIndex(msg) + 1}/${this.branchCount(msg)}`)
        .fontSize(12)
        .fontColor('#666666')
      Text('›')
        .fontSize(18)
        .fontColor('#4D6BFE')
        .padding({ left: 10, right: 10 })
        .onClick(() => {
          this.switchBranch(msg, 1);
        })
    }
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }
}
