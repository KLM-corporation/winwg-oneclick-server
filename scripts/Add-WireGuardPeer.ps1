<#
.SYNOPSIS
  Ajoute un client WireGuard au serveur Windows existant.

.EXAMPLE
  .\Add-WireGuardPeer.ps1 -ClientName "android" -Endpoint "vpn-maison.duckdns.org"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ClientName,

    [Parameter(Mandatory=$true)]
    [string]$Endpoint,

    [int]$ClientNumber = 3,
    [int]$ListenPort = 51820,
    [string]$Dns = "1.1.1.1, 8.8.8.8",
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
function Test-WgKey([string]$Key, [string]$Label) {
    $clean = $Key.Trim()
    if ($clean -notmatch '^[A-Za-z0-9+/]{43}=$') {
        throw "$Label invalide generee par wg.exe. Sortie recue: '$clean'"
    }
    return $clean
}

function Invoke-WgSimple([string]$WgExe, [string]$Command) {
    # Utilise cmd.exe pour eviter les problemes d'encodage/stdin de Windows PowerShell 5.1 avec wg.exe.
    $cmdLine = '"' + $WgExe + '" ' + $Command
    $output = & cmd.exe /C $cmdLine 2>&1
    $code = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($code -ne 0) {
        if ([string]::IsNullOrWhiteSpace($text)) { $text = "wg.exe $Command a retourne le code $code" }
        throw $text
    }
    return $text
}

function New-WgPrivateKey([string]$WgExe) {
    return Test-WgKey -Key (Invoke-WgSimple -WgExe $WgExe -Command 'genkey') -Label 'Cle privee'
}

function Get-WgPublicKey([string]$WgExe, [string]$PrivateKey) {
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tempFile, $PrivateKey.Trim() + "`n", [System.Text.Encoding]::ASCII)
        $cmdLine = '"' + $WgExe + '" pubkey < "' + $tempFile + '"'
        $output = & cmd.exe /C $cmdLine 2>&1
        $code = $LASTEXITCODE
        $text = ($output | Out-String).Trim()
        if ($code -ne 0) {
            if ([string]::IsNullOrWhiteSpace($text)) { $text = "wg.exe pubkey a retourne le code $code" }
            throw $text
        }
        return Test-WgKey -Key $text -Label 'Cle publique'
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function New-WgPresharedKey([string]$WgExe) {
    return Test-WgKey -Key (Invoke-WgSimple -WgExe $WgExe -Command 'genpsk') -Label 'Cle pre-partagee'
}


function Invoke-WireGuardNoThrow([string]$WireGuardExe, [string[]]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $WireGuardExe
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
$wgExe = Join-Path $env:ProgramFiles "WireGuard\wg.exe"
$wireguardExe = Join-Path $env:ProgramFiles "WireGuard\wireguard.exe"
if (-not (Test-Path $wgExe)) { throw "wg.exe introuvable. Installe WireGuard ou lance Install-WireGuardServer.ps1 d'abord." }

$baseDir = Join-Path $env:ProgramData "WireGuardPhoneServer"
$serverConfigPath = Join-Path $baseDir "server\$TunnelName.conf"
$clientDir = Join-Path $baseDir "clients"
$clientConfigPath = Join-Path $clientDir "$ClientName.conf"

if (-not (Test-Path $serverConfigPath)) { throw "Configuration serveur introuvable : $serverConfigPath" }
if (Test-Path $clientConfigPath) { throw "Un client nommé '$ClientName' existe déjà : $clientConfigPath" }

$serverConfig = Get-Content $serverConfigPath -Raw
$serverPrivateKey = ([regex]::Match($serverConfig, 'PrivateKey\s*=\s*(\S+)')).Groups[1].Value
if (-not $serverPrivateKey) { throw "Impossible de lire la clé privée serveur." }
$serverPublicKey = Get-WgPublicKey $wgExe $serverPrivateKey

$clientIp = "10.66.66.$ClientNumber"
if ($serverConfig -match [regex]::Escape("AllowedIPs = $clientIp/32")) {
    throw "L'adresse $clientIp est déjà utilisée. Choisis un autre -ClientNumber."
}

$clientPrivateKey = New-WgPrivateKey $wgExe
$clientPublicKey = Get-WgPublicKey $wgExe $clientPrivateKey
$psk = New-WgPresharedKey $wgExe

$peerBlock = @"

# $ClientName
[Peer]
PublicKey = $clientPublicKey
PresharedKey = $psk
AllowedIPs = $clientIp/32
"@
Add-Content -Path $serverConfigPath -Value $peerBlock -Encoding ASCII

$clientConfig = @"
[Interface]
PrivateKey = $clientPrivateKey
Address = $clientIp/32
DNS = $Dns

[Peer]
PublicKey = $serverPublicKey
PresharedKey = $psk
Endpoint = $Endpoint`:$ListenPort
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
"@
Set-Content -Path $clientConfigPath -Value $clientConfig -Encoding ASCII

$reloadOk = Restart-WireGuardTunnelSafely -WireGuardExe $wireguardExe -TunnelName $TunnelName -ConfigPath $serverConfigPath
if (-not $reloadOk) {
    Write-Warning "L'operation sur le peer est faite, mais le service doit etre redemarre manuellement."
}

Write-Host "✅ Client ajouté : $ClientName" -ForegroundColor Green
Write-Host "IP VPN      : $clientIp"
Write-Host "Client conf : $clientConfigPath"
