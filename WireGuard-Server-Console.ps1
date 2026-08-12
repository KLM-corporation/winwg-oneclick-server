<#
.SYNOPSIS
  Console serveur unifiee pour WinWG OneClick Server.

.DESCRIPTION
  WireGuard sur Windows tourne comme un service en arriere-plan. Cette console
  regroupe maintenant la supervision ET le controle du service avec un menu
  interactif stable, sans rafraichissement automatique.
#>
[CmdletBinding()]
param(
    [string]$TunnelName = "wg-phone-server",
    [int]$ListenPort = 51820,
    [string]$BaseDir = "$env:ProgramData\WireGuardPhoneServer"
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


function Get-DefaultEndpoint([int]$ListenPort, [string]$BaseDir) {
    $clientDir = Join-Path $BaseDir "clients"
    if (Test-Path $clientDir) {
        $firstClient = Get-ChildItem $clientDir -Filter "*.conf" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($firstClient) {
            $content = Get-Content $firstClient.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match '(?m)^Endpoint\s*=\s*([^:\s]+):\d+') { return $Matches[1] }
        }
    }

    $services = @("https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com")
    foreach ($svc in $services) {
        try {
            $ip = (Invoke-RestMethod -Uri $svc -TimeoutSec 5).ToString().Trim()
            if ($ip -match '^[0-9]{1,3}(\.[0-9]{1,3}){3}$') { return $ip }
        } catch {}
    }
    return "TON_IP_PUBLIQUE_OU_DNS"
}

function Get-NextClientNumber([string]$TunnelName, [string]$BaseDir) {
    $serverConfig = Get-ServerConfigPath -TunnelName $TunnelName -BaseDir $BaseDir
    $used = @()
    if (Test-Path $serverConfig) {
        foreach ($line in Get-Content $serverConfig) {
            if ($line -match 'AllowedIPs\s*=\s*10\.66\.66\.(\d+)/32') {
                $used += [int]$Matches[1]
            }
        }
    }
    for ($i = 2; $i -lt 255; $i++) {
        if ($used -notcontains $i) { return $i }
    }
    throw "Aucune adresse VPN disponible dans 10.66.66.0/24."
}

function Add-DeviceFromConsole([string]$TunnelName, [int]$ListenPort, [string]$BaseDir) {
    Assert-ProjectInstalled -TunnelName $TunnelName -BaseDir $BaseDir
    $scriptPath = Join-Path $PSScriptRoot "scripts\Add-WireGuardPeer.ps1"
    if (-not (Test-Path $scriptPath)) { throw "Script d'ajout introuvable : $scriptPath" }

    Write-Host ""
    Write-Host "Ajouter un appareil" -ForegroundColor Cyan
    Write-Host "-------------------" -ForegroundColor DarkGray
    $clientName = (Read-Host "Nom de l'appareil, ex: iphone, android, laptop").Trim()
    if ([string]::IsNullOrWhiteSpace($clientName)) { throw "Nom d'appareil vide." }

    $defaultEndpoint = Get-DefaultEndpoint -ListenPort $ListenPort -BaseDir $BaseDir
    $endpointInput = (Read-Host "Endpoint public ou DNS [$defaultEndpoint]").Trim()
    $endpoint = if ([string]::IsNullOrWhiteSpace($endpointInput)) { $defaultEndpoint } else { $endpointInput }

    $clientNumber = Get-NextClientNumber -TunnelName $TunnelName -BaseDir $BaseDir
    Write-Host "IP VPN attribuee automatiquement : 10.66.66.$clientNumber" -ForegroundColor DarkCyan

    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ClientName $clientName -Endpoint $endpoint -ClientNumber $clientNumber -ListenPort $ListenPort -TunnelName $TunnelName 2>&1
    $code = $LASTEXITCODE
    if ($output) { $output | Out-Host }
    if ($code -ne 0) { throw "Echec de l'ajout de l'appareil '$clientName'." }

    $clientDir = Join-Path $BaseDir "clients"
    if (Test-Path $clientDir) { Start-Process explorer.exe $clientDir }
    return "Appareil ajoute : $clientName. Fichier .conf genere dans $clientDir"
}

