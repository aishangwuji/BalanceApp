# TD-004 移动端发布准备缺口（Android / iOS）

- 状态：待处理
- 影响范围：`mobile/`（Flutter 跨平台端）
- 首次登记：2026-10-23

## 现象 / 缺口

1. **Android release 尚未生成正式 keystore**：`android/app/build.gradle.kts` 已支持
   读取 `android/key.properties` 的 release 签名（缺失时回退 debug）。上架前仍需用
   `keytool` 生成 keystore、填好 `key.properties`，再执行 `flutter build appbundle --release`。
2. **iOS 未编译验证**：开发机为 Windows，没有 Xcode。iOS target、bundle id
   `com.example.balanceapp`、`NSFaceIDUsageDescription` 已配置，但仍需在
   macOS/CI 上执行 `flutter build ios --release --no-codesign` 与真机回归。
3. **运行时验证未完成**：本机 AVD 的 `system-images/android-36.1/...` 缺少
   `system.img`，无法启动；也没有连接 Android 真机。当前只验证到
   `flutter analyze`、`flutter test`、`flutter build apk --debug`。
4. **应用图标仍是 Flutter 默认图标**：Android mipmap 与 iOS AppIcon 未替换为
   品牌图标；鸿蒙端已有 `startIcon.png`，可直接派生多尺寸资源。
5. **商店材料缺失**：隐私政策、应用截图、应用描述、内容分级、签名证书指纹
   均未准备。
6. **多语言仅覆盖设置页**：`chat` / `assets` 仍为中文硬编码，与鸿蒙端现状一致。
   若要面向海外商店，需要把全部 UI 文案迁入资源文件。
7. **保密会话未加密**：消息正文仍以明文 JSON 存在 `SharedPreferences`；
   `isPrivate` 仅做 UI 门禁（与鸿蒙 `TD-003` 同源）。API Key 已升级到
   Keychain/Keystore，但会话正文尚未加密。
8. **应用锁关闭路径无二次认证**：开启/关闭应用锁均直接改设置；鸿蒙端同样如此。
   若要防「拿到已解锁设备后关闭锁」，应在关闭前要求一次身份认证。
9. **应用标识仍是占位值**：Android `applicationId` 与 iOS bundle id 均为
   `com.example.balanceapp`。`com.example` 不能作为商店正式标识，上架前必须改为
   自有域名反写（如 `com.yourcompany.balanceapp`），并同步修改
   `MainActivity.kt` 包路径、iOS RunnerTests 标识与签名配置。

## 处置建议

- 上架前按 1→3→4→5 顺序补齐；2 需要 macOS 环境或 CI runner。
- 7 可作为后续安全迭代：为 `isPrivate` 会话引入本地加密（例如
  `cryptography` + Keychain 密钥），并迁移旧数据。
- 8 属于产品决策，若保持与鸿蒙一致可暂不处理，但应在发布说明中标注。
