@echo off
chcp 65001 >nul
setlocal
REM =============================================================
REM  Temporary diagnostic: test port mapping with miniupnpc/upnpc
REM =============================================================

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-MiniUPnPc.ps1"

echo.
echo Done / Termine. You can close this window / Tu peux fermer cette fenetre.
pause
