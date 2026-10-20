/*
 * ChatModels.ets
 *
 * 对话核心数据结构定义 —— 包含消息、会话、角色卡等。
 * 遵守 ArkTS 严格模式规范：无 any/unknown，无解构，强类型定义。
 */

export type MessageRole = 'user' | 'assistant' | 'system';

/**
 * 写时上下文净化掩码（topic gate）。
 * Business Rule: 判定只在消息写入历史时做一次，之后回放按 keep 投影；
 *   topic 记录该消息产生时的主题（非当前主题），避免会话漂移后误删当时切题的内容。
 *   keep 与切段结果一一对应，长度不符时回放 fail-open（保留全文）。
 */
export interface TopicGateMask {
  topic: string;
  keep: boolean[];
}

export interface ChatMessage {
  id: string;
  role: MessageRole;
  content: string;
  reasoningContent?: string;
  /** 深度思考用时（秒，整数，用于还原 DeepSeek 思考用时显示）。 */
  thinkingDuration?: number;
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
  /** 助手消息的上下文净化掩码；未判定/不适用时缺省。 */
  topicMask?: TopicGateMask;
}

export interface CharacterCard {
  id: string;
  name: string;
  avatarIcon: string; // 标识内置图标或首字母
  description: string;
  systemPrompt: string;
  firstMessage: string;
  temperature: number; // 默认 0.7
  /** 私有知识（已下线，统一集成到系统设定中；保留可选以兼容历史数据）。 */
  knowledge?: string;
  createdAt: number;
}

/**
 * 用户身份卡：真人在剧中扮演的身份，区别于 AI 扮演的角色卡。
 * Business Rule: 只要"我是谁"（名字+背景/性格），不要 AI 参数（温度/开场白/知识）。
 */
export interface UserIdentityCard {
  id: string;
  name: string;
  persona: string; // 背景、性格、身份描述
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
  /** 本会话用户扮演的身份卡 id；''=普通用户。选定后锁定。 */
  userIdentityId: string;
  /** 保密会话：打开该会话记录前必须通过人脸/指纹认证。 */
  isPrivate: boolean;
}

export interface ModelInfo {
  id: string;
  name: string;
  description?: string;
}
