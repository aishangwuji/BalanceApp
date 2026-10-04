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
  messages: ChatMessage[];
}

export interface ModelInfo {
  id: string;
  name: string;
  description?: string;
}
