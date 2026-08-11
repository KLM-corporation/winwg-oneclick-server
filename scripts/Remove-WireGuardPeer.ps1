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

$remove = Invoke-WireGuardNoThrow -WireGuardExe $wireguardExe -Arguments @('/uninstalltunnelservice', $TunnelName)
if ($remove.ExitCode -ne 0 -and $remove.StdErr -notmatch 'does not exist|n.existe pas|service.*introuvable') { Write-Host "Ancien tunnel non supprimé : $($remove.StdErr.Trim())" -ForegroundColor Yellow }
$install = Invoke-WireGuardNoThrow -WireGuardExe $wireguardExe -Arguments @('/installtunnelservice', $serverConfigPath)
if ($install.ExitCode -ne 0) { throw (($install.StdErr + $install.StdOut).Trim()) }

Write-Host "✅ Client supprimé : $ClientName" -ForegroundColor Green
