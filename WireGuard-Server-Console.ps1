<#
.SYNOPSIS
  Console serveur unifiee pour WinWG OneClick Server.

.DESCRIPTION
  WireGuard sur Windows tourne comme un service en arriere-plan. Cette console
  regroupe maintenant la supervision ET le controle du service : statut,
  handshakes, demarrage, arret et redemarrage du serveur VPN.
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
    $wireguardExe = Join-Path $env:ProgramFiles "WireGuard\wireguard.exe"
    if (-not (Test-Path $wireguardExe)) { return $null }
    return $wireguardExe
}

function Get-WgExe {
    $wgExe = Join-Path $env:ProgramFiles "WireGuard\wg.exe"
    if (-not (Test-Path $wgExe)) { return $null }
    return $wgExe
}

function Get-ServerConfigPath([string]$TunnelName, [string]$BaseDir) {
    return Join-Path $BaseDir "server\$TunnelName.conf"
}

function Test-ProjectInstalled([string]$TunnelName, [string]$BaseDir) {
    return (Test-Path (Get-ServerConfigPath -TunnelName $TunnelName -BaseDir $BaseDir))
}

function Assert-ProjectInstalled([string]$TunnelName, [string]$BaseDir) {
    $configPath = Get-ServerConfigPath -TunnelName $TunnelName -BaseDir $BaseDir
    if (-not (Test-Path $configPath)) {
        throw "WinWG OneClick Server semble desinstalle : configuration serveur introuvable ($configPath). Relance INSTALLER-ONE-CLICK.bat avant d'activer le service."
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

function Enable-Tunnel([string]$TunnelName, [string]$BaseDir) {
    Assert-ProjectInstalled -TunnelName $TunnelName -BaseDir $BaseDir
    $wireguardExe = Get-WireGuardExe
    if (-not $wireguardExe) { throw "wireguard.exe introuvable. Installe WireGuard ou relance INSTALLER-ONE-CLICK.bat." }

    $configPath = Get-ServerConfigPath -TunnelName $TunnelName -BaseDir $BaseDir
    $svc = Get-ServiceState -TunnelName $TunnelName
    if ($svc) {
        if ($svc.Status -ne 'Running') {
            Start-Service -Name $svc.Name -ErrorAction Stop
            Start-Sleep -Seconds 1
            return "Service demarre : $($svc.Name)"
        }
        return "Service deja actif : $($svc.Name)"
    }

    $result = Invoke-ExternalNoThrow -FileName $wireguardExe -Arguments @('/installtunnelservice', $configPath)
    $msg = ($result.StdErr + $result.StdOut).Trim()
    if ($result.ExitCode -ne 0) {
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "wireguard.exe a retourne le code $($result.ExitCode)" }
        throw $msg
    }
    return "Service installe et demarre : WireGuardTunnel`$$TunnelName"
}

function Disable-Tunnel([string]$TunnelName) {
    $svc = Get-ServiceState -TunnelName $TunnelName
    if (-not $svc) { return "Service deja desactive / non installe" }

    $wireguardExe = Get-WireGuardExe
    if ($wireguardExe) {
        $result = Invoke-ExternalNoThrow -FileName $wireguardExe -Arguments @('/uninstalltunnelservice', $TunnelName)
        $msg = ($result.StdErr + $result.StdOut).Trim()
        if ($result.ExitCode -ne 0 -and $msg -notmatch 'does not exist|n.existe pas|service.*introuvable|specified service') {
            throw $msg
        }
        return "Service desactive : WireGuardTunnel`$$TunnelName"
    }

    if ($svc.Status -ne 'Stopped') { Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue }
    sc.exe delete $svc.Name | Out-Null
    return "Service residuel supprime : $($svc.Name)"
}

function Restart-Tunnel([string]$TunnelName, [string]$BaseDir) {
    $stopMsg = Disable-Tunnel -TunnelName $TunnelName
    Start-Sleep -Seconds 1
    $startMsg = Enable-Tunnel -TunnelName $TunnelName -BaseDir $BaseDir
    return "$stopMsg`n$startMsg"
}

function Get-WgShow([string]$TunnelName) {
    $wgExe = Get-WgExe
    if (-not $wgExe) { return "wg.exe introuvable" }
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
        if ($trim -match '^#\s*(.+)$') { $currentName = $Matches[1].Trim(); continue }
        if ($trim -match '^PublicKey\s*=\s*(\S+)') {
            if ($currentName) { $map[$Matches[1]] = $currentName; $currentName = $null }
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
            $current = [ordered]@{ Name=$name; PublicKey=$pub; Endpoint="-"; AllowedIPs="-"; LatestHandshake="jamais"; Transfer="-"; Status="hors ligne" }
            continue
        }
        if (-not $current) { continue }
        if ($line -match '^endpoint:\s*(.+)$') { $current.Endpoint = $Matches[1].Trim(); continue }
        if ($line -match '^allowed ips:\s*(.+)$') { $current.AllowedIPs = $Matches[1].Trim(); continue }
        if ($line -match '^latest handshake:\s*(.+)$') { $current.LatestHandshake = $Matches[1].Trim(); $current.Status = "connecte"; continue }
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
    if ($peers.Length -eq 0) { Write-Host "Aucun telephone/peer detecte dans wg show." -ForegroundColor Yellow; return }
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
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop | Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
        if ($route) {
            $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction Stop | Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
            if ($ip) { return $ip.IPAddress }
        }
    } catch {}
    return "inconnue"
}

