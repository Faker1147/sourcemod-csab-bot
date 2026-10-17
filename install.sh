#!/bin/bash
# ==========================================================
#  CSAB Bot Pack - 安装脚本 (Linux)
#  用法: ./install.sh /path/to/cstrike
# ==========================================================
set -e

GAME_DIR="${1:-.}"
SM_DIR="$GAME_DIR/addons/sourcemod"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==== CSAB Bot Pack v2.1 安装 ===="

if [ ! -d "$SM_DIR" ]; then
    echo "[错误] 未找到 SourceMod: $SM_DIR"
    exit 1
fi

mkdir -p "$SM_DIR/scripting" "$SM_DIR/plugins" "$SM_DIR/configs/csab_bot"

cp "$SRC_DIR/addons/sourcemod/scripting/csab_bot.sp"      "$SM_DIR/scripting/"
cp "$SRC_DIR"/addons/sourcemod/configs/csab_bot/*.cfg     "$SM_DIR/configs/csab_bot/"

if [ -f "$SRC_DIR/addons/sourcemod/plugins/csab_bot.smx" ]; then
    cp "$SRC_DIR/addons/sourcemod/plugins/csab_bot.smx"   "$SM_DIR/plugins/"
    echo "[OK] 已安装 csab_bot.smx"
else
    echo "[提示] 请编译 csab_bot.sp 后放入 plugins/"
fi

echo "==== 安装完成 ===="
