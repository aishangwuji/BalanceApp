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
  /** 发言角色卡 id；用户消息为 ''；单聊助手消息为会话绑定的角色卡 id。 */
  speakerId: string;
  /** 本条用户消息 @ 的角色卡 id（助手消息为空）。 */
  mentionedIds: string[];
}

export interface CharacterCard {
  id: string;
  name: string;
  avatarIcon: string; // 标识内置图标或首字母
  description: string;
  systemPrompt: string;
  firstMessage: string;
  temperature: number; // 默认 0.7
  /** 私有知识（该角色知道、他人默认不知道的事实；建群聊上下文时注入）。 */
  knowledge: string;
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
  /** 本场景参与的角色卡 id（群聊成员）；单聊为空。 */
  participantIds: string[];
  /** 会话模式：单聊沿用单角色逻辑，群聊走多角色链式生成。 */
  sceneMode: 'single' | 'group';
  /** 角色可见水位：characterId -> 可见首条消息之前的 msgId（缺省全部可见；Phase1 全员可见）。 */
  joinMap: Record<string, string>;
}

export interface ModelInfo {
  id: string;
  name: string;
  description?: string;
}
