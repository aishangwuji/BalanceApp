# TD-002 Markdown 渲染后续项（FluidMarkdown 接入后）

- 状态：待评估
- 背景：`fluid-markdown@1.0.11` 已接入（`entry/oh-package.json5`），GFM + 流式
  Typing + 代码高亮/复制 + 主题映射已落地（见 `systemmap/balance-app.md` Markdown 条目）。
- 后续项：
  1. ~~LazyForEach + IDataSource 迁移~~ 已落地（2026-10-19）：
     `services/ChatMessageDataSource.ets` + `LazyForEach` + `cachedCount(2)`，
     数据源按结构性/局部 key 变化分级刷新，流式增量仍由 controller 驱动。
     剩余：`@Reusable` 实例复用（滚动回收复用组件，进一步降滚动开销）仍待做。
  2. 引用来源：`[ref_N]` 已可点；服务端联网工具返回的 `sources` 已随消息持久化，并在正文下方
     渲染来源卡片（2026-11-19，`4f5fbd6`）。剩余两项：
     - **内联角标**：Chat Completions 的引用在 `annotations` 的 `start_index`/`end_index`
       （按 Unicode 码点计数），正文里没有 `[ref_N]` 标记，尚未在正文对应位置插入角标；
       需先把码点偏移换算成 UTF-16 下标，并跳过代码块内部。
     - **阅读链接**：`deepseek_read_url` 的网页正文放在 `signature` 里，多轮要原样回传整条
       assistant 消息的 `server_tool_calls` 才能复现；当前未声明该工具、也未回传。
  3. Worker 解析实测：库内 parse 为异步合并，解析线程归属未验证；超长消息先观察是否卡顿。
  4. 表格横滚：库采用列宽自适应（`cellMaxWidth` 主题可调），无溢出故未做外层横滚；若出现宽表溢出再议。
  5. LaTeX：库鸿蒙端明确未支持（Known Issues），公式需求如提出需另选方案。
- 影响范围：`components/MarkdownBody.ets`、`pages/ChatView.ets`（气泡/key/驱动器）。
