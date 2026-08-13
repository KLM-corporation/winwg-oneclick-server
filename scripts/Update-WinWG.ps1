<#
.SYNOPSIS
  Updates the local WinWG OneClick Server repository.

.DESCRIPTION
  If the project was cloned with Git, this script fetches and pulls the current branch.
  If the project was downloaded as a ZIP/release without .git metadata, it does not overwrite
  files automatically; instead it opens the latest GitHub release page.
#>
[CmdletBinding()]
param(
    [string]$RepositoryUrl = "https://github.com/KLM-corporation/winwg-oneclick-server.git",
    [string]$ReleasePage = "https://github.com/KLM-corporation/winwg-oneclick-server/releases/latest"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Ok([string]$Text) {
    Write-Host "OK - $Text" -ForegroundColor Green
}

function Write-Warn([string]$Text) {
    Write-Host "WARNING / ATTENTION - $Text" -ForegroundColor Yellow
}

function Test-GitRepository([string]$Path) {
    return (Test-Path (Join-Path $Path ".git"))
}

function Get-CurrentBranch {
    $branch = (& git branch --show-current 2>$null).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) { return $null }
    return $branch
}

function Test-LocalChanges {
    $status = (& git status --porcelain 2>$null)
    return (-not [string]::IsNullOrWhiteSpace(($status | Out-String).Trim()))
}

$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot

Write-Host "WinWG OneClick Server - updater / mise a jour" -ForegroundColor Green
Write-Host "Project / Projet: $projectRoot"

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Write-Warn "Git is not installed / Git n'est pas installe."
    Write-Host "Opening latest release page / Ouverture de la derniere release :" -ForegroundColor Cyan
    Write-Host $ReleasePage
    Start-Process $ReleasePage
    exit 0
}

if (-not (Test-GitRepository -Path $projectRoot)) {
    Write-Warn "This folder is not a Git clone / Ce dossier n'est pas un clone Git."
    Write-Host "Automatic overwrite is disabled to avoid losing local files." -ForegroundColor Yellow
    Write-Host "La mise a jour automatique est desactivee pour eviter de perdre des fichiers locaux." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Download the latest ZIP here / Telecharge le dernier ZIP ici:" -ForegroundColor Cyan
    Write-Host $ReleasePage
    Start-Process $ReleasePage
    exit 0
}

Write-Step "Checking repository state / Verification du depot"
$branch = Get-CurrentBranch
if (-not $branch) {
    throw "Unable to detect current Git branch / Impossible de detecter la branche Git actuelle."
}
Write-Host "Current branch / Branche actuelle : $branch"

$remoteUrl = (& git remote get-url origin 2>$null).Trim()
if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
    Write-Warn "No origin remote found. Adding origin: $RepositoryUrl"
    git remote add origin $RepositoryUrl
} else {
    Write-Host "Origin: $remoteUrl"
}

if (Test-LocalChanges) {
    Write-Warn "Local changes detected / Modifications locales detectees."
    Write-Host "The updater will not overwrite local changes." -ForegroundColor Yellow
    Write-Host "Le script ne va pas ecraser tes changements locaux." -ForegroundColor Yellow
    Write-Host ""
    git status --short
    Write-Host ""
    Write-Host "Commit/stash your changes, or clone a fresh copy." -ForegroundColor Yellow
    Write-Host "Commit/stash tes changements, ou reclone le projet proprement." -ForegroundColor Yellow
    exit 1
}

Write-Step "Fetching latest changes / Recuperation des dernieres modifications"
git fetch origin --prune

Write-Step "Updating current branch / Mise a jour de la branche actuelle"
$pullOutput = & git pull --ff-only origin $branch 2>&1
$exit = $LASTEXITCODE
$pullText = ($pullOutput | Out-String).Trim()
if (-not [string]::IsNullOrWhiteSpace($pullText)) { Write-Host $pullText }
if ($exit -ne 0) {
    throw "Git pull failed / Echec de git pull. Try manual update: git pull --rebase origin $branch"
}

Write-Ok "Project updated / Projet mis a jour"
Write-Host ""
Write-Host "You can now run / Tu peux maintenant lancer :" -ForegroundColor Cyan
Write-Host "  INSTALLER-ONE-CLICK.bat"
Write-Host "  SERVER-CONSOLE.bat"
Write-Host "  UNINSTALLER-ONE-CLICK.bat"
