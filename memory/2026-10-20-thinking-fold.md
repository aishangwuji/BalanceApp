# 思考内容折叠按钮无法重新展开

## 症状

思考内容折叠一次后，再次点击标题无法展开。

## 根因

`ChatView.toggleReason()` 修改普通数组 `collapsedReasons` 并递增全局 `reasonVersion`，但消息列表已经由 `LazyForEach` 和 `ChatMessageDataSource` 管理。LazyForEach 只有在数据源 `sync()` 发出 `onDataChanged()` 后才会刷新缓存项；折叠事件没有同步数据源，导致折叠态与缓存的消息渲染键脱节。

## 修复

- 在 `ChatView.msgRenderKey()` 中移除全局 `reasonVersion`，保留每条消息独立的折叠标记。
- 在 `toggleReason()` 更新折叠数组后调用 `syncMessageSource()`，只通知对应消息项刷新。
- 同步更新 `systemmap/balance-app.md` 中 LazyForEach 折叠态的刷新约定。

## 验证

- `devecocli build`：成功。
- 签名版 HAP 安装到设备 `6UNBB26820047956`：成功；`EntryAbility` 启动：成功。
- 当前仓库没有匹配的 UI 自动化/单元测试文件；未进行截图或设备点击复测。
