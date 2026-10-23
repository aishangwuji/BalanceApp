---
covered_paths:
  - BalanceApp/entry/src/main/ets/services/BalanceService.ets
  - BalanceApp/entry/src/main/ets/services/ProviderRegistry.ets
  - BalanceApp/entry/src/main/ets/services/ChatService.ets
  - BalanceApp/entry/src/main/ets/services/TopicGateService.ets
  - BalanceApp/entry/src/main/ets/services/JevService.ets
  - BalanceApp/entry/src/main/ets/services/MarkdownService.ets
  - BalanceApp/entry/src/main/ets/components/MarkdownBody.ets
  - BalanceApp/entry/src/main/ets/models/ChatModels.ets
  - BalanceApp/entry/src/main/ets/pages/Index.ets
  - BalanceApp/entry/src/main/ets/pages/ChatView.ets
  - BalanceApp/entry/src/main/ets/pages/Settings.ets
  - BalanceApp/entry/src/main/ets/pages/Assets.ets
  - BalanceApp/entry/src/main/ets/services/AuthService.ets
  - BalanceApp/entry/src/main/ets/services/SettingsService.ets
  - BalanceApp/entry/src/main/ets/services/ChatStorageService.ets
  - BalanceApp/entry/src/main/ets/services/ChatMessageDataSource.ets
  - BalanceApp/entry/src/main/ets/components/AppLockGate.ets
  - BalanceApp/entry/src/main/ets/components/ConfirmDialog.ets
  - BalanceApp/entry/src/main/ets/components/ThinkingButton.ets
  - BalanceApp/entry/src/main/ets/entryability/EntryAbility.ets
  - BalanceApp/entry/src/main/resources/base/profile/main_pages.json
  - BalanceApp/entry/src/main/resources/base/element/color.json
  - BalanceApp/entry/src/main/resources/dark/element/color.json
  - BalanceApp/entry/src/main/resources/base/media/ic_appearance.svg
  - BalanceApp/entry/src/main/resources/base/media/ic_assets.svg
  - BalanceApp/entry/src/main/resources/base/media/ic_collapse.svg
  - BalanceApp/entry/src/main/resources/base/media/ic_expand.svg
  - BalanceApp/entry/src/main/resources/base/media/ic_font.svg
  - BalanceApp/entry/src/main/resources/base/media/ic_language.svg
  - BalanceApp/entry/src/main/resources/base/media/ic_personalize.svg
last_verified_commit: 0b7f889a6622c2bb7753e4523c55d92e8bd404c2
last_verified: 2026-10-20
---

> 前瞻设计：多角色群聊（@ + Jev 路由 + 记忆隔离）详见 `docs/group-chat-design.md`。
> 状态：群聊已下线（相关代码注释保留，运行时恒为单聊）；以下“群聊 Phase 1”小节为历史记录。
> 跨平台移动端（Android/iOS，Flutter）见 `systemmap/balance-app-mobile.md`，与鸿蒙端并列维护。

## 上下文净化 Topic Gate（2026-10-20，已落地，构建通过）

> 融合自 nanobot 的写时 topic gate；与本项目「Jev 是裁判、不是生成器」的定位一致（见 group-chat-design）。

- 动机：长会话中离题内容被反复回灌会挤占主线；流式原文已交付用户、无法回收，
  故不在接收端拦截，只在「消息写入历史后」判定一次，影响后续请求。
- 切段 `services/TopicGateService.ets`：按 `。！？!?；;` 与换行切分，保持无损
  （`join(segments) === 原文`），否则掩码与回放文本无法对齐。
