/*
 * ChatStorageService.ets
 *
 * 历史会话与角色卡持久化存储服务 —— 基于 Preferences 本地存储。
 * 遵循 ArkTS 严格模式约束：禁止解构、强类型转换、类型收窄。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CharacterCard, ChatMessage, ChatSession, MessageRole } from '../models/ChatModels';

const DOMAIN = 0x0000;
const TAG = 'ChatStorageService';
const PREFS_STORE_NAME = 'chat_storage_prefs';
const KEY_CHARACTERS = 'saved_characters';
const KEY_SESSIONS = 'saved_sessions';
const KEY_ACTIVE_SESSION_ID = 'active_session_id';

/**
 * 默认角色卡列表：空。
 * Business Rule: 不内置任何预设角色，用户按需在“角色卡设定”中自建。
 */
export const DEFAULT_CHARACTERS: CharacterCard[] = [];

export class ChatStorageService {
  private static prefsInstance: preferences.Preferences | undefined = undefined;

  public static async init(context: common.UIAbilityContext): Promise<void> {
    if (!ChatStorageService.prefsInstance) {
      try {
        ChatStorageService.prefsInstance = await preferences.getPreferences(context, { name: PREFS_STORE_NAME });
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'Failed to init preferences: %{public}s', String(err));
      }
    }
  }

  // ── 角色卡持久化 ──

  public static async loadCharacters(): Promise<CharacterCard[]> {
    if (!ChatStorageService.prefsInstance) {
      return DEFAULT_CHARACTERS;
    }
    try {
      const val: preferences.ValueType = await ChatStorageService.prefsInstance.get(KEY_CHARACTERS, '');
      if (typeof val === 'string' && (val as string).length > 0) {
        const parsed: ESObject = JSON.parse(val as string) as ESObject;
        if (Array.isArray(parsed) && parsed.length > 0) {
          // 边界归一化：旧角色卡补 knowledge 缺省。
          return ChatStorageService.normalizeCharacters(parsed as ESObject[]);
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to load characters: %{public}s', String(err));
    }
    // 初次加载保存默认列表
    await ChatStorageService.saveCharacters(DEFAULT_CHARACTERS);
    return DEFAULT_CHARACTERS;
  }

  private static normalizeCharacters(rawList: ESObject[]): CharacterCard[] {
    const out: CharacterCard[] = [];
    let i: number = 0;
    while (i < rawList.length) {
      const item: ESObject = rawList[i];
      i += 1;
      if (item === null || typeof item !== 'object') {
        continue;
      }
      const rec: Record<string, ESObject> = item as Record<string, ESObject>;
      const id: string = typeof rec['id'] === 'string' ? rec['id'] as string : '';
      if (id.length === 0) {
        continue;
      }
      const card: CharacterCard = {
        id: id,
        name: typeof rec['name'] === 'string' ? rec['name'] as string : '未命名',
        avatarIcon: typeof rec['avatarIcon'] === 'string' ? rec['avatarIcon'] as string : 'custom',
        description: typeof rec['description'] === 'string' ? rec['description'] as string : '',
        systemPrompt: typeof rec['systemPrompt'] === 'string' ? rec['systemPrompt'] as string : '',
        firstMessage: typeof rec['firstMessage'] === 'string' ? rec['firstMessage'] as string : '',
        temperature: typeof rec['temperature'] === 'number' ? rec['temperature'] as number : 0.7,
        knowledge: typeof rec['knowledge'] === 'string' ? rec['knowledge'] as string : '',
        createdAt: typeof rec['createdAt'] === 'number' ? rec['createdAt'] as number : Date.now(),
      };
      out.push(card);
    }
    return out;
  }

  public static async saveCharacters(cards: CharacterCard[]): Promise<void> {
    if (!ChatStorageService.prefsInstance) {
      return;
    }
    try {
      await ChatStorageService.prefsInstance.put(KEY_CHARACTERS, JSON.stringify(cards));
      await ChatStorageService.prefsInstance.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save characters: %{public}s', String(err));
    }
  }

  // ── 会话与消息持久化 ──

  public static async loadSessions(): Promise<ChatSession[]> {
    if (!ChatStorageService.prefsInstance) {
      return [];
    }
    try {
      const val: preferences.ValueType = await ChatStorageService.prefsInstance.get(KEY_SESSIONS, '');
      if (typeof val === 'string' && (val as string).length > 0) {
        const parsed: ESObject = JSON.parse(val as string) as ESObject;
        if (Array.isArray(parsed)) {
          // 边界校验：持久化数据不可信，统一走 normalize（含旧版线性结构迁移）。
          return ChatStorageService.normalizeSessions(parsed as ESObject[]);
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to load sessions: %{public}s', String(err));
    }
    return [];
  }

  // ── 持久化数据归一化（边界校验 + 旧结构迁移） ──

  private static normalizeSessions(rawList: ESObject[]): ChatSession[] {
    const out: ChatSession[] = [];
    let i: number = 0;
    while (i < rawList.length) {
      const item: ESObject = rawList[i];
      i += 1;
      if (item === null || typeof item !== 'object') {
        continue;
      }
      const rec: Record<string, ESObject> = item as Record<string, ESObject>;
      const id: string = typeof rec['id'] === 'string' ? rec['id'] as string : '';
      if (id.length === 0) {
        continue;
      }

      const msgsRaw: ESObject = rec['messages'];
      const pool: ChatMessage[] = [];
      if (Array.isArray(msgsRaw)) {
        const arr: ESObject[] = msgsRaw as ESObject[];
        let m: number = 0;
        while (m < arr.length) {
          const msg: ChatMessage | undefined = ChatStorageService.normalizeMessage(arr[m]);
          if (msg !== undefined) {
            pool.push(msg);
          }
          m += 1;
        }
      }

      let rootIds: string[] = [];
      let activeRootId: string = '';
      const rootsRaw: ESObject = rec['rootIds'];
      const hasTree: boolean = Array.isArray(rootsRaw) && typeof rec['activeRootId'] === 'string';
      if (hasTree) {
        const rArr: ESObject[] = rootsRaw as ESObject[];
        let r: number = 0;
        while (r < rArr.length) {
          if (typeof rArr[r] === 'string' && ChatStorageService.messageExists(pool, rArr[r] as string)) {
            rootIds.push(rArr[r] as string);
          }
          r += 1;
        }
        activeRootId = rec['activeRootId'] as string;
      } else {
        // 旧版为线性数组，迁移为单链树。
        rootIds = ChatStorageService.migrateLinear(pool);
        activeRootId = rootIds.length > 0 ? rootIds[0] : '';
      }

      // 修正悬空引用：过滤不存在的子节点、校正 activeChildId。
      ChatStorageService.repairRefs(pool, rootIds);

      let validActive: boolean = false;
      let ri: number = 0;
      while (ri < rootIds.length) {
        if (rootIds[ri] === activeRootId) {
          validActive = true;
          break;
        }
        ri += 1;
      }
      if (!validActive) {
        activeRootId = rootIds.length > 0 ? rootIds[0] : '';
      }

      // 参与者与模式（旧数据缺省为单聊）。
      const partsRaw: ESObject = rec['participantIds'];
      const participantIds: string[] = [];
      if (Array.isArray(partsRaw)) {
        const pArr: ESObject[] = partsRaw as ESObject[];
        let p: number = 0;
        while (p < pArr.length) {
          if (typeof pArr[p] === 'string' && (pArr[p] as string).length > 0) {
            participantIds.push(pArr[p] as string);
          }
          p += 1;
        }
      }
      let sceneMode: 'single' | 'group' = 'single';
      if (rec['sceneMode'] === 'group' && participantIds.length >= 2) {
        sceneMode = 'group';
      }
      const joinRaw: ESObject = rec['joinMap'];
      const joinMap: Record<string, string> = {};
      if (joinRaw !== null && typeof joinRaw === 'object' && !Array.isArray(joinRaw)) {
        const jRec: Record<string, ESObject> = joinRaw as Record<string, ESObject>;
        const jKeys: string[] = Object.keys(jRec);
        let ki: number = 0;
        while (ki < jKeys.length) {
          const kk: string = jKeys[ki];
          if (typeof jRec[kk] === 'string') {
            joinMap[kk] = jRec[kk] as string;
          }
          ki += 1;
        }
      }

      const session: ChatSession = {
        id: id,
        title: typeof rec['title'] === 'string' ? rec['title'] as string : '对话',
        characterId: typeof rec['characterId'] === 'string' ? rec['characterId'] as string : '',
        providerId: typeof rec['providerId'] === 'string' ? rec['providerId'] as string : 'deepseek',
        modelId: typeof rec['modelId'] === 'string' ? rec['modelId'] as string : '',
        updatedAt: typeof rec['updatedAt'] === 'number' ? rec['updatedAt'] as number : Date.now(),
        messages: pool,
        rootIds: rootIds,
        activeRootId: activeRootId,
        participantIds: participantIds,
        sceneMode: sceneMode,
        joinMap: joinMap,
      };
      out.push(session);
    }
    return out;
  }

  private static normalizeMessage(item: ESObject): ChatMessage | undefined {
    if (item === null || typeof item !== 'object') {
      return undefined;
    }
    const rec: Record<string, ESObject> = item as Record<string, ESObject>;
    const id: string = typeof rec['id'] === 'string' ? rec['id'] as string : '';
    if (id.length === 0) {
      return undefined;
    }
    let role: MessageRole = 'user';
    const roleStr: ESObject = rec['role'];
    if (roleStr === 'assistant' || roleStr === 'system') {
      role = roleStr as MessageRole;
    }
    let status: 'sending' | 'streaming' | 'success' | 'error' = 'success';
    const st: ESObject = rec['status'];
    if (st === 'sending' || st === 'streaming' || st === 'error') {
      status = st as 'sending' | 'streaming' | 'error';
    }
    const menRaw: ESObject = rec['mentionedIds'];
    const mentionedIds: string[] = [];
    if (Array.isArray(menRaw)) {
      const mArr: ESObject[] = menRaw as ESObject[];
      let mi: number = 0;
      while (mi < mArr.length) {
        if (typeof mArr[mi] === 'string' && (mArr[mi] as string).length > 0) {
          mentionedIds.push(mArr[mi] as string);
        }
        mi += 1;
      }
    }
    const msg: ChatMessage = {
      id: id,
      role: role,
      content: typeof rec['content'] === 'string' ? rec['content'] as string : '',
      reasoningContent: typeof rec['reasoningContent'] === 'string' ? rec['reasoningContent'] as string : undefined,
      createdAt: typeof rec['createdAt'] === 'number' ? rec['createdAt'] as number : Date.now(),
      status: status,
      errorMessage: typeof rec['errorMessage'] === 'string' ? rec['errorMessage'] as string : undefined,
      parentId: typeof rec['parentId'] === 'string' ? rec['parentId'] as string : '',
      childIds: [],
      activeChildId: '',
      speakerId: typeof rec['speakerId'] === 'string' ? rec['speakerId'] as string : '',
      mentionedIds: mentionedIds,
    };
    const childRaw: ESObject = rec['childIds'];
    if (Array.isArray(childRaw)) {
      const cArr: ESObject[] = childRaw as ESObject[];
      let c: number = 0;
      while (c < cArr.length) {
        if (typeof cArr[c] === 'string') {
          msg.childIds.push(cArr[c] as string);
        }
        c += 1;
      }
    }
    msg.activeChildId = typeof rec['activeChildId'] === 'string' ? rec['activeChildId'] as string : '';
    return msg;
  }

  private static messageExists(pool: ChatMessage[], id: string): boolean {
    let i: number = 0;
    while (i < pool.length) {
      if (pool[i].id === id) {
        return true;
      }
      i += 1;
    }
    return false;
  }

  /** 旧版线性消息迁移为单链树，返回根节点列表。 */
  private static migrateLinear(pool: ChatMessage[]): string[] {
    if (pool.length === 0) {
      return [];
    }
    let i: number = 0;
    while (i < pool.length) {
      const cur: ChatMessage = pool[i];
      cur.childIds = [];
      cur.activeChildId = '';
      cur.parentId = i > 0 ? pool[i - 1].id : '';
      if (i > 0) {
        const prev: ChatMessage = pool[i - 1];
        prev.childIds = [cur.id];
        prev.activeChildId = cur.id;
      }
      i += 1;
    }
    return [pool[0].id];
  }

  /** 过滤悬空的 childIds 引用并校正 activeChildId。 */
  private static repairRefs(pool: ChatMessage[], roots: string[]): void {
    let i: number = 0;
    while (i < pool.length) {
      const msg: ChatMessage = pool[i];
      const kept: string[] = [];
      let c: number = 0;
      while (c < msg.childIds.length) {
        if (ChatStorageService.messageExists(pool, msg.childIds[c])) {
          kept.push(msg.childIds[c]);
        }
        c += 1;
      }
      msg.childIds = kept;
      if (kept.length === 0) {
        msg.activeChildId = '';
      } else if (!kept.includes(msg.activeChildId)) {
        msg.activeChildId = kept[0];
      }
      i += 1;
    }
    // 根列表本身也去重去悬空（roots 已按存在性过滤，这里仅去重）。
    const seen: string[] = [];
    let r: number = 0;
    while (r < roots.length) {
      if (!seen.includes(roots[r])) {
        seen.push(roots[r]);
      }
      r += 1;
    }
    while (roots.length > 0) {
      roots.pop();
    }
    r = 0;
    while (r < seen.length) {
      roots.push(seen[r]);
      r += 1;
    }
  }

  public static async saveSessions(sessions: ChatSession[]): Promise<void> {
    if (!ChatStorageService.prefsInstance) {
      return;
    }
    try {
      await ChatStorageService.prefsInstance.put(KEY_SESSIONS, JSON.stringify(sessions));
      await ChatStorageService.prefsInstance.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save sessions: %{public}s', String(err));
    }
  }

  public static async loadActiveSessionId(): Promise<string> {
    if (!ChatStorageService.prefsInstance) {
      return '';
    }
    try {
      const val: preferences.ValueType = await ChatStorageService.prefsInstance.get(KEY_ACTIVE_SESSION_ID, '');
      if (typeof val === 'string') {
        return val as string;
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to load active session ID: %{public}s', String(err));
    }
    return '';
  }

  public static async saveActiveSessionId(sessionId: string): Promise<void> {
    if (!ChatStorageService.prefsInstance) {
      return;
    }
    try {
      await ChatStorageService.prefsInstance.put(KEY_ACTIVE_SESSION_ID, sessionId);
      await ChatStorageService.prefsInstance.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save active session ID: %{public}s', String(err));
    }
  }
}