function Remove-DeviceFromConsole([string]$TunnelName, [string]$BaseDir) {
    Assert-ProjectInstalled -TunnelName $TunnelName -BaseDir $BaseDir
    $scriptPath = Join-Path $PSScriptRoot "scripts\Remove-WireGuardPeer.ps1"
    if (-not (Test-Path $scriptPath)) { throw "Script de suppression introuvable : $scriptPath" }

    $clientDir = Join-Path $BaseDir "clients"
    $clients = @()
    if (Test-Path $clientDir) { $clients = @(Get-ChildItem $clientDir -Filter "*.conf" -ErrorAction SilentlyContinue) }

    Write-Host ""
    Write-Host "Supprimer un appareil" -ForegroundColor Cyan
    Write-Host "---------------------" -ForegroundColor DarkGray
    if ($clients.Length -eq 1) {
        $clientName = $clients[0].BaseName
        Write-Host "1 - $clientName" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "Un seul appareil est configure. Selection automatique : $clientName" -ForegroundColor Yellow
    } elseif ($clients.Length -gt 1) {
        Write-Host "0 - Annuler"
        for ($i = 0; $i -lt $clients.Length; $i++) {
            Write-Host ("{0} - {1}" -f ($i + 1), $clients[$i].BaseName)
        }
        Write-Host ""
        $choice = (Read-Host "Tape le numero de l'appareil a supprimer, ou son nom exact").Trim()
        if ($choice -eq '0') { return "Suppression annulee." }
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $clients.Length) {
            $clientName = $clients[[int]$choice - 1].BaseName
        } else {
            $clientName = $choice
        }
    } else {
        Write-Host "Aucun fichier .conf trouve dans $clientDir" -ForegroundColor Yellow
        $clientName = (Read-Host "Nom exact de l'appareil a supprimer, ou laisse vide pour annuler").Trim()
        if ([string]::IsNullOrWhiteSpace($clientName)) { return "Suppression annulee." }
    }

    if ([string]::IsNullOrWhiteSpace($clientName)) { return "Suppression annulee." }
    $confirm = (Read-Host "Confirmer la suppression de '$clientName' ? Tape O pour confirmer [o/N]").Trim().ToLowerInvariant()
    if ($confirm -notin @('o','oui','y','yes')) { return "Suppression annulee." }

    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ClientName $clientName -TunnelName $TunnelName 2>&1
    $code = $LASTEXITCODE
    if ($output) { $output | Out-Host }
    if ($code -ne 0) { throw "Echec de la suppression de l'appareil '$clientName'." }
    return "Appareil supprime : $clientName"
}

function Show-Status([string]$LastMessage = "") {
    Clear-Host
    Write-Host "WinWG OneClick Server - Console serveur unifiee" -ForegroundColor Green
    Write-Host "Surveillance + controle du service VPN dans une seule console." -ForegroundColor DarkGray
    Write-Host "Menu interactif: pas de rafraichissement automatique." -ForegroundColor Cyan
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
    Write-Host "- Si le telephone est connecte, il apparait dans 'Telephones / peers' avec un handshake recent."
}

function Show-MainMenu {
    Write-Host ""
    Write-Host "Actions" -ForegroundColor Cyan
    Write-Host "-------" -ForegroundColor DarkGray
    Write-Host "1 / A - Activer / demarrer le serveur VPN"
    Write-Host "2 / D - Desactiver / arreter le serveur VPN"
    Write-Host "3     - Redemarrer le serveur VPN"
    Write-Host "4 / N - Ajouter un nouvel appareil"
    Write-Host "5 / R - Retirer / supprimer un appareil"
    Write-Host "S     - Rafraichir le statut"
    Write-Host "Q     - Quitter"
    Write-Host ""
}


function Pause-ConsoleAction([string]$Message) {
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Write-Host ""
        Write-Host $Message -ForegroundColor Yellow
    }
    Write-Host ""
    [void](Read-Host "Appuie sur Entree pour revenir au menu")
}

try {
    Assert-Admin
    $host.UI.RawUI.WindowTitle = "WinWG OneClick Server - Console serveur unifiee"
    $lastMessage = ""
    while ($true) {
        Show-Status -LastMessage $lastMessage
        $lastMessage = ""
        Show-MainMenu
        $choice = (Read-Host "Choix").Trim().ToLowerInvariant()
        switch ($choice) {
            { $_ -in @('1','a') } {
                try { $lastMessage = Enable-Tunnel -TunnelName $TunnelName -BaseDir $BaseDir } catch { $lastMessage = "ERREUR activation : $($_.Exception.Message)" }
                Pause-ConsoleAction $lastMessage
                $lastMessage = ""
            }
            { $_ -in @('2','d') } {
                try { $lastMessage = Disable-Tunnel -TunnelName $TunnelName } catch { $lastMessage = "ERREUR desactivation : $($_.Exception.Message)" }
                Pause-ConsoleAction $lastMessage
                $lastMessage = ""
            }
            { $_ -in @('3') } {
                try { $lastMessage = Restart-Tunnel -TunnelName $TunnelName -BaseDir $BaseDir } catch { $lastMessage = "ERREUR redemarrage : $($_.Exception.Message)" }
                Pause-ConsoleAction $lastMessage
                $lastMessage = ""
            }
            { $_ -in @('4','n') } {
                try { $lastMessage = Add-DeviceFromConsole -TunnelName $TunnelName -ListenPort $ListenPort -BaseDir $BaseDir } catch { $lastMessage = "ERREUR ajout appareil : $($_.Exception.Message)" }
                Pause-ConsoleAction $lastMessage
                $lastMessage = ""
            }
            { $_ -in @('5','r','x') } {
                try { $lastMessage = Remove-DeviceFromConsole -TunnelName $TunnelName -BaseDir $BaseDir } catch { $lastMessage = "ERREUR suppression appareil : $($_.Exception.Message)" }
                Pause-ConsoleAction $lastMessage
                $lastMessage = ""
            }
            's' { $lastMessage = "Statut rafraichi." }
            'q' { return }
            default { $lastMessage = "Choix invalide. Utilise 1/2/3/4/5, A/D/N/R, S ou Q." }
        }
    }
} catch {
    Write-Host "ERREUR : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Appuie sur une touche pour fermer..."
    [void][Console]::ReadKey($true)
    exit 1
}
