<#
.SYNOPSIS
  Supprime un client WireGuard du fichier serveur.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ClientName,

    [string]$TunnelName = "wg-phone-server"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Lance PowerShell en administrateur."
    }
}


function Invoke-WireGuardNoThrow([string]$WireGuardExe, [string[]]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $WireGuardExe
    # Compatible Windows PowerShell 5.1 : ProcessStartInfo.ArgumentList n'existe pas partout.
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


function Restart-WireGuardTunnelSafely([string]$WireGuardExe, [string]$TunnelName, [string]$ConfigPath) {
    Write-Host "Rechargement du service WireGuard..."

    if (-not (Test-Path $WireGuardExe)) {
        Write-Warning "wireguard.exe introuvable, impossible de recharger le service automatiquement."
        return $false
    }

    $remove = Invoke-WireGuardNoThrow -WireGuardExe $WireGuardExe -Arguments @('/uninstalltunnelservice', $TunnelName)
    if ($remove.ExitCode -ne 0 -and $remove.StdErr -notmatch 'does not exist|n.existe pas|service.*introuvable|specified service') {
        Write-Warning "Ancien tunnel non supprime proprement : $($remove.StdErr.Trim()) $($remove.StdOut.Trim())"
    }

    Start-Sleep -Seconds 2

    $install = Invoke-WireGuardNoThrow -WireGuardExe $WireGuardExe -Arguments @('/installtunnelservice', $ConfigPath)
    if ($install.ExitCode -eq 0) {
        Write-Host "Service WireGuard recharge."
        return $true
    }

    $msg = ($install.StdErr + $install.StdOut).Trim()
    Write-Warning "Premier rechargement echoue : $msg"
    Write-Warning "Nouvelle tentative dans 3 secondes..."
    Start-Sleep -Seconds 3

    $install2 = Invoke-WireGuardNoThrow -WireGuardExe $WireGuardExe -Arguments @('/installtunnelservice', $ConfigPath)
    if ($install2.ExitCode -eq 0) {
        Write-Host "Service WireGuard recharge apres deuxieme tentative."
        return $true
    }

    $msg2 = ($install2.StdErr + $install2.StdOut).Trim()
    Write-Warning "Configuration modifiee, mais le service WireGuard n'a pas pu etre recharge automatiquement : $msg2"
    Write-Warning "Utilise SERVER-CONSOLE.bat puis l'action 3 pour redemarrer le serveur VPN."
    return $false
}

Assert-Admin
$wireguardExe = Join-Path $env:ProgramFiles "WireGuard\wireguard.exe"
$baseDir = Join-Path $env:ProgramData "WireGuardPhoneServer"
$serverConfigPath = Join-Path $baseDir "server\$TunnelName.conf"
$clientConfigPath = Join-Path $baseDir "clients\$ClientName.conf"

if (-not (Test-Path $serverConfigPath)) { throw "Configuration serveur introuvable : $serverConfigPath" }

$config = Get-Content $serverConfigPath -Raw
$pattern = "(?ms)^#\s*$([regex]::Escape($ClientName))\s*\r?\n\[Peer\]\s*\r?\nPublicKey\s*=\s*\S+\s*\r?\nPresharedKey\s*=\s*\S+\s*\r?\nAllowedIPs\s*=\s*[^\r\n]+\s*\r?\n?"
$newConfig = [regex]::Replace($config, $pattern, "")

if ($newConfig -eq $config) {
    throw "Peer '$ClientName' introuvable dans $serverConfigPath"
}

Set-Content -Path $serverConfigPath -Value $newConfig -Encoding ASCII
if (Test-Path $clientConfigPath) { Remove-Item $clientConfigPath -Force }

$reloadOk = Restart-WireGuardTunnelSafely -WireGuardExe $wireguardExe -TunnelName $TunnelName -ConfigPath $serverConfigPath
if (-not $reloadOk) {
    Write-Warning "L'operation sur le peer est faite, mais le service doit etre redemarre manuellement."
}

Write-Host "✅ Client supprimé : $ClientName" -ForegroundColor Green
