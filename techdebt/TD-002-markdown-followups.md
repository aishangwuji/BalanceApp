# TD-002 Markdown 渲染后续项（FluidMarkdown 接入后）

- 状态：待评估
- 背景：`fluid-markdown@1.0.11` 已接入（`entry/oh-package.json5`），GFM + 流式
  Typing + 代码高亮/复制 + 主题映射已落地（见 `systemmap/balance-app.md` Markdown 条目）。
- 后续项：
  1. LazyForEach + IDataSource + @Reusable 迁移：当前 `List + ForEach + 稳定 key`
     已懒加载且流式不闪烁；迁移触及分支树与顶部锚定滚动，需先实测长对话帧率再定。
  2. 引用来源列表：`[ref_N]` 已改写可点，当前落 toast；待模型侧提供来源 URL 后做来源面板。
  3. Worker 解析实测：库内 parse 为异步合并，解析线程归属未验证；超长消息先观察是否卡顿。
  4. 表格横滚：库采用列宽自适应（`cellMaxWidth` 主题可调），无溢出故未做外层横滚；若出现宽表溢出再议。
  5. LaTeX：库鸿蒙端明确未支持（Known Issues），公式需求如提出需另选方案。
- 影响范围：`components/MarkdownBody.ets`、`pages/ChatView.ets`（气泡/key/驱动器）。
