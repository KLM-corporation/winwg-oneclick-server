@echo off
chcp 65001 >nul
setlocal
REM =============================================================
REM  WinWG OneClick Server - updater / mise a jour
REM  Works best when the project was cloned with Git.
REM =============================================================

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Update-WinWG.ps1"

echo.
echo Done / Termine. You can close this window / Tu peux fermer cette fenetre.
pause