- 判定 `services/JevService.ets`：System One 只有两个渠道，端点/模型按官方文档固定：
  `typesafe` → `POST https://api.typesafe.ai/v1/systemone`，模型 `jev-latest`；
  `openrouter` → `POST https://openrouter.ai/api/v1/systemone`，模型 `~typesafe/jev-latest`，
  且必须使用 OpenRouter 自己的 Key（与官方 Key 不通用）。
  一次请求合并本消息所有分段，每段一个 Noul 问句：
  `{model, state:{topic, segments:{segment_i}}, questions:{segment_i:{type:'noul',instructions}}}`，
  读 `answers.segment_i.noul`（切题概率）。
- 写时接线（ChatView）：`generateReply` 的 `onComplete` 与 `stopGenerating` 落库后调用 `gateTopic`，
  **topic 取产生该回复的用户消息（parentMsg.content），不是当前会话主题**，避免会话漂移后误删
  当时切题的内容；判定异步执行，不阻塞回复交付。
- 掩码即缓存：`ChatMessage.topicMask {topic, keep[]}` 随消息持久化，同一段永不重复判定，
  回放 token 序列因此稳定；已带掩码的消息直接跳过。
- 回放 `ChatService.buildApiMessages`：仅对 assistant 历史按掩码投影；掩码缺省或
  `keep.length !== 切段数` 时 fail-open 返回原文。界面与原文存储不变。
- 持久化边界 `ChatStorageService.normalizeTopicMask`：topic 必须为字符串、keep 必须为数组，
  否则视为无掩码（不是「全删」）。
- 配置：设置 > 对话 > 上下文净化，两个 tab：
  - System One（判定）：渠道二选一 + 该渠道专属 Key + 切题阈值（默认 0.5，0.1~0.9）+ 开关。
    Key 分存 `key_jev_typesafe` / `key_jev_openrouter`，只落 Preferences、不上 AppStorage、不进日志；
    清除当前渠道 Key 会同时关闭开关（避免永远空转的启用态）。
  - System Two（生成）：渠道即 `ProviderRegistry` 现有服务商，Key 复用资产监控的 `key_<id>`，
    不另存第二份（同一偏好键，两处入口改动即时同步）。
- 失败语义：未启用/无 Key/网络错误/非 200/结构非法/条数不符/不足两段 → 保留全部（fail-open）。
- 已知边界：切段含换行，代码块内单行被判定剔除时可能留下残块（与 nanobot 行为一致）；
  判定晚于本轮交付，若下一轮在判定完成前开始，该条会以未净化形式参与一次请求。

## 消息列表 LazyForEach 迁移（2026-10-19，已落地，构建通过）

- 问题：`List + ForEach(this.activePath())` 会**一次性实例化整条激活分支**。实测 55 条
  的会话开会话时同时 `new BaseEngine()` × 55 并触发 55 次异步 Markdown 解析：主线程卡顿，
  且可见的尾部消息排在最晚解析 → 内容长时间空白。
- 方案：新增 `services/ChatMessageDataSource.ets`（实现 `IDataSource`），
  消息流改 `LazyForEach(this.msgSource, ...)` + `.cachedCount(2)`，只为视口附近消息建实例。
- 同步策略（关键，避免破坏流式）：
  - `sync(next, nextKeys)` 判定「数量/顺序/消息 id 变化」= 结构性 → `onDataReloaded()`；
  - 否则统计 key 变化面：≥8 条（字号/主题等全表 key 变化）→ 整表 reload；
    1~7 条（思考折叠、流式思考字数 `R<n>`、status 切换）→ 逐条 `onDataChanged(index)` 精确刷新；
  - 正文出现后 key 恒为 `C`，`sync` 不动 → 实例不重建，增量仍由 `MarkdownController` 驱动
    （保持原「同 key 不刷新、靠 controller 喂 token」的机制）。
- 接线：`msgRenderKey(msg)` 同时用于 `LazyForEach` key 与数据源键；`rebuildSessionReference()`
  末尾统一 `syncMessageSource()`；`createNewSession`/`switchSession` 各自补一次 sync。
  索引语义不变（数据源顺序 == `activePath()`），故 `scrollToIndex`/`onScrollIndex` 锚定逻辑无需改。