function Write-Line([string]$Name, [string]$Value, [ConsoleColor]$Color = [ConsoleColor]::White) {
    Write-Host ($Name.PadRight(28) + ": ") -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Show-Status([string]$LastMessage = "") {
    Clear-Host
    Write-Host "WinWG OneClick Server - Console serveur unifiee" -ForegroundColor Green
    Write-Host "Surveillance + controle du service VPN dans une seule console." -ForegroundColor DarkGray
    Write-Host "Touches: A=activer  D=desactiver  R=redemarrer  Q=quitter" -ForegroundColor Cyan
    Write-Host "Actualisation toutes les $RefreshSeconds secondes." -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor DarkGray
    if (-not [string]::IsNullOrWhiteSpace($LastMessage)) {
        Write-Host ""
        Write-Host $LastMessage -ForegroundColor Yellow
    }
    Write-Host ""

    $serverConfig = Get-ServerConfigPath -TunnelName $TunnelName -BaseDir $BaseDir
    $clientDir = Join-Path $BaseDir "clients"
    $installed = Test-ProjectInstalled -TunnelName $TunnelName -BaseDir $BaseDir
    $svc = Get-ServiceState -TunnelName $TunnelName

    if ($installed) { Write-Line "Installation" "presente" Green } else { Write-Line "Installation" "absente / desinstallee" Yellow }
    if ($svc) {
        $color = if ($svc.Status -eq 'Running') { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }
        Write-Line "Service" "$($svc.Name) - $($svc.Status)" $color
        if (-not $installed) { Write-Line "Attention" "service residuel sans configuration" Yellow }
    } else {
        Write-Line "Service" "introuvable / desactive" Yellow
    }

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
    if ($svc -and $svc.Status -eq 'Running' -and $installed) {
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
    } else {
        Write-Host "WireGuard n'est pas actif, aucun handshake a afficher." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Aide rapide" -ForegroundColor Cyan
    Write-Host "- A active/demarre le serveur si la configuration existe."
    Write-Host "- D desactive/arrete le serveur sans supprimer les configurations."
    Write-Host "- R redemarre le service tunnel."
    Write-Host "- Si le telephone est connecte, il apparait dans 'Telephones / peers' avec un handshake recent."
}

try {
    Assert-Admin
    $host.UI.RawUI.WindowTitle = "WinWG OneClick Server - Console serveur unifiee"
    $lastMessage = ""
    while ($true) {
        Show-Status -LastMessage $lastMessage
        $lastMessage = ""
        $deadline = (Get-Date).AddSeconds($RefreshSeconds)
        while ((Get-Date) -lt $deadline) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                switch ($key.Key) {
                    'Q' { return }
                    'A' { try { $lastMessage = Enable-Tunnel -TunnelName $TunnelName -BaseDir $BaseDir } catch { $lastMessage = "ERREUR activation : $($_.Exception.Message)" }; break }
                    'D' { try { $lastMessage = Disable-Tunnel -TunnelName $TunnelName } catch { $lastMessage = "ERREUR desactivation : $($_.Exception.Message)" }; break }
                    'R' { try { $lastMessage = Restart-Tunnel -TunnelName $TunnelName -BaseDir $BaseDir } catch { $lastMessage = "ERREUR redemarrage : $($_.Exception.Message)" }; break }
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($lastMessage)) { break }
            Start-Sleep -Milliseconds 200
        }
    }
} catch {
    Write-Host "ERREUR : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Appuie sur une touche pour fermer..."
    [void][Console]::ReadKey($true)
    exit 1
}
