<#
.SYNOPSIS
  Active, desactive, redemarre ou affiche le statut du service WireGuard du projet.

.DESCRIPTION
  Le serveur WireGuard Windows tourne comme un service Windows nomme :
  WireGuardTunnel$wg-phone-server

  Ce script permet de :
  - activer/demarrer le serveur VPN ;
  - desactiver/arreter le serveur VPN ;
  - redemarrer le serveur VPN ;
  - afficher son statut.

  Les fichiers de configuration ne sont pas supprimes.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu','Start','Stop','Restart','Status')]
    [string]$Action = 'Menu',

    [string]$TunnelName = 'wg-phone-server',
    [string]$BaseDir = "$env:ProgramData\WireGuardPhoneServer"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
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
    Write-Host "ATTENTION - $Text" -ForegroundColor Yellow
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Ce script doit etre lance en administrateur. Utilise WIREGUARD-SERVICE-TOGGLE.bat."
    }
}

function Invoke-ExternalNoThrow([string]$FileName, [string[]]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $escapedArguments = $Arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }
    $psi.Arguments = ($escapedArguments -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

function Get-WireGuardExe {
    $wireguardExe = Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'
    if (-not (Test-Path $wireguardExe)) {
        throw "wireguard.exe introuvable. Installe WireGuard ou relance INSTALLER-ONE-CLICK.bat."
    }
    return $wireguardExe
}

function Get-WgExe {
    $wgExe = Join-Path $env:ProgramFiles 'WireGuard\wg.exe'
    if (-not (Test-Path $wgExe)) { return $null }
    return $wgExe
}

function Get-ServerConfigPath([string]$TunnelName, [string]$BaseDir) {
    return Join-Path $BaseDir "server\$TunnelName.conf"
}

function Get-TunnelService([string]$TunnelName) {
    $serviceName = "WireGuardTunnel`$$TunnelName"
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        $svc = Get-Service -Name "WireGuardTunnel*$TunnelName*" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    return $svc
}

function Show-Status([string]$TunnelName, [string]$BaseDir) {
    Write-Step "Statut du serveur WireGuard"
    $configPath = Get-ServerConfigPath -TunnelName $TunnelName -BaseDir $BaseDir
    $svc = Get-TunnelService -TunnelName $TunnelName

    Write-Host "Tunnel        : $TunnelName"
    Write-Host "Config serveur: $configPath"

    if ($svc) {
        $color = if ($svc.Status -eq 'Running') { 'Green' } else { 'Yellow' }
        Write-Host "Service       : $($svc.Name) - $($svc.Status)" -ForegroundColor $color
    } else {
        Write-Host "Service       : non installe / desactive" -ForegroundColor Yellow
    }

    if (Test-Path $configPath) {
        Write-Host "Config        : presente" -ForegroundColor Green
    } else {
        Write-Host "Config        : manquante" -ForegroundColor Red
    }

    $wgExe = Get-WgExe
    if ($wgExe -and $svc -and $svc.Status -eq 'Running') {
        Write-Host ""
        Write-Host "wg show:" -ForegroundColor Cyan
        & $wgExe show $TunnelName 2>&1 | Out-Host
    }
}

function Enable-Tunnel([string]$TunnelName, [string]$BaseDir) {
    Write-Step "Activation/demarrage du serveur WireGuard"
    $wireguardExe = Get-WireGuardExe
    $configPath = Get-ServerConfigPath -TunnelName $TunnelName -BaseDir $BaseDir

    if (-not (Test-Path $configPath)) {
        throw "Configuration serveur introuvable : $configPath. Relance INSTALLER-ONE-CLICK.bat."
    }

    $svc = Get-TunnelService -TunnelName $TunnelName
    if ($svc) {
        if ($svc.Status -ne 'Running') {
            Start-Service -Name $svc.Name
            Start-Sleep -Seconds 1
            Write-Ok "Service demarre : $($svc.Name)"
        } else {
            Write-Ok "Service deja actif : $($svc.Name)"
        }
        return
    }

    $result = Invoke-ExternalNoThrow -FileName $wireguardExe -Arguments @('/installtunnelservice', $configPath)
    $msg = ($result.StdErr + $result.StdOut).Trim()
    if ($result.ExitCode -ne 0) {
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "wireguard.exe a retourne le code $($result.ExitCode)" }
        throw $msg
    }
    Write-Ok "Service installe et demarre : WireGuardTunnel`$$TunnelName"
}