- 思考折叠：`collapsedReasons` 是普通数组，`msgRenderKey` 只包含该消息自身的折叠标记；
  `toggleReason` 改变标记后必须调用 `syncMessageSource()`，让数据源通知该消息项刷新。
  不使用全局版本号污染所有消息键，否则可能整表重建并破坏 LazyForEach 的缓存同步。
- 结果：开会话只挂载视口内几条消息，卡顿与「空白等渲染」大幅缓解；
  `TD-002` 第 1 项（LazyForEach）落地，`@Reusable` 实例复用仍待做。

## 应用锁与保密会话（2026-10-19，已落地，构建通过）

- 系统认证封装 `services/AuthService.ets`：`authenticate(title)` 走
  `@kit.UserAuthenticationKit` 的 `userAuth.getUserAuthInstance`，认证类型
  **必须同时含 FACE+FINGERPRINT+PIN**，`AuthTrustLevel.ATL2`，challenge 用
  `cryptoFramework` 随机 16 字节；`inProgress` 静态位供生命周期判断，避免认证弹窗
  引起的切后台重复锁定。权限 `ohos.permission.ACCESS_BIOMETRIC`（system_grant/normal）
  已加 `module.json5`。
  - 坑位（真机实测）：系统 UserAuth 组件**不支持「仅人脸+指纹」组合**，
    `CheckAuthWidgetParam: only face+finger not support` → `start()` 直接返错码 8、
    弹窗不出现，调用方只会看到「验证未通过」。故必须带 PIN，系统弹窗仍优先引导
    指纹/人脸，用户可自选。
- 应用锁：设置页「安全 > 应用锁」开关，`SettingsService.setAppLockEnabled` 持久化到
  `balance_prefs` 的 `app_lock_enabled`；`app_locked` 为运行态。`EntryAbility.onWindowStageCreate`
  先 `await SettingsService.init` 再 loadContent（冷启动锁定态在首帧前就绪，避免露内容）；
  `onBackground` 若开关开启且非认证中则置 `app_locked=true`。
  `components/AppLockGate.ets`（挂在 Index 的 Stack 顶层）监听 `app_locked`，锁定态
  全屏 `page_bg` 遮挡并自动拉起认证，成功置 false，失败留在锁屏可重试。
- 保密会话：`ChatSession.isPrivate`（ChatModels/ChatStorageService normalize 缺省 false）。
  历史抽屉长按菜单新增「保密 / 取消保密」；列表项带锁形图标（`ic_lock.svg`），
  ForEach key 追加 `isPrivate` 指纹。点开保密会话走 `openSessionWithPrivacy`
  （系统身份认证）；取消保密也需先认证，防止「不打开会话即可解保再打开」的绕过。
  删除当前会话时优先切首个非保密会话，全为保密则新建空白会话。
- 启动默认新会话 + 草稿会话：`ChatView.aboutToAppear` 不再读取/恢复 `active_session_id`，
  每次重启都进入新会话；但空会话以**草稿**（`draftSession`，不入 `sessions`、不落盘）
  存在，`getCurrentSession()` 优先返回草稿，`attach()` 首次写入消息时
  `promoteDraftIfNeeded()` 才转正并持久化。这样既满足「启动新会话」，又不会在历史里
  堆一堆空「新对话」。启动时顺带清理旧版本遗留的空会话（`messages.length===0`）。
  `createNewSession` 不再 `saveState`（草稿不落盘），`switchSession` 丢弃未使用的草稿。
- 待办：保密标记仅做 UI 门禁，Preferences 内消息仍为明文，见
  `techdebt/TD-003-private-session-plaintext.md`。

## 对话会话体验修正（2026-10-18，已落地，构建通过）

