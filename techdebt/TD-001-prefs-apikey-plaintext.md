# TD-001 Preferences 明文存 API Key，待迁移加密存储

- 状态：待评估
- 原因：用户明确选择“加密持久化”，当前用 `@ohos.data.preferences` 实现 `baseUrl/apiKey/providerIndex` 存取（Index.ets:savePrefs/aboutToAppear），Preferences 为本地明文 KV，仅依赖系统级文件保护，不算应用层加密。
- 影响范围：`BalanceApp/entry/src/main/ets/pages/Index.ets` 的存取逻辑；不影响查询协议本身。
- 追踪：后续可迁移到 AssetStore（`@kit.BasicServicesKit` Asset）或加密数据库；迁移时需做一次性密钥搬迁 + 老值清理。
- 安全现状：已做补偿——永不打印明文 key（maskKey）、报错不回显完整 key、不提交含 key 的文件（需用户勿将真实 key 写入 git）。

