#!/bin/bash
GAME_DIR="${1:-.}"
SM_DIR="$GAME_DIR/addons/sourcemod"

rm -f "$SM_DIR/plugins/csab_bot.smx"
rm -f "$SM_DIR/scripting/csab_bot.sp"
rm -rf "$SM_DIR/configs/csab_bot"
echo "[CSAB] 已卸载"