- 输入框（ChatView）：单行 TextInput → 多行 TextArea；折叠态固定两行高（`INPUT_BASE_HEIGHT=68`，
  超出内容由 TextArea 内部滚动），右下角为矢量展开/收起图标按钮（`ic_expand.svg`/`ic_collapse.svg`，
  `inputExpanded` 状态切换 `INPUT_EXPANDED_HEIGHT=200` 查看全文）；发送后自动收起；移除
  `onSubmit`，回车改为换行（不再直接发送）。动态资源名走三元分支两处字面量，符 $r 规范。
- 新会话角色单选：群聊下线后 `togglePendingParticipant` 改单选（再点已选中的角色取消），
  `confirmParticipants` 恒为单聊；选择弹窗重做（顶部拖动条 + 标题/副标题 + 圆形关闭按钮 +
  右侧单选圆圈，去掉冗余“关闭”按钮）；新建角色自动选中。
- 删除会话保留抽屉：`switchSession(sessionId, closeDrawer=true)` 新增开关，`deleteSession`
  删除当前会话时传 false，删完抽屉不收起，可连续长按删除其他会话。

## 群聊 Phase 1（2026-10-05，已落地；已被“群聊下线”取代，仅存档）

- 数据：`ChatMessage.speakerId/mentionedIds`，`ChatSession.participantIds/sceneMode/joinMap`，
  `CharacterCard.knowledge`；存储归一化补缺省并兼容旧数据。
- 建联：新会话角色卡多选 + 开始对话确认；单选绑定单聊（含开场白），多选自动群聊（空白开场）。
- 路由：`sendGroup` 确定性路由（@ 优先 → 规则回退上轮发言人/首位成员 → 全体沉默插提示）；
  按序链式生成（后者挂前者之下），出错即停；`generateReply` 改为 Promise 以支持等待链。
- 显示：助手气泡头显发言人名，用户气泡显 @ 对象；@ 按钮仅群聊展示，成员小弹窗多选
  （居中轻量卡片，✓ 即切），chips 回显，发送时选择器＋文本扫描（CJK 边界）双通道校对落库。
- 私有知识拼入对应发言角色的 systemPrompt（标注不得外泄）。

## 用户身份卡（2026-10-05，已落地）

- 新实体 `UserIdentityCard { id/name/persona/createdAt }`，独立存储 `saved_identities`；
  与角色卡区分：只要"我是谁"，不要 AI 参数。
- 角色管理内「我的身份」分组：新建/点行编辑/长按删除（复用 ConfirmDialog 二次确认）。
- 新会话「我扮演（可选）」单选，写入 `session.userIdentityId` 后锁定（与角色卡同规则）。
- 上下文：每个发言角色的 system prompt 追加用户剧中身份段；请求历史的用户发言前缀身份名
  （拷贝后改写，不污染存储）；用户气泡右上显示身份名。

## 对话与资产体验第二批（2026-10-05，已落地）

- 删除二次确认：新增可复用 `components/ConfirmDialog.ets`（show/title/message/confirmText/danger +
  onConfirm/onCancel；函数类型不可 @Prop，用普通成员）；会话删除与角色卡删除统一接入。
- 移除右上角「清空对话」按钮及 `clearSessionMessages`。
- 角色管理：历史抽屉底部加「角色管理」入口；角色卡面板分 select（新会话多选建联，无新建按钮）
  /manage（新建+点行编辑+长按菜单）两态；`characterSheetMode` 控制。
- 深度思考开关移至输入框下方左侧（仅支持厂商展示）。
- 资产页：新增 Jev 智能路由配置卡（开关 + Key 配置/更换/删除 + 官网链接复制；
  `key_jev`/`jev_enabled` 存 balance_prefs；本期仅存配置，路由生效待 Phase 2）；
  添加服务商弹窗加「未添加/已添加」分段过滤。

# BalanceApp systemmap（初始）

## 入口点

