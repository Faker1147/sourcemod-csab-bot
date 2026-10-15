# CSAB Bot Pack

独立的第三方 BOT 系统，与官方 ZBot **完全隔离、可共存、可停用**。

适用于使用 SourceMod 的 Counter-Strike: Source / Counter-Strike: GO 服务器。

---

## 与官方 ZBot 的关系

| 方面     | 官方 ZBot            | CSAB Bot                        |
| -------- | -------------------- | ------------------------------- |
| 添加命令 | `bot_add`            | `csab_add`                      |
| 踢出命令 | `bot_kick`           | `csab_kick`                     |
| 数量命令 | `bot_quota`          | `csab_quota`                    |
| 名单来源 | `botprofile.db`      | `configs/csab_bot/roster.cfg`   |
| 技能来源 | 引擎内建             | `configs/csab_bot/behavior.cfg` |
| 瞄准     | 引擎原生             | 插件自研插值                    |
| 购买     | 引擎原生             | 按 behavior 优先级              |

两者可在同一服务器同时运行，互不干扰。插件只拦截 `csab_*` 命令，**绝不 Hook `bot_*`**，
因此对原生 ZBot 行为零影响。

## 特性

- 6 个行为档：`csab` / `csab_sniper` / `csab_rifler` / `csab_defense` / `csab_eco` / `csab_rookie`
- 120 个 csab 系列 BOT 名单
- 每档独立配置瞄准速度 / 视野 / 反应 / 误差 / 侵略性 / 购买优先级
- 玩家可接管 BOT：`+botaim` 瞄准、`+botmove` 走位
- 一键停用：`csab_enabled 0`，服务器立即恢复原版 ZBot 行为

## 环境要求

- MetaMod:Source
- SourceMod 1.11 或更高（使用了 `enum struct`、`#pragma newdecls required`）

## 安装

将 `addons/` 覆盖到游戏服务器的 `cstrike`（CS:S）或 `csgo`（CS:GO）目录，
或使用附带脚本：

```bash
# Linux
chmod +x install.sh
./install.sh /path/to/cstrike

# Windows
install.bat C:\path\to\cstrike
```

安装后目录结构：

```
addons/sourcemod/
├── plugins/csab_bot.smx
├── scripting/csab_bot.sp
└── configs/csab_bot/
    ├── behavior.cfg
    ├── roster.cfg
    └── buy_priority.cfg
```

`csab_bot.smx` 需要自行编译（见下文），或从 Releases 下载。

## 编译

需要 SourceMod 的 `spcomp`。在本仓库的 `addons/sourcemod/scripting/` 同级放入
SourceMod 官方 `include/` 后执行：

```bash
# Windows
addons\sourcemod\scripting\spcomp.exe addons\sourcemod\scripting\csab_bot.sp

# Linux
./spcomp addons/sourcemod/scripting/csab_bot.sp
```

生成 `csab_bot.smx`，复制到 `addons/sourcemod/plugins/` 即可。

## 玩家命令

| 命令                          | 说明                          |
| ----------------------------- | ----------------------------- |
| `sm_csab`                     | 打开控制菜单                  |
| `sm_csabspawn [数量]`         | 生成 CSAB BOT（默认 1，上限 10）|
| `sm_csabspawnname <名字\|索引>` | 生成指定名单中的 BOT          |
| `sm_csabkick`                 | 踢出所有 CSAB BOT             |
| `sm_csabinfo`                 | 查看当前控制的 BOT            |
| `sm_csabroster`               | 查看 CSAB 名单                |
| `sm_csabreload`               | 重载 CSAB 配置                |
| `sm_csabaim`                  | 切换 BOT 自动瞄准             |
| `sm_csabfollow`               | 切换 BOT 跟随                 |
| `sm_csabbuy <武器>`           | 给 BOT 买枪                   |
| `sm_csabrelease`              | 释放 BOT 控制                 |
| `+botaim` / `-botaim`         | 快捷键：按住瞄准 / 松开       |
| `+botmove`                    | 快捷键：BOT 前进              |

## 服务器命令

| 命令                | 说明                     |
| ------------------- | ------------------------ |
| `csab_add`          | 生成一个 CSAB BOT        |
| `csab_add_t`        | 生成一个 T 方 CSAB BOT   |
| `csab_add_ct`       | 生成一个 CT 方 CSAB BOT  |
| `csab_kick [名字]`  | 踢出全部 / 指定 CSAB BOT |
| `csab_quota <数量>` | 调整 CSAB BOT 数量       |
| `csab_kill`         | 杀死所有存活的 CSAB BOT  |
| `csab_stop`         | 停止（占位，保留）       |

## ConVar

| ConVar                | 默认 | 说明             |
| --------------------- | ---- | ---------------- |
| `csab_enabled`        | 1    | 总开关           |
| `csab_autobuy`        | 1    | 自动购买主武器   |
| `csab_autobuy_armor`  | 1    | 自动购买护甲     |
| `csab_aim_mult`       | 1.0  | 全局瞄准速度倍率 |

## 行为档配置

`configs/csab_bot/behavior.cfg`：

```sourcepawn
"BotBehavior"
{
    "csab"
    {
        "aim_speed"  "12.0"   // 瞄准旋转速度 (1.0 - 20.0)
        "aim_fov"    "75.0"   // 视野半角 (度)
        "reaction"   "0.08"   // 反应延迟 (秒)
        "aim_error"  "0.6"    // 瞄准误差 (度)
        "aggression" "0.95"   // 侵略性 (0.0 - 1.0)
        "weapons"    "ak47,m4a1,awp,deagle"  // 购买优先级
    }
}
```

## 卸载

```bash
# Linux
./uninstall.sh /path/to/cstrike

# Windows
uninstall.bat C:\path\to\cstrike
```

## 目录结构

```
.
├── addons/sourcemod/
│   ├── scripting/csab_bot.sp          # 插件源码
│   └── configs/csab_bot/              # 运行时配置
│       ├── behavior.cfg
│       ├── roster.cfg
│       └── buy_priority.cfg
├── install.bat / install.sh
├── uninstall.bat / uninstall.sh
├── CHANGELOG.md
└── LICENSE
```

## 许可

GPL-3.0-or-later，详见 [LICENSE](LICENSE)。
