@echo off
chcp 65001 >nul
setlocal
REM =============================================================
REM  WinWG OneClick Server - console serveur
REM  Affiche l'etat du tunnel, firewall, NAT et handshakes.
REM =============================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights / Demande des droits administrateur...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\WireGuard-Server-Console.ps1"