- `BalanceApp/entry/src/main/ets/pages/Index.ets` — Dashboard 总览（总资产 Hero + 服务商卡片 + 添加弹窗 + 空态），对齐智额 dashboard_screen/HeroStatsCard/PremiumProviderCard 前端形式。
- `BalanceApp/entry/src/main/ets/services/ProviderRegistry.ets` — 数据驱动注册表。
- `BalanceApp/entry/src/main/ets/services/BalanceService.ets` — 通用查询引擎 + 错误通道。

## 核心数据模型

- `BalanceInfo { providerId/total/used/available/currency/updatedAt }`（ProviderRegistry.ets，对齐智额 balance_info.dart）
- `ProviderDefinition { id/name/baseUrl/category/balanceType/balanceConfig/brandColor }` + `PROVIDERS[7]`（ProviderRegistry.ets，对齐智额 registry，酒馆除外；2026-10-04 新增 Kimi（月之暗面）api.moonshot.cn/v1/users/me/balance，成功语义 code==0）
- 通用 bearer 引擎：responsePath 导航 + 数组求和 + 换算因子 + used 推导（BalanceService.ets，对齐智额 BearerBalanceAdapter；OpenRouter available 对称推导为本侧修正）
- 本地持久化：Preferences `balance_prefs` 存 `addedIds` + `key_<id>`（Index.ets）
- UI 状态：`records: ProviderRecord[]` + `refreshView()` 重建数组推刷新 + ForEach 数据指纹 key 防复用旧快照（Index.ets，ArkTS @State 深层观察不到的补偿）
- 品牌图标：`resources/base/media/` 下 deepseek/kimi/siliconflow/stepfun/openrouter/novita/mimo
  已于 2026-10-23 统一替换为官方品牌资源（256×256 透明 PNG，来源为各官网 SVG/应用图标，
  见 `mobile/README.md` 的 Provider icons）；`ProviderDefinition.icon` + `Index.providerIcon`
  静态 $r 映射（$r 不支持动态拼接）

## 本次任务所涉现状

- 空目录脚手架 → `devecocli create BalanceApp (API 24, com.example.balanceapp)`，debug 构建成功。
- 真机 `6UNBB26820047956`（UDID `5FB0F2328…BD1E4`）已在 AGC 登记，`devecocli signature generate`
  自动签名成功，`devecocli run` 签名构建+安装成功，`aa start` 启动成功，真机截屏确认
  查询页正常渲染（供应商选择/BaseURL/Key输入/查询-清空按钮/底部说明）。
- 产物：签名 HAP 位于 `entry/build/default/outputs/default/`（-signed）。
- 2026-10-04 dashboard 对齐验证：DeepSeek 真 Key 查询 258ms 回 200，Hero ¥4.89 与卡片
  ¥4.8900/总额/已用/进度条一致；修复过 ForEach 复用旧快照致卡片常显查询中
  （数据指纹 key + refreshView 重建数组，详见 Index.ets cardVersionKey/refreshView）。

## 对话与导航架构（2026-10-05 改造）

- 页面结构（main_pages.json）：`pages/Index`（壳，仅渲染 ChatView）→ `pages/Settings`
  （设置）→ `pages/Assets`（资产监控，由原 Index dashboard 迁出）。底部 Tabs 已移除，
  应用主界面即对话。
- 设置页 Settings.ets：仅入口占位——语言 / 外观 / 字体大小 / 个性化（点击 toast
  「该功能暂未实现」）+ 「资产监控」入口（router.pushUrl → pages/Assets）。
- 对话导航：ChatView 顶部左侧三横杠打开历史抽屉；抽屉底部「设置」行 → Settings。
- 思考模式（ChatService.ets）：`ProviderDefinition.supportsThinking`（deepseek/kimi/mimo=true）
  控制是否下发 `thinking:{type:enabled/disabled}` 与 `reasoning_effort`；Kimi K3 始终推理
  只下发 `reasoning_effort`（默认 max），K2.7 始终思考不下发任何开关，思考开启时按官方
  规范不下发 `temperature`；非支持厂商不传非标准字段。保留式思考：Kimi/MiMo 历史回传
  `reasoning_content` 保多轮思维连贯（DeepSeek 无 tools 场景传了也被忽略，统一回传无害）。
