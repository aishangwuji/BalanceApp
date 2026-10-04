---
covered_paths:
  - BalanceApp/entry/src/main/ets/services/BalanceService.ets
  - BalanceApp/entry/src/main/ets/pages/Index.ets
  - BalanceApp/entry/src/main/module.json5
last_verified_commit: uncommitted (no git repo yet)
---

# BalanceApp systemmap（初始）

## 入口点

- `BalanceApp/entry/src/main/ets/pages/Index.ets` — Dashboard 总览（总资产 Hero + 服务商卡片 + 添加弹窗 + 空态），对齐智额 dashboard_screen/HeroStatsCard/PremiumProviderCard 前端形式。
- `BalanceApp/entry/src/main/ets/services/ProviderRegistry.ets` — 数据驱动注册表。
- `BalanceApp/entry/src/main/ets/services/BalanceService.ets` — 通用查询引擎 + 错误通道。

## 核心数据模型

- `BalanceInfo { providerId/total/used/available/currency/updatedAt }`（ProviderRegistry.ets，对齐智额 balance_info.dart）
- `ProviderDefinition { id/name/baseUrl/category/balanceType/balanceConfig/brandColor }` + `PROVIDERS[7]`（ProviderRegistry.ets，对齐智额 registry，酒馆除外；2026-10-04 新增 Kimi（月之暗面）api.moonshot.cn/v1/users/me/balance，成功语义 code==0）
- 通用 bearer 引擎：responsePath 导航 + 数组求和 + 换算因子 + used 推导（BalanceService.ets，对齐智额 BearerBalanceAdapter；OpenRouter available 对称推导为本侧修正）
- 本地持久化：Preferences `balance_prefs` 存 `addedIds` + `key_<id>`（Index.ets）
- UI 状态：`records: ProviderRecord[]` + `refreshView()` 重建数组推刷新 + ForEach 数据指纹 key 防复用旧快照（Index.ets，ArkTS @State 深层观察不到的补偿）
- 品牌图标：`resources/base/media/` 下 deepseek/kimi（取自智额）+ siliconflow/stepfun/openrouter/novita（Google favicons 128px）；`ProviderDefinition.icon` + `Index.providerIcon` 静态 $r 映射（$r 不支持动态拼接）

## 本次任务所涉现状

- 空目录脚手架 → `devecocli create BalanceApp (API 24, com.example.balanceapp)`，debug 构建成功。
- 真机 `6UNBB26820047956`（UDID `5FB0F2328…BD1E4`）已在 AGC 登记，`devecocli signature generate`
  自动签名成功，`devecocli run` 签名构建+安装成功，`aa start` 启动成功，真机截屏确认
  查询页正常渲染（供应商选择/BaseURL/Key输入/查询-清空按钮/底部说明）。
- 产物：签名 HAP 位于 `entry/build/default/outputs/default/`（-signed）。
- 2026-10-04 dashboard 对齐验证：DeepSeek 真 Key 查询 258ms 回 200，Hero ¥4.89 与卡片
  ¥4.8900/总额/已用/进度条一致；修复过 ForEach 复用旧快照致卡片常显查询中
 （数据指纹 key + refreshView 重建数组，详见 Index.ets cardVersionKey/refreshView）。
