# 发布辅助脚本：读版本号 → 构建 HAP → 拷贝到 dist/ → 打印后续发布命令。
# 用法（仓库根目录）：pwsh ./scripts/release.ps1
# 只做本地构建与打包，不自动打 tag / 发 release（发布动作由人确认后执行）。

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$appScope = Join-Path $root 'BalanceApp/AppScope/app.json5'
$hvigorDir = Join-Path $root 'BalanceApp'
$outputDir = Join-Path $root 'BalanceApp/entry/build/default/outputs/default'
$hapName = 'entry-default-signed.hap'
$distDir = Join-Path $root 'dist'

if (-not (Test-Path $appScope)) {
  throw "找不到 $appScope"
}

$versionName = (Select-String -Path $appScope -Pattern '"versionName"\s*:\s*"([^"]+)"').Matches[0].Groups[1].Value
$versionCode = (Select-String -Path $appScope -Pattern '"versionCode"\s*:\s*(\d+)').Matches[0].Groups[1].Value
Write-Host "构建 BalanceApp v$versionName (versionCode=$versionCode)"

$env:DEVECO_SDK_HOME = 'D:/Program Files/Huawei/DevEco Studio/sdk'
$node = 'D:/Program Files/Huawei/DevEco Studio/tools/node/node.exe'
$hvigor = 'D:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js'

Push-Location $hvigorDir
try {
  & $node $hvigor assembleHap --mode module -p module=entry@default -p product=default `
    -p buildMode=debug --no-daemon
  if ($LASTEXITCODE -ne 0) {
    throw "hvigor 构建失败（exit $LASTEXITCODE）"
  }
} finally {
  Pop-Location
}

$hap = Join-Path $outputDir $hapName
if (-not (Test-Path $hap)) {
  throw "构建产物不存在：$hap"
}

New-Item -ItemType Directory -Force -Path $distDir | Out-Null
$target = Join-Path $distDir "BalanceApp-$versionName.hap"
Copy-Item $hap $target -Force
$sizeMb = [math]::Round((Get-Item $target).Length / 1MB, 1)

Write-Host ""
Write-Host "产物：$target ($sizeMb MB)"
Write-Host ""
Write-Host "后续手动执行（发布前先确认版本号与 changelog）："
Write-Host "  git add -A; git commit -m `"chore: 发布 v$versionName`"; git tag v$versionName"
Write-Host "  git push origin main --tags                                    # origin = Gitee"
Write-Host "  gh workflow run mirror-from-gitee.yml --repo aishangwuji/BalanceApp   # 同步到 GitHub"
Write-Host "  gitee release create -R aishangwuji/BalanceApp --tag v$versionName -n `"v$versionName`" -b `"变更说明`""
Write-Host "  # Gitee 附件（CLI 无 --attach）："
Write-Host "  `$id = (gitee api '/repos/aishangwuji/BalanceApp/releases/tags/v$versionName' | ConvertFrom-Json).id"
Write-Host "  curl.exe -s -X POST `"https://gitee.com/api/v5/repos/aishangwuji/BalanceApp/releases/`$id/attach_files`" -F `"access_token=`$(gitee auth token)`" -F `"file=@$target`""
Write-Host "  gh release create v$versionName `"$target`" --repo aishangwuji/BalanceApp --title `"v$versionName`" --notes `"变更说明`""
Write-Host ""
Write-Host "详见 docs/release.md"
