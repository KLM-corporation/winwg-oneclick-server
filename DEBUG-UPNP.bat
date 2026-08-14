@echo off
chcp 65001 >nul
setlocal
REM =============================================================
REM  WinWG OneClick Server - UPnP / PCP / NAT-PMP diagnostic
REM =============================================================

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Debug-UPnP.ps1"

echo.
echo Done / Termine. You can close this window / Tu peux fermer cette fenetre.
pause
