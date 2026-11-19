# openchat

一个鸿蒙（HarmonyOS / ArkTS）小应用，两个目标合在一个壳里：

1. **余额监控**：统一查看各家大模型 / 云服务的账户余额（Bearer 类厂商约 20 家，另含阿里云 BSS、智额等非 Bearer 引擎）。
2. **对话客户端**：贴近 DeepSeek 官方 App 的聊天体验——联网搜索、正文引用角标、来源胶囊、文件解析（PDF/Office/图片）、图片视觉输入、语音输入与朗读。

仓库：GitHub [aishangwuji/openchat](https://github.com/aishangwuji/openchat) ·
Gitee [aishangwuji/openchat](https://gitee.com/aishangwuji/openchat)。
Gitee 为主干（`origin`），GitHub 由 Actions 自动镜像（`.github/workflows/mirror-from-gitee.yml`）。

> 源码开源，但**不包含签名材料**。鸿蒙应用必须签名才能安装，签名与开发者账号绑定，
> 每人用自己的账号生成——步骤在下面和 [docs/signing.md](docs/signing.md)。

## 特性

- **资产**：密钥只存本机 Preferences；余额自动刷新，失败保留上次结果。
- **对话**：多服务商 / 多模型、流式输出与思考过程、Markdown + 代码高亮、消息分支（编辑/重新生成）、会话自动标题。
- **联网搜索**：DeepSeek 服务端 `web_search` 工具，SSE 解析来源，正文注入引用角标，来源可点开。
- **文件与图片**：Files API 上传（`user_data` / `text_recognition` 分流），图片走视觉通道，附件随消息持久化。
- **语音**：按住说话录音 → `/v1/tools/asr` 转写回填；回答可朗读（`/v1/tools/tts`，本地音频缓存）。
- **外观**：浅色 / 深色 / 跟随系统，7 档字号，中英双语。
- **安全**：应用锁（锁屏密码 / 指纹 / 人脸），切后台即锁定。

## 快速开始：编译并装到自己的手机

### 0. 环境

- DevEco Studio 6.x，HarmonyOS SDK **6.1.1(24)**
- Node 18+（DevEco 自带）
- 一台开了**开发者模式 + USB 调试**的鸿蒙手机，数据线

### 1. 生成签名（关键一步，只需做一次）

1. DevEco Studio 打开本仓库的 `BalanceApp/` 目录；
2. 菜单 *File → Project Structure → Signing Configs*；
3. 勾选 **Automatically generate signature**，登录华为开发者账号（免费注册）；
4. 手机连上电脑，DevEco 会自动登记设备 UDID、申请调试证书，并把配置写回
   `BalanceApp/build-profile.json5`。

> 这一步生成的 `signingConfigs` 里含本机证书路径与密钥库口令，**不要提交**。
> 建议执行一次 `git update-index --skip-worktree BalanceApp/build-profile.json5`，之后本机改动不会出现在 `git status` 里。

### 2. 编译

```powershell
$env:DEVECO_SDK_HOME = "D:/Program Files/Huawei/DevEco Studio/sdk"
cd BalanceApp
node "D:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" assembleHap `
  --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

产物：`BalanceApp/entry/build/default/outputs/default/entry-default-signed.hap`
（没做第 1 步的话，构建会在 `SignHap` 报 `bundleName ... does not match`）。

### 3. 安装到手机

```powershell
hdc -t <serial> install -r entry-default-signed.hap
hdc -t <serial> shell aa start -a EntryAbility -b com.example.openchat
```

`<serial>` 用 `hdc list targets` 查；`hdc` 在
`DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe`。

也可以直接在 DevEco 里点 Run，效果一样。

## 为什么别人装不上 Release 里的 HAP

调试签名的 profile 里只登记了**作者自己的设备 UDID**，换台手机装会报
`9568320 signature verify failed`。所以：

- 仓库里不包含 `.p12`（私钥）/ `.p7b`（profile）/ `.cer`（证书），也**不会**公开；
- 别人要用，要么按上面的步骤自己签名，要么等作者上架 AppGallery（唯一能给普通用户分发的途径）；
- 完整的机制、报错排查与升级规则见 [docs/signing.md](docs/signing.md)。

## 更新机制

应用内自带更新检查，更新源就是**本仓库的 Release**（双源，Gitee 优先、GitHub 兜底）：

- 入口：设置 → 关于 → 检查更新；启动时也会静默检查一次（12 小时节流）。
- 逻辑：`UpdateService` 运行时读 `BundleInfo.versionName`，与 release 的 `tag_name` 做逐段数值比较；
  发现新版弹窗展示 release 说明，「去下载」打开 HAP 直链（没有资产则回退 release 页面）。
- 版本号在 `BalanceApp/AppScope/app.json5`（`versionName` / `versionCode` 同步递增）。

### 发一个版本（维护者）

```powershell
# 1. 改版本号（两个字段都要）
#    BalanceApp/AppScope/app.json5
# 2. 构建并收集产物
pwsh ./scripts/release.ps1
# 3. 提交、打 tag、推到 Gitee（主干）
git add -A; git commit -m "chore: 发布 v1.0.1"; git tag v1.0.1
git push origin main --tags
# 4. 让 GitHub 跟上（或等每 2 小时的定时任务）
gh workflow run mirror-from-gitee.yml --repo aishangwuji/openchat
# 5. 两边各发一个 release，挂上 dist/openchat-<ver>.hap
gh release create v1.0.1 "dist/openchat-1.0.1.hap" --repo aishangwuji/openchat --title "v1.0.1" --notes "变更说明"
gitee release create -R aishangwuji/openchat --tag v1.0.1 -n "v1.0.1" -b "变更说明"
#    Gitee CLI 没有 --attach，附件用 attach_files API 补（见 docs/release.md）
```

应用的更新弹窗展示的就是 release 的说明正文，建议写简短的「变更」列表。
细节与校验步骤见 [docs/release.md](docs/release.md)。

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
docs/                  设计稿、发布与签名说明
scripts/               发布辅助脚本
```

## 数据与安全

- API Key 存本机 Preferences（`key_<providerId>`），不上传、不进日志；日志统一 `maskKey`。
- 会话、角色卡以 JSON 存本机 Preferences，**是明文**（见 `techdebt/TD-003`）。
- 应用锁只做本机门禁，不替代系统级加密。
- 仓库全历史不包含任何密钥；提交前会扫 `sk-` / `gho_` / 私钥头。

## 许可证

MIT，见 [LICENSE](LICENSE)。
