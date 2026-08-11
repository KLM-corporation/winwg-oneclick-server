<#
.SYNOPSIS
  Console de supervision locale pour WinWG OneClick Server.

.DESCRIPTION
  WireGuard sur Windows tourne comme un service en arriere-plan, donc il n'y a pas
  naturellement de "console serveur" visible. Ce script fournit une console de statut :
  service, tunnel, port UDP, NAT, firewall, configurations telephone et handshakes.
#>
[CmdletBinding()]
param(
    [string]$TunnelName = "wg-phone-server",
    [int]$ListenPort = 51820,
    [string]$BaseDir = "$env:ProgramData\WireGuardPhoneServer",
    [int]$RefreshSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Cette console doit etre lancee en administrateur. Utilise SERVER-CONSOLE.bat."
    }
}

function Get-ServiceState([string]$TunnelName) {
    $serviceName = "WireGuardTunnel`$$TunnelName"
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        $svc = Get-Service -Name "WireGuardTunnel*$TunnelName*" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    return $svc
}

function Get-WgShow([string]$TunnelName) {
    $wgExe = Join-Path $env:ProgramFiles "WireGuard\wg.exe"
    if (-not (Test-Path $wgExe)) { return "wg.exe introuvable" }
    $output = & $wgExe show $TunnelName 2>&1
    if ($LASTEXITCODE -ne 0) { return ($output | Out-String).Trim() }
    return ($output | Out-String).Trim()
}


function Get-PeerNameMap([string]$ServerConfigPath) {
    $map = @{}
    if (-not (Test-Path $ServerConfigPath)) { return $map }

    $currentName = $null
    foreach ($line in Get-Content $ServerConfigPath) {
        $trim = $line.Trim()
        if ($trim -match '^#\s*(.+)$') {
            $currentName = $Matches[1].Trim()
            continue
        }
        if ($trim -match '^PublicKey\s*=\s*(\S+)') {
            if ($currentName) {
                $map[$Matches[1]] = $currentName
                $currentName = $null
            }
        }
    }
    return $map
}

function Get-WgPeerSummaries([string]$WgShowText, [hashtable]$PeerNameMap) {
    $peers = @()
    $current = $null

    foreach ($rawLine in ($WgShowText -split "`r?`n")) {
        $line = $rawLine.Trim()
        if ($line -match '^peer:\s*(\S+)') {
            if ($current) { $peers += [pscustomobject]$current }
            $pub = $Matches[1]
            $name = if ($PeerNameMap.ContainsKey($pub)) { $PeerNameMap[$pub] } else { "telephone inconnu" }
            $current = [ordered]@{
                Name = $name
                PublicKey = $pub
                Endpoint = "-"
                AllowedIPs = "-"
                LatestHandshake = "jamais"
                Transfer = "-"
                Status = "hors ligne"
            }
            continue
        }
        if (-not $current) { continue }
        if ($line -match '^endpoint:\s*(.+)$') { $current.Endpoint = $Matches[1].Trim(); continue }
        if ($line -match '^allowed ips:\s*(.+)$') { $current.AllowedIPs = $Matches[1].Trim(); continue }
        if ($line -match '^latest handshake:\s*(.+)$') {
            $current.LatestHandshake = $Matches[1].Trim()
            $current.Status = "connecte"
            continue
        }
        if ($line -match '^transfer:\s*(.+)$') { $current.Transfer = $Matches[1].Trim(); continue }
    }
    if ($current) { $peers += [pscustomobject]$current }
    return @($peers)
}

function Write-PeerDashboard([string]$WgShowText, [string]$ServerConfigPath) {
    $nameMap = Get-PeerNameMap -ServerConfigPath $ServerConfigPath
    $peers = @(Get-WgPeerSummaries -WgShowText $WgShowText -PeerNameMap $nameMap)

    Write-Host "Telephones / peers" -ForegroundColor Cyan
    Write-Host "------------------" -ForegroundColor DarkGray
    if ($peers.Length -eq 0) {
        Write-Host "Aucun telephone/peer detecte dans wg show." -ForegroundColor Yellow
        return
    }

    foreach ($peer in $peers) {
        $color = if ($peer.Status -eq "connecte") { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }
        Write-Host ("- " + $peer.Name + " : " + $peer.Status) -ForegroundColor $color
        Write-Host ("  IP VPN       : " + $peer.AllowedIPs) -ForegroundColor DarkCyan
        Write-Host ("  Endpoint     : " + $peer.Endpoint) -ForegroundColor DarkCyan
        Write-Host ("  Handshake    : " + $peer.LatestHandshake) -ForegroundColor DarkCyan
        Write-Host ("  Transfert    : " + $peer.Transfer) -ForegroundColor DarkCyan
        Write-Host ("  Public key   : " + $peer.PublicKey.Substring(0, 12) + "...") -ForegroundColor DarkGray
    }
}

