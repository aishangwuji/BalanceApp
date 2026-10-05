---
covered_paths:
  - BalanceApp/entry/src/main/ets/services/BalanceService.ets
  - BalanceApp/entry/src/main/ets/services/ProviderRegistry.ets
  - BalanceApp/entry/src/main/ets/services/ChatService.ets
  - BalanceApp/entry/src/main/ets/models/ChatModels.ets
  - BalanceApp/entry/src/main/ets/pages/Index.ets
  - BalanceApp/entry/src/main/ets/pages/ChatView.ets
  - BalanceApp/entry/src/main/ets/pages/Settings.ets
  - BalanceApp/entry/src/main/ets/pages/Assets.ets
  - BalanceApp/entry/src/main/resources/base/profile/main_pages.json
last_verified_commit: uncommitted (working tree 2026-10-05)
---

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
- 品牌图标：`resources/base/media/` 下 deepseek/kimi（取自智额）+ siliconflow/stepfun/openrouter/novita（Google favicons 128px）；`ProviderDefinition.icon` + `Index.providerIcon` 静态 $r 映射（$r 不支持动态拼接）

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
- 思考模式（ChatService.ets）：`ProviderDefinition.supportsThinking`（当前仅 deepseek=true）
  控制是否下发 `thinking:{type:enabled/disabled}` 与 `reasoning_effort`；思考开启时按官方
  规范不下发 `temperature`；非支持厂商不传非标准字段。`reasoning_content` 仅本地展示，
  多轮历史按无 tools 场景只回传 role/content（符合官方“无需回传”）。
- 数据模型：CharacterCard 移除 `tags`；ChatMessage 移除 `usage`，ChatUsage 接口删除
  （token 统计功能整体下线）。角色卡不再内置预设，DEFAULT_CHARACTERS=[]，无角色时用
  EMPTY_CHARACTER 兜底。

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
- 流式顶部锚定滚动（ChatView，Auto Scroll Top Anchor）：流式生成时对末条（当前回答）
  调 `scroller.scrollToIndex(idx, false, ScrollAlign.START)`，把首行推到容器顶后停住，
  内容继续增高但视口不动；内容不足时自动收敛为跟底。用户手动滚动（`onScrollStop`
  比较 `currentOffset` 与 `lastAnchorOffset`）→ 暂停锚定并显示「回到底部」浮动按钮；
  `onReachEnd` 或点按钮恢复。
