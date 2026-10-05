# 多角色群聊设计：@ 指定 + Jev 路由 + 记忆隔离

状态：【已下线 / 已归档】根据产品决议，群聊模式已停用，相关代码均已安全注释下线。当前系统专注于纯净单聊与高质量角色扮演。

## 0. 目标与非目标

- 目标：用户勾选多个角色卡进入同一场景；发送消息时可 @ 指定角色；无 @ 时由 Jev 决定谁发言/谁沉默；每个角色带着"自己该知道的"上下文独立生成回复。
- 非目标：Jev 生成文本；Jev 存记忆；私聊/悄悄话；语音；本期不做自动记忆写入（Phase 3 才做）。

## 1. 总体架构（三层分工）

```
用户输入(@解析) ──▶ 主控编排(代码)
                      ├─ 有@ → 确定性路由（跳过 Jev）
                      ├─ 无@ → Jev 决策（Choice/Noul，带 confidence 兜底）
                      ├─ 逐发言角色构建上下文（system prompt + 私有记忆 + 可见历史 + 本轮消息）
                      ├─ 调生成模型（DeepSeek 等现有供应商）逐个产出回复
                      └─ 落库（speakerId/mentionedIds/水位）+ 渲染
```

- @：把"猜"变成"用户亲口指定"，100% 准确、零模型成本。
- Jev：只做"选谁"，是无状态裁判，不存记忆、不组装上下文、不生成。
- 记忆：全部由主控代码维护（存/取/裁剪）；Jev 只读本轮递过去的 state。

## 2. 数据模型增量（基于现有分支树，不推翻）

现有 `ChatMessage` 树（parentId/childIds/activeChildId）保持不变，增量字段：

```ts
// ChatMessage 新增
speakerId: string;      // 发言角色卡 id；用户消息为 ''；助手消息为角色卡 id
mentionedIds: string[]; // 本条用户消息 @ 的角色卡 id（助手消息为空）

// ChatSession 新增
participantIds: string[]; // 本场景勾选的角色卡 id（场景成员）
sceneMode: 'single' | 'group'; // 单聊沿用现有逻辑；群聊走本设计
```

新实体（独立 Preferences 键，与会话分开存，便于跨会话复用）：

```ts
interface MemoryFact { id: string; text: string; createdAt: number; }
interface CharacterMemory {
  characterId: string;
  knowledge: string;   // 手工维护的私有知识（角色卡新增字段，用户可编辑）
  facts: MemoryFact[]; // 程序写入的事实（Phase 3 自动写入，本期只读 knowledge）
  summary: string;      // 长对话压缩摘要（Phase 3，本期留空）
  updatedAt: number;
}
// 参与者加入水位：participantId -> 该角色可见的首条消息 seq
// 实现为 session 级 Map<characterId, string /* joinAfterMsgId */>，存在 ChatSession 扩展字段 joinMap
```

`CharacterCard` 新增 `knowledge: string`（私有知识，多行文本，建上下文时注入）。

## 3. @ 交互设计（ChatView 输入区）

- 输入行新增 @ 按钮（参考微信/DeepSeek 群聊习惯，放输入框左侧）。
- 点击 @ → 底部弹出场景成员列表（participantIds 对应角色卡，显示名+已选态）。
- 选择后：输入框追加 `@Name ` 文本，同时 `pendingMentions` 记 id；输入框上方以 chip 回显已 @ 对象，点 chip 可移除。
- 发送时校对：仅保留文本中仍存在 `@Name` 的 id（防用户手删文字导致错位），写入 `mentionedIds` 后清空 `pendingMentions`。
- 无成员场景（单聊）不显示 @ 按钮。

## 4. 发送链路（主控流程，每轮用户发送后）

```
1. text + mentionedIds 入队；生成 user 节点 U（挂当前激活分支叶下）。
2. 确定发言者列表 speakers: string[]：
   a. mentionedIds 非空 → speakers = 去重后的 mentionedIds（保持勾选顺序/选择顺序）。
   b. 为空 → 调 Jev 路由（§5），失败/无 Key/超时 → 规则回退（§5.4）。
   c. 空 speakers（全体沉默）→ 插入一条 system 提示节点“（大家沉默了）”，结束本轮。
3. 对 speakers 依次（顺序即选择顺序或 Jev 排序）：
   a. 用 §6 规则为该角色构建上下文。
   b. 调生成模型流式产出，挂为链式节点：U → A1 → A2 …（顺序回复是前后关系，不是分支关系；
      重新生成才产生兄弟分支，沿用现有 < i/n > 切换）。
4. 更新各参与者 lastSeen；saveState。
```

## 5. Jev 集成设计（仅无 @ 时触发）

### 5.1 请求 state（每轮现组装，不持久化 whole state）

```json
{
  "scene": "场景一句话（如：深夜食堂，三位熟客闲聊）",
  "user_message": "本轮用户原文",
  "characters": [
    { "id": "c1", "name": "姚瑶", "bio": "角色卡 description+systemPrompt 摘要",
      "knows": "knowledge 摘要", "recent": "该角色最近 3 轮可见发言摘要" }
  ],
  "recent_turns": "最近约 10 条群聊原文（说话人前缀）"
}
```

### 5.2 问题清单（一次请求全问，并行）

- `should_speak_<id>`：Noul × N（N=参与者数），"X 是否应该在本轮发言？"（支持多人发言与全体沉默）。
- `next_speaker`：Choice 一题，options=各角色+`none`，用于排序与单人场景；与 Noul 交叉验证。
- 门控类（可选，默认关）：`knows_<fact>` Noul，仅在需要校验"该不该知道"时启用。

