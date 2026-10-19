# TD-003 保密会话仅为 UI 门禁，消息仍明文落盘

- 状态：待评估
- 原因：本期「保密会话」与「应用锁」通过 `services/AuthService.ets` 调用系统
  UserAuthenticationKit 做认证，认证通过后才渲染/切换会话；但会话消息依旧由
  `ChatStorageService` 明文写入 `chat_storage_prefs`（Preferences），
  `ChatSession.isPrivate` 本身也不带密钥保护。
- 影响范围：`services/ChatStorageService.ets`、`pages/ChatView.ets`、`models/ChatModels.ets`；
  不涉及网络协议本身。
- 安全现状（补偿）：保密会话打开/取消保密均须人脸或指纹认证；取消保密也要求认证，
  避免绕过；应用锁开启后切后台即遮挡内容。但具备 root/备份导出能力的一方仍可读取
  明文消息，UI 门禁不构成静态加密。
- 追踪：与 TD-001（API Key 明文）一并评估迁移到 AssetStore 或加密数据库；
  迁移时按 `isPrivate` 决定是否整段加密，并做一次性数据搬迁。
