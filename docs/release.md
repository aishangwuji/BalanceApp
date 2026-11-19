# 发布流程（GitHub + Gitee 双源）

应用内「检查更新」读的是 **release**，不是 tag：`tag_name` 作版本号，`body` 作更新说明，
`assets` 里的 `.hap` 作下载直链。因此每次发布必须同时满足：

1. `BalanceApp/AppScope/app.json5` 的 `versionName` 递增（`versionCode` 也要递增，安装器用它比较）；
2. 打 `vX.Y.Z` 标签；
3. release 里挂上 `BalanceApp-X.Y.Z.hap`；
4. GitHub 与 Gitee 两个源都发（应用先查 Gitee、失败再查 GitHub）。

## 1. 改版本号

```powershell
# BalanceApp/AppScope/app.json5
"versionCode": 1000001,
"versionName": "1.0.1",
```

版本比较是逐段数值比较（`1.0.10 > 1.0.9`），不要用日期式版本号。

## 2. 构建 HAP

```powershell
$env:DEVECO_SDK_HOME = "D:/Program Files/Huawei/DevEco Studio/sdk"
cd BalanceApp
node "D:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" assembleHap `
  --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

或直接跑 `./scripts/release.ps1`（自动读版本号、构建、拷贝到 `dist/`）。

产物：`BalanceApp/entry/build/default/outputs/default/entry-default-signed.hap`。

> 说明：debug 签名的 HAP 只能在签名时登记过的设备上安装；开源分发的安装包需要读者用
> DevEco 自行签名，或你用自己的发布证书签名后上传。仓库只发源码也可以，HAP 属于便利附件。

## 3. 提交并打标签

```powershell
git add -A
git commit -m "chore: 发布 v1.0.1"
git tag v1.0.1
git push origin main
git push origin v1.0.1
```

## 4. 发 GitHub Release

```powershell
gh release create v1.0.1 "dist/BalanceApp-1.0.1.hap" `
  --title "v1.0.1" `
  --notes "## 变更`n- 修复 xxx`n- 新增 yyy"
```

`--notes` 的内容会原样显示在应用的更新弹窗里（应用内截断到 600 字），建议用简短的
「变更」列表，而不是整段提交日志。

## 5. 发 Gitee Release 并同步仓库

```powershell
gitee release create --repo aishangwuji/BalanceApp --tag v1.0.1 `
  --title "v1.0.1" --notes "变更说明" --attach "dist/BalanceApp-1.0.1.hap"

git push gitee main
git push gitee v1.0.1
```

`gitee release create` 的参数以 `gitee release create --help` 为准；如果 CLI 版本不支持
`--attach`，就在 Gitee 网页的「发行版」里手动上传附件。

## 6. 校验

```powershell
gh release view v1.0.1 --json tagName,assets
gitee release view v1.0.1 -R aishangwuji/BalanceApp
```

再在应用里「设置 → 关于 → 检查更新」确认弹窗能拿到说明与下载链接。

## 双源维护

```powershell
git remote -v
# origin  https://github.com/aishangwuji/BalanceApp.git
# gitee   https://gitee.com/aishangwuji/BalanceApp.git

# 每次发布后同步两边
git push origin main --tags
git push gitee  main --tags
```

若只想推代码、不发 release，两个 `git push` 即可；应用内检查会因为没有新 tag 而静默跳过。

## 常见问题

- **检查更新提示失败**：Gitee/GitHub API 都可能被网络限制；应用静默失败不打扰用户，
  设置页会提示「暂时无法检查更新」。确认 release 是公开的（私有仓库的 API 需要 token）。
- **弹窗里没有下载按钮**：release 没挂 `.hap` 资产时，应用回退到 release 页面链接。
- **装了新版还提示更新**：`versionName` 没改，或 release tag 与 `versionName` 不一致。