### 5.3 阈值与兜底（confidence 即裁判的可信度）

- Noul > 0.7 → 发言；< 0.3 → 沉默；0.3~0.7 → 仅当其为 Choice 第一名且 top prob > 0.5 才发言。
- 全体 < 0.3 → 全体沉默（插入沉默提示节点，不调用生成）。
- Choice top prob < 0.5 → 忽略排序，用场景默认顺序。

### 5.4 失败回退（无 Key / 超时 / 报错 / 用户关闭开关）

回退到规则：上轮发言人继续；若无，取 participantIds 第一位。保证任何情况下链路不断。

### 5.5 服务形态

- 新增 `JevService.ets`（独立于 ProviderRegistry 生成供应商）：POST `https://api.typesafe.ai/v1/systemone`，
  body `{ state, model: 'jev-latest'(可配置), questions }`，Bearer Key 存 `key_jev`（复用现有 Key 存储与 maskKey 规范）。
- 设置页加总开关"智能路由（Jev）"，默认关闭；关闭时无 @ 走规则回退。

## 6. 上下文构建与可见性规则（知识隔离的核心）

为角色 C 构建上下文 =（按序拼接，超预算从旧到新截断）：

1. `systemPrompt`（角色设定）。
2. 私有知识段：`knowledge + facts/topK + summary`，包在 `<private_memory>` 标记内，指令要求不得外泄。
3. 可见历史：`historyTo(分支路径)` 过滤——仅保留 seq > joinMap[C] 的消息；用户消息与 C 自身消息全保留；其他角色消息保留（同房默认公开）。
4. 本轮用户消息（含 @ 信息已在 mentions 体现，不再重复注入）。

可见性一句话：**角色只能看到加入之后的消息 + 自己的私有记忆**；中途加入的角色看不到之前的内容（对应"不知道"），hint 到位。

Token 预算：历史按字符截断（如最近 6000 字）+ 记忆 topK（如 10 条），超限从旧到新丢弃，保证请求稳定。

## 7. 记忆机制（本期只读手工 knowledge，自动写放到 Phase 3）

- 读：§6 第 2 步。
- 写（Phase 3）：每轮结束后用生成模型做一次"事实抽取"（仅针对发言角色，输入=本轮新增消息，输出≤3 条事实），经去重后 append；facts 超 50 条做一次压缩摘要。
- 不用 Jev 做写入（它是判断模型，不是抽取/生成模型）。

## 8. 生成与渲染（复用现有能力）

- 复用 `ChatService.streamChat` + `thinking/reasoning_effort`（DeepSeek）+ 中断；`speakerId` 随节点持久化。
- 气泡头显示发言角色名（assistant 侧小字）；分支 `< i/n >`、折叠、锚定滚动逻辑不变（顺序回复走链，天然兼容）。
- 多人同轮依次流式，各自独立 `generateReply`；第二人历史含第一人回复（链式 pathToNode 自然包含）。

## 9. 设置与开关

- 设置页新增：智能路由（Jev）开关 + Jev Key 入口（复用资产监控的 Key 管理样式）+ 说明"关闭则用规则回退"。
- 群聊入口：历史抽屉"新会话"后增加"单聊/群聊"选择？——本期简化：新会话选完角色卡后，若选 ≥2 个自动进入群聊（sceneMode='group'）。

## 10. 成本 / 延迟 / 隐私 / 风险

- 每次无 @ 发言多一次 Jev 调用（state 小，官方称快且便宜；仍需实测记录 p50）。
- 有 @ 的轮次零额外成本——这也是 @ 按钮的产品意义。
- 隐私：对话原文出境到第三方；设置页需一句话披露；Key 按现有规范本地存。
- 最大风险：中文路由准确率（官方自述 CJK 低于英文）→ 由 Phase 0 离线评估 gate，不达标不上线。

## 11. 离线评估结论（Phase 0 实测，已通过）

- 语料：20 轮真实中文多角色情境（覆盖领域专长、口头非@点名、上下文顺接、争执指涉、情感求助、跨领域迷惑项）。
- 结果：
  - 现有规则回退基线准确率：20.0%
  - Jev-Router 决策准确率：**85.0%**（扣除网络超时的有效样本中达 **94.4%**）。
  - 对话气泡左上角角标匹配准确，口头提及与复杂第三人指涉识别尤为精准。
- 门禁判定：**通过**。已进入 Phase 2 代码落地。

## 12. 分阶段落地进展

- Phase 0：【已完成】离线实测评估，通过门禁。
- Phase 1：【已完成】@ 按钮 + 确定性路由 + speakerId/mentionedIds 落库 + 群聊渲染。
- Phase 2：【已完成】`JevService.ets` 实现 + 设置页与资产页开关/Key 管理 + 发送链路接入与阈值兜底。
- Phase 3：【规划中】knowledge 字段 + 自动记忆写入/压缩 + 可见性水位（joinMap）完整版。

## 13. 开放问题（评审时定）

1. 群聊中是否允许中途增删成员？增删后 joinMap/可见性如何算（本期建议：只允许建场景时确定）。
2. 全体沉默时是否需要 AI 抛话题暖场？默认插入沉默提示，不主动暖场。
3. Jev Key 与生成 Key 共用一套存储规范，`key_jev` 是否需要在资产监控页展示余额？否（Jev 无余额接口），仅设置页入口。