function Get-PrimaryIPv4 {
    try {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
            Sort-Object RouteMetric, InterfaceMetric |
            Select-Object -First 1
        if ($route) {
            $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction Stop |
                Where-Object { $_.IPAddress -notlike '169.254.*' } |
                Select-Object -First 1
            if ($ip) { return $ip.IPAddress }
        }
    } catch {}
    return "inconnue"
}

function Write-Line([string]$Name, [string]$Value, [ConsoleColor]$Color = [ConsoleColor]::White) {
    Write-Host ($Name.PadRight(28) + ": ") -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Show-Status {
    Clear-Host
    Write-Host "WinWG OneClick Server - Console serveur" -ForegroundColor Green
    Write-Host "Actualisation toutes les $RefreshSeconds secondes. Appuie sur Q pour quitter." -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host ""

    $svc = Get-ServiceState -TunnelName $TunnelName
    if ($svc) {
        $color = if ($svc.Status -eq 'Running') { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }
        Write-Line "Service" "$($svc.Name) - $($svc.Status)" $color
    } else {
        Write-Line "Service" "introuvable" Red
    }

    $serverConfig = Join-Path $BaseDir "server\$TunnelName.conf"
    $clientDir = Join-Path $BaseDir "clients"
    Write-Line "Tunnel" $TunnelName Cyan
    Write-Line "Port UDP" "$ListenPort" Cyan
    Write-Line "IP locale PC" (Get-PrimaryIPv4) Cyan
    Write-Line "Config serveur" $serverConfig Cyan

    $fw = @(Get-NetFirewallRule -DisplayName "WireGuard Server UDP $ListenPort" -ErrorAction SilentlyContinue)
    if ($fw.Length -gt 0) { Write-Line "Pare-feu" "regle presente" Green } else { Write-Line "Pare-feu" "regle manquante" Red }

    $nat = Get-NetNat -Name "WireGuardPhoneServerNAT" -ErrorAction SilentlyContinue
    if ($nat) { Write-Line "NAT Windows" "$($nat.InternalIPInterfaceAddressPrefix)" Green } else { Write-Line "NAT Windows" "manquant" Yellow }

    $udp = @(Get-NetUDPEndpoint -LocalPort $ListenPort -ErrorAction SilentlyContinue)
    if ($udp.Length -gt 0) { Write-Line "Endpoint UDP local" "present" Green } else { Write-Line "Endpoint UDP local" "non visible / normal selon driver" Yellow }

    if (Test-Path $clientDir) {
        $clients = @(Get-ChildItem $clientDir -Filter "*.conf" -ErrorAction SilentlyContinue)
        Write-Line "Configs telephone" "$($clients.Length) fichier(s)" Cyan
        foreach ($c in $clients) { Write-Host "  - $($c.FullName)" -ForegroundColor DarkCyan }
    } else {
        Write-Line "Configs telephone" "dossier introuvable" Yellow
    }

    Write-Host ""
    $show = Get-WgShow -TunnelName $TunnelName
    if ([string]::IsNullOrWhiteSpace($show)) {
        Write-Host "Aucune sortie wg show." -ForegroundColor Yellow
    } else {
        Write-PeerDashboard -WgShowText $show -ServerConfigPath $serverConfig
        Write-Host ""
        Write-Host "Details WireGuard bruts" -ForegroundColor Cyan
        Write-Host "-----------------------" -ForegroundColor DarkGray
        Write-Host $show
    }

    Write-Host ""
    Write-Host "Aide rapide" -ForegroundColor Cyan
    Write-Host "- Si le telephone est connecte, il apparait dans 'Telephones / peers' avec un handshake recent."
    Write-Host "- Si aucun handshake hors Wi-Fi: verifier redirection UDP $ListenPort sur la box et CG-NAT."
    Write-Host "- Cette console n'est qu'un moniteur: le serveur continue comme service meme si tu la fermes."
}

try {
    Assert-Admin
    $host.UI.RawUI.WindowTitle = "WinWG OneClick Server - Console serveur"
    while ($true) {
        Show-Status
        $deadline = (Get-Date).AddSeconds($RefreshSeconds)
        while ((Get-Date) -lt $deadline) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq 'Q') { return }
            }
            Start-Sleep -Milliseconds 200
        }
    }
} catch {
    Write-Host "ERREUR : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Appuie sur une touche pour fermer..."
    [void][Console]::ReadKey($true)
    exit 1
}
