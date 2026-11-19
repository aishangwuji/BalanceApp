# 签名与安装

这份文档解释「为什么开源仓库里没有签名材料」以及「不同的人怎么把 openchat 装到自己手机上」。

## 一句话结论

鸿蒙应用必须签名才能安装；**源码开源，签名私有不分发**。每个人用自己的华为开发者账号生成签名，
或者由作者上架应用市场统一分发。

## 为什么签名材料不能进仓库

| 文件 | 作用 | 公开的后果 |
|---|---|---|
| `.p12` | 密钥库（含私钥） | 别人可以用你的身份给任意代码签名，等同身份被盗 |
| `.p7b` | profile（绑定 bundleName + 证书 + 设备列表） | 配合上面的私钥就能冒用你的应用对外发布 |
| `.cer` | 公钥证书 | 单独泄露危害小，但没必要公开 |

所以仓库里 `BalanceApp/build-profile.json5` 的 `signingConfigs` 是**空**的；
`.gitignore` 也不覆盖它（文件本身要入库，只是内容不含签名）。你在本机生成签名后，
那份配置只留在本地：

```powershell
# 让 git 忽略这个文件的本机改动（推荐，配置一次即可）
git update-index --skip-worktree BalanceApp/build-profile.json5
```

## 作者本人：怎么签名

1. DevEco Studio 打开 `BalanceApp/` 工程；
2. *File → Project Structure → Signing Configs* → 勾选 **Automatically generate signature**；
3. 登录华为开发者账号（免费注册即可）；
4. 手机开启开发者模式 + USB 调试，连上电脑；
5. DevEco 自动向 AGC 登记设备 UDID、申请调试证书，并把配置写回 `build-profile.json5`；
6. 点 Run，或命令行 `assembleHap` 后 `hdc install`。

签名材料默认落在 `C:\Users\<user>\.ohos\config\default_<bundle>_*.{p12,cer,p7b}`，**不要复制进仓库**。

> 注意：调试 profile 里登记的是设备 UDID 列表，所以调试包只能装在自己登记过的设备上。

## 其他人：三种方式

### A. 自己构建并签名（推荐给开发者）

按上面「作者本人」的步骤做一遍即可——用自己的开发者账号，生成的签名属于自己，
装自己的设备没有问题。这也是开源项目的标准方式。

### B. 下载 Release 里的 HAP

**只对作者自己的设备有效**。profile 里没有你的 UDID，安装会报：

```
9568320 signature verify failed
```

这不是打包坏了，是签名机制决定的。

### C. 上架 AppGallery

面向普通用户的正规途径：

1. 华为开发者账号完成实名/企业认证；
2. AGC 创建应用（包名 `com.example.openchat`），申请发布证书与 profile（release 类型）；
3. 用发布证书构建，上传 AGC，提交审核；
4. 审核通过后由应用市场分发，任何用户都能装。

调试签名不能用于这条路径。

## 常见错误

| 报错 | 原因 | 解决 |
|---|---|---|
| `9568320 signature verify failed` | HAP 的签名/设备列表不含本机 | 自己签名（方式 A），或用作者登记过的设备 |
| `The bundleName in app.json5 ... does not match the generated SigningConfigs` | 改了 `bundleName` 但沿用旧证书 | 重新生成签名（DevEco → Signing Configs → Fix） |
| `no signature file` | 构建产物是 unsigned 包 | 先完成签名配置再 `assembleHap` |
| 安装报 `install failed due to grant request permissions failed` | 设备未授权 USB 调试 | 手机上确认「允许调试」 |

## 版本升级与签名

- 同一个 `bundleName` + 同一套签名证书 → 覆盖安装、数据保留；
- 换 `bundleName`（例如从 `com.example.balanceapp` 改成 `com.example.openchat`）→ 视为新应用，
  旧数据不共享、旧证书也不能再用，必须重新签名；
- 发布新版只要 `versionName/versionCode` 递增，签名保持一致即可原地升级。

### 命令行签名（可选，等价于 DevEco 图形操作）

```powershell
devecocli auth login          # 浏览器登录华为开发者账号，只需一次
devecocli signature generate --force
```

`signature generate` 会生成 p12/csr/cer/p7b 并写回 `build-profile.json5`，
随后 `hvigorw assembleHap` 即可产出已签名 HAP。