function Disable-Tunnel([string]$TunnelName) {
    Write-Step "Desactivation/arret du serveur WireGuard"
    $wireguardExe = Get-WireGuardExe
    $svc = Get-TunnelService -TunnelName $TunnelName

    if (-not $svc) {
        Write-Ok "Service deja desactive / non installe"
        return
    }

    # /uninstalltunnelservice arrete et supprime le service WireGuard, sans supprimer les configs.
    $result = Invoke-ExternalNoThrow -FileName $wireguardExe -Arguments @('/uninstalltunnelservice', $TunnelName)
    $msg = ($result.StdErr + $result.StdOut).Trim()
    if ($result.ExitCode -ne 0 -and $msg -notmatch 'does not exist|n.existe pas|service.*introuvable|specified service') {
        throw $msg
    }
    Write-Ok "Service desactive : WireGuardTunnel`$$TunnelName"
    Write-Host "Les configurations sont conservees dans $BaseDir" -ForegroundColor DarkGray
}

function Restart-Tunnel([string]$TunnelName, [string]$BaseDir) {
    Write-Step "Redemarrage du serveur WireGuard"
    Disable-Tunnel -TunnelName $TunnelName
    Start-Sleep -Seconds 1
    Enable-Tunnel -TunnelName $TunnelName -BaseDir $BaseDir
}

function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Host "WinWG OneClick Server - Gestion du service" -ForegroundColor Green
        Write-Host "==================================================" -ForegroundColor DarkGray
        Show-Status -TunnelName $TunnelName -BaseDir $BaseDir
        Write-Host ""
        Write-Host "Actions:" -ForegroundColor Cyan
        Write-Host "1 - Activer / demarrer le serveur VPN"
        Write-Host "2 - Desactiver / arreter le serveur VPN"
        Write-Host "3 - Redemarrer le serveur VPN"
        Write-Host "4 - Rafraichir le statut"
        Write-Host "Q - Quitter"
        Write-Host ""
        $choice = Read-Host "Choix"
        switch ($choice.Trim().ToLowerInvariant()) {
            '1' { Enable-Tunnel -TunnelName $TunnelName -BaseDir $BaseDir; pause }
            '2' { Disable-Tunnel -TunnelName $TunnelName; pause }
            '3' { Restart-Tunnel -TunnelName $TunnelName -BaseDir $BaseDir; pause }
            '4' { }
            'q' { return }
            default { Write-Warn "Choix invalide"; pause }
        }
    }
}

try {
    Assert-Admin
    $host.UI.RawUI.WindowTitle = "WinWG OneClick Server - Gestion service"

    switch ($Action) {
        'Menu' { Show-Menu }
        'Start' { Enable-Tunnel -TunnelName $TunnelName -BaseDir $BaseDir; Show-Status -TunnelName $TunnelName -BaseDir $BaseDir }
        'Stop' { Disable-Tunnel -TunnelName $TunnelName; Show-Status -TunnelName $TunnelName -BaseDir $BaseDir }
        'Restart' { Restart-Tunnel -TunnelName $TunnelName -BaseDir $BaseDir; Show-Status -TunnelName $TunnelName -BaseDir $BaseDir }
        'Status' { Show-Status -TunnelName $TunnelName -BaseDir $BaseDir }
    }
} catch {
    Write-Host ""
    Write-Host "ERREUR : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
