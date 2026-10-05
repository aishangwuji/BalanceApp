/*
 * ChatModels.ets
 *
 * 对话核心数据结构定义 —— 包含消息、会话、角色卡等。
 * 遵守 ArkTS 严格模式规范：无 any/unknown，无解构，强类型定义。
 */

export type MessageRole = 'user' | 'assistant' | 'system';

export interface ChatMessage {
  id: string;
  role: MessageRole;
  content: string;
  reasoningContent?: string;
  createdAt: number;
  status: 'sending' | 'streaming' | 'success' | 'error';
  errorMessage?: string;
  /** 父节点 id；根节点为 ''。 */
  parentId: string;
  /** 有序子节点 id 列表（承载多个分支/编辑版本）。 */
  childIds: string[];
  /** 当前激活的子分支 id；无子节点为 ''。 */
  activeChildId: string;
}

export interface CharacterCard {
  id: string;
  name: string;
  avatarIcon: string; // 标识内置图标或首字母
  description: string;
  systemPrompt: string;
  firstMessage: string;
  temperature: number; // 默认 0.7
  createdAt: number;
}

export interface ChatSession {
  id: string;
  title: string;
  characterId: string;
  providerId: string;
  modelId: string;
  updatedAt: number;
  /** 扁平节点池：所有分支的节点都保留在此，靠 parent/child 关系组织成树。 */
  messages: ChatMessage[];
  /** 根节点 id 列表（首条消息被编辑会产生多个根分支）。 */
  rootIds: string[];
  /** 当前激活的根分支 id。 */
  activeRootId: string;
}

export interface ModelInfo {
  id: string;
  name: string;
  description?: string;
}