- 流式/记忆（ChatService.ets，对齐 Kimi 官方两节规范）：SSE 以 `data:[DONE]` 为唯一完成判据
  （不用 finish_reason；中断走 err 回调）；`delta.content/reasoning_content` 追加折叠，
  终块 `{choices:[],usage}` 直接跳过（token 统计已下线，不下发 `stream_options.include_usage`）；
  `tool_calls` 无 tools 声明有意忽略，`n` 恒为 1 不下发。记忆为无状态回传：
  `buildApiMessages` 收口流式/非流式，system 常驻首位，历史取新截断（最新 20 条 +
  12000 字符双预算，超限从旧丢弃）；全量历史仍按 session 存 Preferences，只裁剪本次请求。
- Markdown 渲染（FluidMarkdown `fluid-markdown@1.0.11`，ohpm，`MarkdownService/MarkdownBody`）：
  自研引擎已否决，复用支付宝开源库（Apache-2.0，原生 StyledString，无 WebView）。
  流式走 Typing 模式（累计文本 + Begin/Append/End，库内 hash 差量 + 打字机 pacing），
   完成/历史走 Normal；`MarkdownController` 按消息单例存活（建于生成开始、终于完成/停止/
   删会话），ForEach key 去掉 content 长度保实例稳定。库契约：`typing.update`
   只能在 `onMarkdownTypingReady` 之后（`MarkdownBody.onTypingReady` 回调记
   `mdTypingReady`，就绪前跳过不记 begun；完成前未 Begin 则不发 End）。
   高频刷新节流 `refreshStreamView`（~8fps）：driveMarkdown + 整表重建 + 思考跟随
   统一压到 tick，喂库永远累计文本故合并无损（直驱百 Hz 重建会压垮 UI 线程，
   视感"一次性"）。`[ref_N]` 改写为 `[N](#cite-N)`
  （围栏/行内代码内不碰），点击路由：引用 toast（来源列表待模型侧，见 TD-002）、
  外链仅 http/https/mailto 走 viewData 拉起。主题映射字号（`app_font_scale`，`@Prop` 接
  `@StorageProp`）与深色正文色；代码高亮/复制为库内置（highlight.js 移植，无需 prism4cj，
  其为 Android 侧）；表格列宽自适应故无外层横滚。延迟项见 `techdebt/TD-002-markdown-followups.md`
  （LazyForEach 迁移/来源面板/Worker 实测/LaTeX 缺失）。
- 数据模型：CharacterCard 移除 `tags`；ChatMessage 移除 `usage`，ChatUsage 接口删除
  （token 统计功能整体下线）。角色卡不再内置预设，DEFAULT_CHARACTERS=[]，无角色时用
  EMPTY_CHARACTER 兜底。

## 全局视觉主题（2026-10-20）

- 视觉方向为「温润静奢」：浅色采用暖纸白、墨色与克制的香槟金，深色采用温润墨黑与柔金；
  两套资源在 `resources/base/element/color.json` 与 `resources/dark/element/color.json` 使用同名语义 token。
- `accent` 用于文本强调，`accent_solid` / `accent_contrast` 负责主操作表面与对比文字，
  `accent_soft` / `accent_soft_selected` 负责选中态，`hero_*` 固定深墨资产总览层级，
  `overlay_scrim` 统一用于抽屉和弹层遮罩。Markdown 正文主题由 `MarkdownService.applyTheme()` 显式映射。
- 主聊天入口与历史抽屉、模型/角色/消息弹层、设置、资产监控、确认对话框及应用锁共用该色板；
  首页空态、消息气泡、输入区、资产 Hero 与设置卡片依颜色 token 建立统一层级。设置图标使用暖色底片，
  对应 SVG 线色已调整为可读的深金色。
