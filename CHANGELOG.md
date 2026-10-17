# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [2.1.0]

### 新增
- 「队友是否算敌人」开关：ConVar `csab_teammates_enemy`（默认 `0`），以及管理员命令 `sm_csabff`
- 阵营武器限制：BOT 只会购买当前阵营可用的枪（CT 不买 AK、T 不买 M4），自动购买与 `sm_csabbuy` 同时生效

### 优化
- 移除运行时 `StringMap` 武器价格表，改用静态常量数组，减少句柄与堆分配
- 精简数组尺寸：`MAX_PRIORITY` 32→16、`MAX_BEHAVIOR` 16→12、武器名 32→24、BOT 名 64→40、行为名 32→24
- 插件数据段（Data size）由 46012 字节降至 28096 字节（约 −39%）

## [2.0.0]

### 新增
- 独立的 CSAB BOT 系统，与官方 ZBot 完全隔离、可共存
- 6 个行为档：`csab` / `csab_sniper` / `csab_rifler` / `csab_defense` / `csab_eco` / `csab_rookie`
- 120 条 csab 系列 BOT 名单
- 玩家可接管 BOT：瞄准（`+botaim`）、跟随走位（`+botmove`）、手动购买（`sm_csabbuy`）
- 按 behavior 优先级的自动购买与自动护甲
- `csab_*` 服务器命令体系，不 Hook 任何 `bot_*` 命令

### 说明
- 需要 SourceMod 1.11+
- 一键停用：`csab_enabled 0`
