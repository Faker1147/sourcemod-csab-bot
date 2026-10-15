# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

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