- 本次只改变呈现和布局，不改变聊天发送、模型选择、会话持久化、资产查询、认证及设置保存流程。

## 消息分支、交互细化与锚定滚动（2026-10-05 第二批）

- 消息分支（ChatModels/ChatStorageService/ChatView）：`ChatMessage` 增加
  `parentId/childIds/activeChildId`，`ChatSession` 增加 `rootIds/activeRootId`；消息池为扁平
  节点树。`ChatStorageService.normalizeSessions` 在持久化边界做 Schema 校验并把旧线性
  数据迁移为单链树 + 修复悬空引用。渲染只走 `activePath()`（沿 activeChildId）。
  长按消息 → 编辑并重发（user，同父新增兄弟节点）/ 重新生成（assistant）；气泡右下角
  `< i/n >` 切分支；请求历史用 `historyTo()` 取该分支根到目标的路径。
- 默认会话空白、不绑定角色；点「+ 新会话」先建空白会话再弹角色选择（selectCharacter 补开场白）。
  顶部「厂商」行移除。
- 角色卡：`DEFAULT_CHARACTERS=[]`；列表项去掉“编辑”按钮，改长按弹操作菜单（编辑/删除）；
  编辑弹窗去掉「角色简述」与 `(System Prompt)` 文案。
- 选择服务商与模型：只列出本地已配置 `key_<id>` 的服务商（`loadConfiguredProviders()`）。
- 设置页：语言/外观/字体大小/个性化/资产监控图标改为 `resources/base/media/ic_*.svg`
  （工程化图标，非文字占位）；历史抽屉「设置」行去掉副标题、加齿轮图标。
- 软键盘避让（Index.aboutToAppear）：`getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)`。
  默认 OFFSET 会整页上移致顶栏被顶出屏幕，RESIZE 压缩内容区、顶部固定、聊天区收缩。
  获焦追加：输入框 `onFocus` 在非生成态下分两次（120/380ms）`scrollEdge(Bottom)`，
  保证最新消息不被键盘/收缩区遮挡。
- 会话管理：历史抽屉去掉删除按钮，长按弹菜单（重命名/删除），删除需二次确认弹窗。
- 角色绑定：移除顶部角色切换入口；角色只能在「新会话」弹窗中选择一次，选中后锁定
  （`selectCharacter` 遇已绑定直接 toast 拒绝）；`createNewSession` 重置 `currentCharacterId`。
- 思考过程：方框去掉固定宽度由父气泡包裹；标题行点击「展开/收起」折叠
 （`collapsedReasons + reasonVersion` 强制 ForEach 按 key 刷新）。
- 过渡动画：底部面板统一 `translate(y:360)+ExtremeDeceleration/320ms`，蒙层 `opacity/280ms`，
  历史抽屉面板加左侧滑入。
- 流式顶部锚定滚动（ChatView，Auto Scroll Top Anchor，一次性锚定 2026-10-05 修复）：
  单条回复只在首 token 到达时调一次 `scroller.scrollToIndex(idx, false, ScrollAlign.START)`
  （`anchoredForMsgId` 落标记），顶部固定后内容向下生长视口自然不动；非生成态
  （历史浏览/图片后加载）、用户已接管、已锚定一律直接返回，杜绝每 token 重推把拖动拽回
  （此前每 token + 每次 Markdown 尺寸变化都重锚定，长回答体感“拉不动”）。
  接管检测双通道：`onScrollIndex` 管条目间（end < total-1）；超长单条气泡内部拖动
  end 恒为末条，靠 `onScrollStop` 比较 `currentOffset` 与 `lastAnchorOffset`
 （差值 >30px 即接管并显示「回到底部」）；`onReachEnd` 或点按钮恢复。
  思考区/内容区高度变化只做 offset 记账，不再 bump `reasonVersion`
 （否则 ForEach key 全变致整表重建、滚动跳变）。
  同理：思考结束自动折叠与生成完成时也不 bump `reasonVersion`
 （2026-10-05 跳顶/回复"消失"修复）—— ForEach key 已含 `status` 与折叠态，
  当事条目照常重建（完成时切 Normal 全量渲染）；bump 会改全表 key 致 List
  滚动归零到顶部、新回复沉底不可见。`toggleReason` 的 bump 必须保留
 （`collapsedReasons` 非 @State，那里靠它本身触发渲染）。
