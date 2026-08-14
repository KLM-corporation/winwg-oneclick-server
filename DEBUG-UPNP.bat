@echo off
chcp 65001 >nul
setlocal
REM =============================================================
REM  WinWG OneClick Server - UPnP / PCP / NAT-PMP diagnostic
REM =============================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights / Demande des droits administrateur...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Debug-UPnP.ps1"

echo.
echo Done / Termine. You can close this window / Tu peux fermer cette fenetre.
pause
