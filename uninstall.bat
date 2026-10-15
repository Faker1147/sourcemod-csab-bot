@echo off
setlocal
set GAME_DIR=%1
if "%GAME_DIR%"=="" set GAME_DIR=.
set SM_DIR=%GAME_DIR%\addons\sourcemod

del /Q "%SM_DIR%\plugins\csab_bot.smx"     2>nul
del /Q "%SM_DIR%\scripting\csab_bot.sp"    2>nul
rmdir /S /Q "%SM_DIR%\configs\csab_bot"    2>nul
echo [CSAB] 已卸载
endlocal