- 思考区流式体验（ChatView + MarkdownService，2026-10-05）：思考区定高 380 + 内嵌
  Scroll，流式超出后新文本沉底不可见 → 按消息 id 懒建 `thinkScrollers` 跟底，
  仅内滚动已在底部时跟随（用户上翻查看旧思考不动）；每轮生成重置
  `reasonChunkCount/contentChunkCount`，完成时打一行 hilog 区分"服务端一次性下发"
  与"UI 未刷新"。图片居中限高曾走 `theme.image` 下发，导致整块 Markdown 空白
 （已回退：疑普通对象不符合库内样式级联预期，渲染期异常；居中方案待定）。
  思考标题栏整行可点
  （width 100% + 上下 10vp padding，箭头另加 12/8 padding）；分支切换 `‹ ›`
  内边距加到 16/10。

## 缺陷修复（2026-10-05，已落地，构建通过）

- 流式不刷新根因（ChatView）：ForEach 同 key 复用旧快照，原 key 不含流式进度 →
  正文首 token 不触发 MarkdownBody 挂载、思考 Text 流式期静止。修法：key 增加
  `msgContentPhaseKey`——正文未出现前为 `R<思考字数>`（逐帧重建让思考文本刷新，
  此时 MarkdownBody 未挂载无副作用），正文出现后固定 `C`（MarkdownBody 仅挂载一次，
  增量由 controller 驱动不重建）。思考内滚动 `followThinking` 改为生成期间统一定底
  （条目重建会重置内滚动，`isAtEnd` 会误判）。`onTypingReady`/`mdTypingReady` 机制
  至此才真正生效。
- 深色模式（全仓）：新增 `resources/base|dark/element/color.json` 语义色板
  （page_bg/surface/text_*/divider/accent_soft/reasoning_*/user_bubble_text/hero_bg/
  danger_text 等），ChatView/Settings/Assets/ConfirmDialog/ThinkingButton 的硬编码
  色值改用 `$r('app.color.*')`，由 `setColorMode` 自动切；白色仍保留仅用于彩底按钮
  前景。解析深色态 `app_dark`（system 跟随系统）由 `SettingsService.resolveDark`
  （读 `context.config.colorMode`）落 AppStorage，`EntryAbility.onConfigurationUpdate`
  在 system 模式跟随系统变化；ChatView `isDarkMode()` 读 `app_dark`，Markdown 主题
  随之切换，修复"深色下正文浅字白底隐形"。
- 资产页整轮刷新失效（Assets）：单卡 `refreshOne` 自增 `globalSession` 作废进行中的
  `refreshAll`，但 `refreshAll` 收尾条件不成立 → `refreshingAll` 卡 true、按钮永久
  置灰；修法：`refreshOne` 内复位 `refreshingAll=false`。
- 删除当前会话状态不同步（ChatView）：`deleteSession` 删当前会话后委托
  `switchSession(sessions[0].id)`，重同步 provider/model/key 并重载模型（原逻辑只改
  会话/角色，头部与发送会用错厂商）。
- 待办（本次未动，已识别）：多语言仅 Settings 覆盖、字号仅 ChatView 生效、模型选择
  无手动输入、移除服务商无二次确认、MiMo 余额端点 `/v1/models` 恒 0 等，见审查清单。
