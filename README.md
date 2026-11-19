# openchat

一个鸿蒙（HarmonyOS / ArkTS）小应用，两个目标合在一个壳里：

1. **余额监控**：统一查看各家大模型 / 云服务的账户余额（Bearer 类厂商约 20 家，另含阿里云 BSS、智额等非 Bearer 引擎）。
2. **对话客户端**：贴近 DeepSeek 官方 App 的聊天体验——联网搜索、正文引用角标、来源胶囊、文件解析（PDF/Office/图片）、图片视觉输入、语音输入与朗读。

> 代码按功能模块组织，`systemmap/` 记录模块职责与设计决策，`techdebt/` 记录已知债务。
> 应用内提供「检查更新」（Gitee 优先、GitHub 兜底），发布流程见 [docs/release.md](docs/release.md)。

仓库：GitHub [aishangwuji/openchat](https://github.com/aishangwuji/openchat) ·
Gitee [aishangwuji/openchat](https://gitee.com/aishangwuji/openchat)（国内镜像，`origin`）。
GitHub 侧由 Actions 从 Gitee 自动镜像（`.github/workflows/mirror-from-gitee.yml`）。

## 功能

- **资产**：密钥只存本机 Preferences；余额支持自动刷新与 keep-last-good。
- **对话**：多服务商 / 多模型切换、流式输出与思考过程、Markdown（含代码高亮）、消息分支（编辑/重新生成）、会话自动标题。
- **联网搜索**：DeepSeek 服务端 `web_search` 工具，SSE 解析来源，正文注入引用角标，来源可点开。
- **文件与图片**：DeepSeek Files API 上传（`user_data` / `text_recognition` 按格式分流），图片走视觉通道；附件随消息持久化。
- **语音**：点按/按住录音 → `POST /v1/tools/asr` 转写回填；回答可朗读（`/v1/tools/tts`，本地音频缓存）。
- **外观**：浅色 / 深色 / 跟随系统，7 档字号，中英双语。
- **安全**：应用锁（锁屏密码 / 指纹 / 人脸），切后台即锁定。

## 构建

环境：DevEco Studio 6.x（HarmonyOS SDK 6.1.1(24)）、Node 18+。

```powershell
$env:DEVECO_SDK_HOME = "D:/Program Files/Huawei/DevEco Studio/sdk"
cd BalanceApp
node "D:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" assembleHap `
  --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

产物：`BalanceApp/entry/build/default/outputs/default/entry-default-signed.hap`。

**签名**：仓库中的 `BalanceApp/build-profile.json5` 不含签名配置（本机证书路径与密码不入库）。
首次构建请在 DevEco Studio 里打开工程 → *Project Structure → Signing Configs* → 勾选自动签名，
生成后即可本地编译；这些改动不要提交。

安装到真机：

```powershell
hdc -t <serial> install -r entry-default-signed.hap
hdc -t <serial> shell aa start -a EntryAbility -b com.example.openchat
```

## 目录

```
BalanceApp/            鸿蒙应用（entry 模块）
  entry/src/main/ets/
    pages/             页面（对话、设置、资产、角色…）
    services/          业务服务（ChatService、WebSearchService、FileUploadService、VoiceRecorder、AsrService、UpdateService…）
    components/        UI 组件（Markdown 渲染、能力胶囊…）
mobile/                Flutter 跨端（Android / iOS）
systemmap/             模块职责与设计决策（改动前先看）
techdebt/              已知技术债
docs/                  设计稿与发布流程
```

## 更新与发布

- 应用内检查：设置 → 关于 → 检查更新；启动时也会静默检查（12 小时节流）。
- 版本号在 `BalanceApp/AppScope/app.json5`（`versionCode` / `versionName`）。
- 打 tag、上传 HAP、双源同步的完整步骤见 [docs/release.md](docs/release.md)。

## 数据与安全

- API Key 存本机 Preferences（`key_<providerId>`），不联网上传、不进日志；日志统一 `maskKey`。
- 会话、角色卡等以 JSON 存本机 Preferences，**是明文**（见 `techdebt/TD-003`）。
- 应用锁只做本机门禁，不替代系统级加密。

## 许可证

MIT，见 [LICENSE](LICENSE)。


