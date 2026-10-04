/*
 * ChatStorageService.ets
 *
 * 历史会话与角色卡持久化存储服务 —— 基于 Preferences 本地存储。
 * 遵循 ArkTS 严格模式约束：禁止解构、强类型转换、类型收窄。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CharacterCard, ChatSession } from '../models/ChatModels';

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
          return parsed as CharacterCard[];
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to load characters: %{public}s', String(err));
    }
    // 初次加载保存默认列表
    await ChatStorageService.saveCharacters(DEFAULT_CHARACTERS);
    return DEFAULT_CHARACTERS;
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
          return parsed as ChatSession[];
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to load sessions: %{public}s', String(err));
    }
    return [];
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
