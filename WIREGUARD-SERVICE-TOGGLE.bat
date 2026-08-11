@echo off
chcp 65001 >nul
setlocal
REM =============================================================
REM  WinWG OneClick Server - activer/desactiver service
REM  Double-clique ce fichier. Il demandera les droits admin UAC.
REM =============================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Demande des droits administrateur...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Manage-WireGuard-Service.ps1"

echo.
echo Termine. Tu peux fermer cette fenetre.
pause
