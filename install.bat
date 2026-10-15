@echo off
setlocal

set GAME_DIR=%1
if "%GAME_DIR%"=="" set GAME_DIR=.
set SM_DIR=%GAME_DIR%\addons\sourcemod

echo ==== CSAB Bot Pack v2.0 安装 ====
if not exist "%SM_DIR%" (echo [错误] 未找到 SourceMod: %SM_DIR% & exit /b 1)

if not exist "%SM_DIR%\scripting"         mkdir "%SM_DIR%\scripting"
if not exist "%SM_DIR%\plugins"           mkdir "%SM_DIR%\plugins"
if not exist "%SM_DIR%\configs\csab_bot"  mkdir "%SM_DIR%\configs\csab_bot"

copy /Y addons\sourcemod\scripting\csab_bot.sp   "%SM_DIR%\scripting\"
copy /Y addons\sourcemod\configs\csab_bot\*.cfg  "%SM_DIR%\configs\csab_bot\"

if exist "addons\sourcemod\plugins\csab_bot.smx" (
    copy /Y addons\sourcemod\plugins\csab_bot.smx "%SM_DIR%\plugins\"
    echo [OK] 已安装 csab_bot.smx
) else (
    echo [提示] 请编译 csab_bot.sp 后放入 plugins/
)

echo ==== 安装完成 ====
endlocal