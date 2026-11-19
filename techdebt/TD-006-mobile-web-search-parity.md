# TD-006 移动端（Flutter）联网搜索未对齐

- 状态：待处理
- 影响范围：`mobile/lib/data/services/chat_service.dart`、`mobile/lib/state/chat_controller.dart`、
  `mobile/lib/ui/pages/chat_page.dart`、`mobile/lib/ui/widgets/message_bubble.dart`
- 首次登记：2026-11-19

## 现象 / 缺口

鸿蒙端已在 `4f5fbd6` 接入 DeepSeek 服务端联网搜索（`deepseek_web_search`）：
请求声明 tools、解析 `server_tool_event` 展示检索进度、解析末块 `annotations` 与搜索来源、
按 url 去重持久化并渲染来源卡片。**Flutter 端尚未对齐**，两端功能出现已知差异。

## 对齐要点（按鸿蒙端契约移植，不另起设计）

1. `ChatRequestOptions` 加 `enableWebSearch`；`_buildPayload` 在 DeepSeek 且开关为真时加
   `tools: [{'type': 'deepseek_web_search'}]`。
2. `ChatStreamEvent` 扩展搜索事件（`server_tool_event` 的 started/completed）与
   `annotations` 来源；解析规则与 `WebSearchService` 一致（含「call_completed 不带 kind」这一实测结论）。
3. 消息模型加 `sources`（持久化）与 `searchState`/`searchHint`（不持久化）；
   `ChatStorageService` 归一化时校验 http/https、按 url 去重、上限 24。
4. UI：开关胶囊与「深度思考」并排、检索进度文案、正文下方来源卡片（点击开浏览器）；
   开关值存 `preferences_service` 的 `web_search_enabled`，仅 DeepSeek 展示。
5. 对齐后跑 `flutter analyze`（零 issue）+ `flutter test`；新增的解析/去重用例优先覆盖
   mergeSources 的「先到先得、后到补空」语义。

## 备注

鸿蒙端在 `595db48` 又补了正文引用角标、来源胶囊与语音朗读（`TtsService` + 设置页
「语音 > 朗读音色」），这些同样尚未在移动端出现。`86619ea` 之后输入区也改成官方同款
卡片（能力胶囊进卡片、蓝色胶囊样式、右下发送/停止），`4e195f8` 接入了 DeepSeek Files API
文档问答（「+」上传、消息携带 file_id、历史回放）。建议与联网搜索一起对齐：
引用角标（码点→UTF-16 + 跳过代码块）、来源胶囊、TTS 朗读与音色设置、输入卡片样式、
文件上传与 content 数组消息、图片视觉输入（user_data + file 块）与拍照/相册入口。

移动端当前无真机/模拟器可跑（见 TD-004 第 3 条），本轮按用户选择先只做鸿蒙端，
对齐时至少要做到 `analyze` + `test` 通过，运行期验证与 TD-004 一并排期。
