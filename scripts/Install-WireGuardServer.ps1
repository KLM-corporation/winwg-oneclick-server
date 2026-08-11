<#
.SYNOPSIS
  Configure un PC Windows en serveur WireGuard pour téléphone hors LAN.

.EXAMPLE
  .\Install-WireGuardServer.ps1 -Endpoint "vpn-maison.duckdns.org" -ClientName "iphone"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Endpoint,

    [string]$ClientName = "phone",
    [int]$ListenPort = 51820,
    [string]$VpnCidr = "10.66.66.0/24",
    [string]$ServerVpnIp = "10.66.66.1",
    [string]$FirstClientVpnIp = "10.66.66.2",
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

function Ensure-WireGuard {
    $wgExe = Join-Path $env:ProgramFiles "WireGuard\wg.exe"
    $wireguardExe = Join-Path $env:ProgramFiles "WireGuard\wireguard.exe"
    if ((Test-Path $wgExe) -and (Test-Path $wireguardExe)) {
        return [pscustomobject]@{ WgExe = $wgExe; WireGuardExe = $wireguardExe }
    }

    Write-Host "WireGuard non trouvé. Tentative d'installation via winget..."
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget introuvable. Installe WireGuard manuellement depuis https://www.wireguard.com/install/ puis relance le script."
    }

    & winget install --id WireGuard.WireGuard -e --accept-source-agreements --accept-package-agreements | Out-Host

    if (-not ((Test-Path $wgExe) -and (Test-Path $wireguardExe))) {
        throw "WireGuard n'a pas été trouvé après installation. Relance PowerShell ou installe-le manuellement."
    }
    return [pscustomobject]@{ WgExe = $wgExe; WireGuardExe = $wireguardExe }
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

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
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
$tools = @(Ensure-WireGuard)[-1]
if (-not $tools -or -not $tools.PSObject.Properties["WgExe"] -or -not $tools.PSObject.Properties["WireGuardExe"]) { throw "Impossible de recuperer les chemins WireGuard apres installation." }
$wgExe = $tools.WgExe
$wireguardExe = $tools.WireGuardExe

$baseDir = Join-Path $env:ProgramData "WireGuardPhoneServer"
$serverDir = Join-Path $baseDir "server"
$clientDir = Join-Path $baseDir "clients"
Ensure-Directory $serverDir
Ensure-Directory $clientDir

$serverPrivateKey = New-WgPrivateKey $wgExe
$serverPublicKey = Get-WgPublicKey $wgExe $serverPrivateKey
$clientPrivateKey = New-WgPrivateKey $wgExe
$clientPublicKey = Get-WgPublicKey $wgExe $clientPrivateKey
$psk = New-WgPresharedKey $wgExe

$serverConfigPath = Join-Path $serverDir "$TunnelName.conf"
$clientConfigPath = Join-Path $clientDir "$ClientName.conf"

$serverConfig = @"
[Interface]
PrivateKey = $serverPrivateKey
Address = $ServerVpnIp/24
ListenPort = $ListenPort

# $ClientName
[Peer]
PublicKey = $clientPublicKey
PresharedKey = $psk
AllowedIPs = $FirstClientVpnIp/32
"@

$clientConfig = @"
[Interface]
PrivateKey = $clientPrivateKey
Address = $FirstClientVpnIp/32
DNS = $Dns

[Peer]
PublicKey = $serverPublicKey
PresharedKey = $psk
Endpoint = $Endpoint`:$ListenPort
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
"@

Set-Content -Path $serverConfigPath -Value $serverConfig -Encoding ASCII
Set-Content -Path $clientConfigPath -Value $clientConfig -Encoding ASCII

Write-Host "Activation du routage IPv4 Windows..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name IPEnableRouter -Value 1

Write-Host "Configuration du forwarding sur les interfaces réseau..."
Get-NetIPInterface -AddressFamily IPv4 | ForEach-Object {
    try { Set-NetIPInterface -InterfaceIndex $_.InterfaceIndex -Forwarding Enabled -ErrorAction Stop } catch {}
}

Write-Host "Création/actualisation du pare-feu UDP $ListenPort..."
$fwName = "WireGuard Server UDP $ListenPort"
Get-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName $fwName -Direction Inbound -Action Allow -Protocol UDP -LocalPort $ListenPort | Out-Null

Write-Host "Création/actualisation du NAT Windows pour $VpnCidr..."
$natName = "WireGuardPhoneServerNAT"
Get-NetNat -Name $natName -ErrorAction SilentlyContinue | Remove-NetNat -Confirm:$false
New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix $VpnCidr | Out-Null

Write-Host "Installation du service tunnel WireGuard..."
$remove = Invoke-WireGuardNoThrow -WireGuardExe $wireguardExe -Arguments @('/uninstalltunnelservice', $TunnelName)
if ($remove.ExitCode -ne 0 -and $remove.StdErr -notmatch 'does not exist|n.existe pas|service.*introuvable') { Write-Host "Ancien tunnel non supprimé : $($remove.StdErr.Trim())" -ForegroundColor Yellow }
$install = Invoke-WireGuardNoThrow -WireGuardExe $wireguardExe -Arguments @('/installtunnelservice', $serverConfigPath)
if ($install.ExitCode -ne 0) { throw (($install.StdErr + $install.StdOut).Trim()) }

Write-Host ""
Write-Host "✅ Serveur WireGuard configuré." -ForegroundColor Green
Write-Host "Tunnel      : $TunnelName"
Write-Host "Port UDP    : $ListenPort"
Write-Host "VPN serveur : $ServerVpnIp"
Write-Host "Config telephone : $clientConfigPath"
Write-Host ""
Write-Host "À faire sur ta box : redirige UDP $ListenPort vers l'IP locale de ce PC."
Write-Host "Puis importe le fichier client dans l'app WireGuard du téléphone."
