本项目主要构建于鸿蒙软件开发。
参考：C:\Users\15216\.codeartsdoer\cache\enterprise\agents\鸿蒙开发.md
技能使用：C:\Users\15216\.codeartsdoer\cache\enterprise\skills\

编码时严格遵守：agent-rules这个skill，每次编码都必须严格遵守编码规范。

Jev模型文档："C:\Users\15216\Desktop\文档\jve模型.md"
官方文档地址：https://docs.typesafe.ai/introduction

---

## 本项目开发经验（2026-10-04 BalanceApp 实战沉淀，后续 Agent 必读）

### 1. 工具链与设备（本机实测）

- hdc 路径：`D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`，
  不在 PATH，每次用 `& "<绝对路径>" -t <serial> <cmd>` 调用；真机 serial 如 `6UNBB26820047956`
- devecocli：`npm install -g @deveco/deveco-cli@stable`；`devecocli create/build/run/device/check`，
  注意 `build` 没有 `--project` 参数，必须 `cd` 到工程目录再跑
- 真机装机硬门槛：未签名 HAP 一律被拒（`9568320 no signature file`），USB 调试开了也没用；
  模拟器可装未签名包。`devecocli run` 会直说 real device cannot install unsigned
- 签名链路：`devecocli auth login`（浏览器交互、无头会挂起，勿空跑）→ AGC 登记设备 UDID
  （`hdc shell bm get --udid` 取）→ `devecocli signature generate` 自动签发
- AGC 设备入口（2026-01 官方文档核实）：控制台 → AppGallery Connect →
  “证书、APP ID和Profile > 设备” → 添加设备；`service/josp/agc/` 落的是介绍页不是控制台
- 签名材料（.p12/.cer/.p7b）在本机 `C:\Users\<user>\.ohos\config\`，密钥库不出仓库；
  `build-profile.json5` 的 signing 路径是本机绝对路径，他机 clone 后重跑 `signature generate`
- 启动报 `10106102` = 手机锁屏，开发者模式下工具无法自动解锁，让用户手动解锁后再起

### 2. 真机验证三板斧（hdc）

- 启动：`hdc -t <serial> shell aa start -a EntryAbility -b com.example.balanceapp`
- 日志：`hdc -t <serial> shell "hilog -x -t app -D 0x0000" | Select-String <TAG>`（DOMAIN 0x0000 即 -D 0x0000）
- 截屏：`hdc shell snapshot_display -f /data/local/tmp/x.jpeg` + `hdc file recv` 到
  `C:\Users\15216\AppData\Local\Temp\opencode\` 再 Read 看图；黑屏多为应用还在启动或屏锁了

### 3. ArkTS 严格模式坑位（本次全踩过，写码时逐条对照）

- 禁解构声明：`const {a} = await f()` 一律改 `const r = await f(); const a = r.a`
- 禁 any/unknown：`JSON.parse` 结果必须立刻注明类型（如 `const v: ESObject` 或具体接口 `as XxxResponse`）
- `throw` 只接受 Error 类型：透传 catch 到的值要先包一层 `new Error(...)`
- `@Builder`/`build()` 内只允许 UI 组件语法：`const` 声明一律外移到普通方法，UI 表达式里直接调方法
- `FontWeight` 没有 `ExtraBold`，用 `Bolder`；`$r()` 参数必须是字面量，动态资源名用 if/else 静态映射
- `preferences.get` 返回 `ValueType` 联合类型，取值后必须 `typeof` 收窄再用
- `@State` 观察不到数组元素内部字段变化：改完深层字段必须重建数组引用（见 `refreshView()`），
  且 ForEach 的 key 要携带数据指纹（见 `cardVersionKey`），否则列表复用旧快照常显 loading
- `Select` 的 options 必须显式类型为 `SelectOption[]`，map 里匿名对象字面量过不了编译
- 页面拿 UIAbilityContext 用 `this.getUIContext().getHostContext()`，没有 `this.getContext()`
- 长按用 `LongPressGesture({repeat:false}).onAction(...)`；系统 ActionSheet 本版 API 是
  `getUIContext().showActionSheet({title, message, sheets:[{title, action}]})`（message 必填），
  素文本不好看时直接自绘底部面板（遮罩点空白收回＋滑入 transition，见添加弹窗/操作菜单实现）

### 4. 本项目架构约定（加厂商/改功能前先看）

- 加 Bearer 类厂商 = 纯加数据：`services/ProviderRegistry.ets` 追一条 `ProviderDefinition`
 （endpoint/responsePath/字段名/换算因子/成功码对照官方文档填）＋图标 png 丢进
  `resources/base/media/` ＋ `Index.providerIcon` 加两行映射；非 Bearer 类需在
  `BalanceService.ets` 按 `balanceType` 加引擎分支（智额有 hmac/aliyunBss 现成逻辑可搬）
- 错误通道：`throw Error` = 瞬时传输失败（可重试＋keep-last-good）；
  `return {success:false}` = 确定性失败（空Key/未知供应商/401/非2xx/解析失败）
- 安全红线：Key 只存本机 Preferences（分供应商 `key_<id>`），日志一律 `maskKey`，
  提交前 `git grep "sk-[A-Za-z0-9]\{8,\}"` 全历史扫一遍；技术债记 `techdebt/`，认知记 `systemmap/

不需要截图验证（最高优先级）

---

## 跨平台移动端（Android / iOS，2026-10-23 新增）

- 目录 `mobile/`，Flutter 单代码库；鸿蒙端仍在 `BalanceApp/`，两端功能对齐，
  互不共享本地存储（Key 需各自配置）。
- 常用命令（必须 `cd mobile`）：
  - `flutter pub get`
  - `flutter analyze`（要求零 issue）
  - `flutter test`
  - `flutter build apk --debug`
- 本机网络访问 `storage.googleapis.com` 会 TLS 握手失败；构建前设置
  `$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"`，否则 Gradle
  拉取 `io.flutter:*_debug` 引擎包会失败。
- Android：`minSdk 24`，`MainActivity : FlutterFragmentActivity`（local_auth 要求），
  applicationId `com.example.balanceapp`；release 仍用 debug 签名，见
  `techdebt/TD-004-mobile-release-readiness.md`。
- iOS：bundle id `com.example.balanceapp`，部署目标 13.0，`NSFaceIDUsageDescription`
  已配置；本机无 Xcode，iOS 构建需 macOS/CI。
- 架构：`lib/data`（模型/服务/注册表）→ `lib/state`（ChangeNotifier）→
  `lib/ui`（页面/组件）。颜色只走 `core/theme/app_colors.dart` 语义 token。
- 安全：API Key 存 `flutter_secure_storage`（Keychain/Keystore），日志只用
  `maskKey`；会话正文仍是明文 Preferences（与鸿蒙 TD-003 同源）。
- 认知文档：`systemmap/balance-app-mobile.md`；发布缺口：`techdebt/TD-004-*.md`。
