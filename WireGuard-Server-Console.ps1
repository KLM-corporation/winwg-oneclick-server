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
    [string]$BaseDir = "$env:ProgramData\WireGuardPhoneServer",
    [switch]$UltraVerbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$script:UltraVerboseMode = [bool]$UltraVerbose
$script:LogFilePath = $null
$script:UiMargin = "  "
$script:PeerTrafficSamples = @{}


function Write-UiHost {
    param(
        [Parameter(Position=0)]
        [object]$Object = "",
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White,
        [switch]$NoNewline
    )

    $text = [string]$Object
    if ($NoNewline) {
        Microsoft.PowerShell.Utility\Write-Host ($script:UiMargin + $text) -ForegroundColor $ForegroundColor -NoNewline
    } else {
        Microsoft.PowerShell.Utility\Write-Host ($script:UiMargin + $text) -ForegroundColor $ForegroundColor
    }
}

function Read-UiHost([string]$Prompt) {
    return Read-Host ($script:UiMargin + $Prompt)
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Cette console doit etre lancee en administrateur. Utilise SERVER-CONSOLE.bat."
    }
}


function Initialize-ConsoleLog([string]$BaseDir) {
    $logDir = Join-Path $BaseDir "logs"
    try {
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $script:LogFilePath = Join-Path $logDir "server-console-$stamp.log"
        "WinWG OneClick Server console log - $(Get-Date -Format o)" | Out-File -FilePath $script:LogFilePath -Encoding UTF8
    } catch {
        $script:LogFilePath = $null
$script:UiMargin = "  "
$script:PeerTrafficSamples = @{}
    }
}

function Write-Log([string]$Message) {
    if ($script:LogFilePath) {
        try { "[$(Get-Date -Format o)] $Message" | Out-File -FilePath $script:LogFilePath -Append -Encoding UTF8 } catch {}
    }
}

function Write-Ultra([string]$Message) {
    Write-Log $Message
    if ($script:UltraVerboseMode) {
        Write-UiHost "[VERBOSE] $Message" -ForegroundColor DarkYellow
    }
}

function Format-CommandForLog([string]$FileName, [string[]]$Arguments) {
    return ($FileName + " " + (($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '))
}

function Invoke-ExternalNoThrow([string]$FileName, [string[]]$Arguments) {
    Write-Ultra ("Commande externe: " + (Format-CommandForLog -FileName $FileName -Arguments $Arguments))
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
    Write-Ultra "Code retour: $($process.ExitCode)"
    if (-not [string]::IsNullOrWhiteSpace($stdout)) { Write-Ultra "STDOUT: $($stdout.Trim())" }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Ultra "STDERR: $($stderr.Trim())" }
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


function Convert-WgSizeToBytes([string]$Value, [string]$Unit) {
    $number = [double]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    switch ($Unit) {
        'B'   { return [int64]$number }
        'KiB' { return [int64]($number * 1KB) }
        'MiB' { return [int64]($number * 1MB) }
        'GiB' { return [int64]($number * 1GB) }
        'TiB' { return [int64]($number * 1TB) }
        default { return [int64]$number }
    }
}

function Get-WgTransferBytes([string]$TransferText) {
    $rx = [int64]0
    $tx = [int64]0
    if ($TransferText -match '([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|MiB|GiB|TiB)\s+received,\s+([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|MiB|GiB|TiB)\s+sent') {
        $rx = Convert-WgSizeToBytes -Value $Matches[1] -Unit $Matches[2]
        $tx = Convert-WgSizeToBytes -Value $Matches[3] -Unit $Matches[4]
    }
    return [pscustomobject]@{ ReceivedBytes = $rx; SentBytes = $tx }
}

function Format-BytesPerSecond([double]$BytesPerSecond) {
    if ($BytesPerSecond -lt 0) { $BytesPerSecond = 0 }
    if ($BytesPerSecond -ge 1GB) { return ("{0:N2} GiB/s" -f ($BytesPerSecond / 1GB)) }
    if ($BytesPerSecond -ge 1MB) { return ("{0:N2} MiB/s" -f ($BytesPerSecond / 1MB)) }
    if ($BytesPerSecond -ge 1KB) { return ("{0:N2} KiB/s" -f ($BytesPerSecond / 1KB)) }
    return ("{0:N0} B/s" -f $BytesPerSecond)
}


function Get-BandwidthSettingsPath([string]$BaseDir) {
    return (Join-Path $BaseDir "settings\bandwidth.json")
}

function New-DefaultBandwidthSettings {
    return [pscustomobject]@{
        Mode = "monitoring"
        Global = [pscustomobject]@{ RxMbps = 0; TxMbps = 0 }
        Peers = [pscustomobject]@{}
    }
}

function Get-BandwidthSettings([string]$BaseDir) {
    $path = Get-BandwidthSettingsPath -BaseDir $BaseDir
    if (-not (Test-Path $path)) { return New-DefaultBandwidthSettings }
    try {
        $settings = Get-Content $path -Raw | ConvertFrom-Json
        if (-not $settings.Global) { $settings | Add-Member -NotePropertyName Global -NotePropertyValue ([pscustomobject]@{ RxMbps = 0; TxMbps = 0 }) }
        if (-not $settings.Peers) { $settings | Add-Member -NotePropertyName Peers -NotePropertyValue ([pscustomobject]@{}) }
        return $settings
    } catch {
        Write-Ultra "Impossible de lire les parametres bande passante: $($_.Exception.Message)"
        return New-DefaultBandwidthSettings
    }
}

function Save-BandwidthSettings([string]$BaseDir, [object]$Settings) {
    $settingsDir = Join-Path $BaseDir "settings"
    if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null }
    $path = Get-BandwidthSettingsPath -BaseDir $BaseDir
    $Settings | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
    return $path
}

function Read-MbpsValue([string]$Prompt, [double]$Default = 0) {
    $value = (Read-UiHost "$Prompt [$Default]").Trim().Replace(',', '.')
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    $parsed = 0.0
    if (-not [double]::TryParse($value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        throw "Valeur Mbps invalide : $value"
    }
    if ($parsed -lt 0) { throw "La valeur Mbps ne peut pas etre negative." }
    return $parsed
}

function Format-Mbps([double]$Mbps) {
    if ($Mbps -le 0) { return "illimite" }
    return ("{0:N2} Mbps" -f $Mbps)
}

function Convert-BpsToMbps([double]$BytesPerSecond) {
    return (($BytesPerSecond * 8) / 1000000)
}

function Get-PeerLimitSettings([object]$Settings, [string]$PeerName) {
    if (-not $Settings -or -not $Settings.Peers) { return $null }
    $prop = $Settings.Peers.PSObject.Properties[$PeerName]
    if ($prop) { return $prop.Value }
    return $null
}

function Set-PeerLimitSettings([object]$Settings, [string]$PeerName, [double]$RxMbps, [double]$TxMbps) {
    $limit = [pscustomobject]@{ RxMbps = $RxMbps; TxMbps = $TxMbps }
    $prop = $Settings.Peers.PSObject.Properties[$PeerName]
    if ($prop) {
        $Settings.Peers.$PeerName = $limit
    } else {
        $Settings.Peers | Add-Member -NotePropertyName $PeerName -NotePropertyValue $limit
    }
}

function Remove-PeerLimitSettings([object]$Settings, [string]$PeerName) {
    $prop = $Settings.Peers.PSObject.Properties[$PeerName]
    if ($prop) { $Settings.Peers.PSObject.Properties.Remove($PeerName) }
}

function Get-LimitStatusText([double]$CurrentMbps, [double]$LimitMbps) {
    if ($LimitMbps -le 0) { return @{ Text = "illimite"; Color = [ConsoleColor]::DarkGray } }
    $pct = if ($LimitMbps -gt 0) { ($CurrentMbps / $LimitMbps) * 100 } else { 0 }
    if ($pct -ge 100) { return @{ Text = ("{0:N1}% - DEPASSE" -f $pct); Color = [ConsoleColor]::Red } }
    if ($pct -ge 80) { return @{ Text = ("{0:N1}% - proche limite" -f $pct); Color = [ConsoleColor]::Yellow } }
    return @{ Text = ("{0:N1}%" -f $pct); Color = [ConsoleColor]::Green }
}

function Get-PeerSpeedInfo([object]$Peer, [datetime]$Now) {
    if (-not $script:PeerTrafficSamples.ContainsKey($Peer.PublicKey)) {
        return [pscustomobject]@{ Text = "calcul au prochain refresh"; RxBps = 0.0; TxBps = 0.0; HasSample = $false }
    }

    $previous = $script:PeerTrafficSamples[$Peer.PublicKey]
    $seconds = ($Now - $previous.Timestamp).TotalSeconds
    if ($seconds -le 0.5) { return [pscustomobject]@{ Text = "delai trop court"; RxBps = 0.0; TxBps = 0.0; HasSample = $false } }

    $rxDelta = [double]($Peer.ReceivedBytes - $previous.ReceivedBytes)
    $txDelta = [double]($Peer.SentBytes - $previous.SentBytes)
    if ($rxDelta -lt 0) { $rxDelta = 0 }
    if ($txDelta -lt 0) { $txDelta = 0 }

    $rxBps = $rxDelta / $seconds
    $txBps = $txDelta / $seconds
    $rxRate = Format-BytesPerSecond $rxBps
    $txRate = Format-BytesPerSecond $txBps
    return [pscustomobject]@{ Text = "RX $rxRate / TX $txRate"; RxBps = $rxBps; TxBps = $txBps; HasSample = $true }
}

function Get-PeerSpeedText([object]$Peer, [datetime]$Now) {
    return (Get-PeerSpeedInfo -Peer $Peer -Now $Now).Text
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
            $current = [ordered]@{ Name=$name; PublicKey=$pub; Endpoint="-"; AllowedIPs="-"; LatestHandshake="jamais"; Transfer="-"; ReceivedBytes=[int64]0; SentBytes=[int64]0; Status="hors ligne" }
            continue
        }
        if (-not $current) { continue }
        if ($line -match '^endpoint:\s*(.+)$') { $current.Endpoint = $Matches[1].Trim(); continue }
        if ($line -match '^allowed ips:\s*(.+)$') { $current.AllowedIPs = $Matches[1].Trim(); continue }
        if ($line -match '^latest handshake:\s*(.+)$') { $current.LatestHandshake = $Matches[1].Trim(); $current.Status = "connecte"; continue }
        if ($line -match '^transfer:\s*(.+)$') {
            $current.Transfer = $Matches[1].Trim()
            $bytes = Get-WgTransferBytes -TransferText $current.Transfer
            $current.ReceivedBytes = $bytes.ReceivedBytes
            $current.SentBytes = $bytes.SentBytes
            continue
        }
    }
    if ($current) { $peers += [pscustomobject]$current }
    return @($peers)
}

function Write-PeerDashboard([string]$WgShowText, [string]$ServerConfigPath, [string]$BaseDir) {
    $nameMap = Get-PeerNameMap -ServerConfigPath $ServerConfigPath
    $peers = @(Get-WgPeerSummaries -WgShowText $WgShowText -PeerNameMap $nameMap)
    $bandwidthSettings = Get-BandwidthSettings -BaseDir $BaseDir
    Write-UiHost "Telephones / peers" -ForegroundColor Cyan
    Write-UiHost "------------------" -ForegroundColor DarkGray
    if ($peers.Length -eq 0) { Write-UiHost "Aucun telephone/peer detecte dans wg show." -ForegroundColor Yellow; return }
    $now = Get-Date
    $globalRxBps = 0.0
    $globalTxBps = 0.0
    $hasAnySpeedSample = $false

    foreach ($peer in $peers) {
        $color = if ($peer.Status -eq "connecte") { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }
        $speedInfo = Get-PeerSpeedInfo -Peer $peer -Now $now
        if ($speedInfo.HasSample) {
            $hasAnySpeedSample = $true
            $globalRxBps += $speedInfo.RxBps
            $globalTxBps += $speedInfo.TxBps
        }

        $peerLimit = Get-PeerLimitSettings -Settings $bandwidthSettings -PeerName $peer.Name
        Write-UiHost ("- " + $peer.Name + " : " + $peer.Status) -ForegroundColor $color
        Write-UiHost ("  IP VPN       : " + $peer.AllowedIPs) -ForegroundColor DarkCyan
        Write-UiHost ("  Endpoint     : " + $peer.Endpoint) -ForegroundColor DarkCyan
        Write-UiHost ("  Handshake    : " + $peer.LatestHandshake) -ForegroundColor DarkCyan
        Write-UiHost ("  Transfert    : " + $peer.Transfer) -ForegroundColor DarkCyan
        Write-UiHost ("  Vitesse      : " + $speedInfo.Text) -ForegroundColor Green
        if ($peerLimit) {
            $rxMbps = Convert-BpsToMbps $speedInfo.RxBps
            $txMbps = Convert-BpsToMbps $speedInfo.TxBps
            $rxStatus = Get-LimitStatusText -CurrentMbps $rxMbps -LimitMbps ([double]$peerLimit.RxMbps)
            $txStatus = Get-LimitStatusText -CurrentMbps $txMbps -LimitMbps ([double]$peerLimit.TxMbps)
            Write-UiHost ("  Limite peer  : RX " + (Format-Mbps ([double]$peerLimit.RxMbps)) + " (" + $rxStatus.Text + ") / TX " + (Format-Mbps ([double]$peerLimit.TxMbps)) + " (" + $txStatus.Text + ")") -ForegroundColor $rxStatus.Color
        }
        Write-UiHost ("  Public key   : " + $peer.PublicKey.Substring(0, 12) + "...") -ForegroundColor DarkGray

        $script:PeerTrafficSamples[$peer.PublicKey] = [pscustomobject]@{
            Timestamp = $now
            ReceivedBytes = $peer.ReceivedBytes
            SentBytes = $peer.SentBytes
        }
    }

    Write-UiHost ""
    if ($hasAnySpeedSample) {
        $globalRxText = Format-BytesPerSecond $globalRxBps
        $globalTxText = Format-BytesPerSecond $globalTxBps
        Write-UiHost ("Vitesse globale : RX $globalRxText / TX $globalTxText") -ForegroundColor Green

        $globalRxMbps = Convert-BpsToMbps $globalRxBps
        $globalTxMbps = Convert-BpsToMbps $globalTxBps
        $globalRxStatus = Get-LimitStatusText -CurrentMbps $globalRxMbps -LimitMbps ([double]$bandwidthSettings.Global.RxMbps)
        $globalTxStatus = Get-LimitStatusText -CurrentMbps $globalTxMbps -LimitMbps ([double]$bandwidthSettings.Global.TxMbps)
        if ([double]$bandwidthSettings.Global.RxMbps -gt 0 -or [double]$bandwidthSettings.Global.TxMbps -gt 0) {
            Write-UiHost ("Limite globale : RX " + (Format-Mbps ([double]$bandwidthSettings.Global.RxMbps)) + " (" + $globalRxStatus.Text + ") / TX " + (Format-Mbps ([double]$bandwidthSettings.Global.TxMbps)) + " (" + $globalTxStatus.Text + ")") -ForegroundColor $globalRxStatus.Color
        }
    } else {
        Write-UiHost "Vitesse globale : calcul au prochain refresh" -ForegroundColor Yellow
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
    Write-UiHost ($Name.PadRight(28) + ": ") -NoNewline -ForegroundColor DarkGray
    Write-UiHost $Value -ForegroundColor $Color
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


function Test-DeviceRemoved([string]$ClientName, [string]$TunnelName, [string]$BaseDir) {
    $serverConfig = Get-ServerConfigPath -TunnelName $TunnelName -BaseDir $BaseDir
    $clientConfig = Join-Path $BaseDir "clients\$ClientName.conf"

    $clientFileRemoved = -not (Test-Path $clientConfig)
    $peerRemoved = $true
    if (Test-Path $serverConfig) {
        $content = Get-Content $serverConfig -Raw -ErrorAction SilentlyContinue
        if ($content -match "(?m)^#\s*$([regex]::Escape($ClientName))\s*$") { $peerRemoved = $false }
    }

    return ($clientFileRemoved -and $peerRemoved)
}


function Test-DeviceAdded([string]$ClientName, [string]$TunnelName, [string]$BaseDir) {
    $serverConfig = Get-ServerConfigPath -TunnelName $TunnelName -BaseDir $BaseDir
    $clientConfig = Join-Path $BaseDir "clients\$ClientName.conf"

    $clientFilePresent = Test-Path $clientConfig
    $peerPresent = $false
    if (Test-Path $serverConfig) {
        $content = Get-Content $serverConfig -Raw -ErrorAction SilentlyContinue
        if ($content -match "(?m)^#\s*$([regex]::Escape($ClientName))\s*$") { $peerPresent = $true }
    }

    return ($clientFilePresent -and $peerPresent)
}



function Test-QrFeatureEnabled([string]$BaseDir) {
    $enabledFlag = Join-Path $BaseDir "features\qr-enabled.flag"
    return (Test-Path $enabledFlag)
}

function Generate-DeviceQrFromConsole([string]$BaseDir, [string]$ClientName = "") {
    if (-not (Test-QrFeatureEnabled -BaseDir $BaseDir)) { throw "Fonctionnalite QR desactivee. Relance l'installation et accepte la dependance QR pour l'activer." }
    $scriptPath = Join-Path $PSScriptRoot "scripts\Generate-WireGuardClientQr.ps1"
    if (-not (Test-Path $scriptPath)) { throw "Script QR introuvable : $scriptPath" }

    $clientDir = Join-Path $BaseDir "clients"
    $clients = @()
    if (Test-Path $clientDir) { $clients = @(Get-ChildItem $clientDir -Filter "*.conf" -ErrorAction SilentlyContinue) }

    if ([string]::IsNullOrWhiteSpace($ClientName)) {
        Write-UiHost ""
        Write-UiHost "Generer un QR code WireGuard" -ForegroundColor Cyan
        Write-UiHost "----------------------------" -ForegroundColor DarkGray

        if ($clients.Length -eq 0) {
            throw "Aucune configuration .conf trouvee dans $clientDir"
        } elseif ($clients.Length -eq 1) {
            $ClientName = $clients[0].BaseName
            Write-UiHost "Un seul appareil detecte : $ClientName" -ForegroundColor Yellow
        } else {
            Write-UiHost "0 - Annuler"
            for ($i = 0; $i -lt $clients.Length; $i++) {
                Write-UiHost ("{0} - {1}" -f ($i + 1), $clients[$i].BaseName)
            }
            Write-UiHost ""
            $choice = (Read-UiHost "Tape le numero de l'appareil, ou son nom exact").Trim()
            if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) { return "Generation QR annulee." }
            if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $clients.Length) {
                $ClientName = $clients[[int]$choice - 1].BaseName
            } else {
                $ClientName = $choice
            }
        }
    }

    Write-Ultra "Generation QR: ClientName=$ClientName Script=$scriptPath"
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ClientName $ClientName -BaseDir $BaseDir -Open 2>&1
    $code = $LASTEXITCODE
    $outputText = ($output | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($outputText)) {
        Write-Ultra "Sortie script QR: $outputText"
        Write-UiHost $outputText
    }
    if ($code -ne 0) { throw "Echec de generation du QR code pour '$ClientName'." }

    return "QR code genere pour : $ClientName"
}

function Add-DeviceFromConsole([string]$TunnelName, [int]$ListenPort, [string]$BaseDir) {
    Write-Ultra "Action: ajout appareil"
    Assert-ProjectInstalled -TunnelName $TunnelName -BaseDir $BaseDir
    $scriptPath = Join-Path $PSScriptRoot "scripts\Add-WireGuardPeer.ps1"
    if (-not (Test-Path $scriptPath)) { throw "Script d'ajout introuvable : $scriptPath" }

    Write-UiHost ""
    Write-UiHost "Ajouter un appareil" -ForegroundColor Cyan
    Write-UiHost "-------------------" -ForegroundColor DarkGray
    $clientName = (Read-UiHost "Nom de l'appareil, ex: iphone, android, laptop").Trim()
    if ([string]::IsNullOrWhiteSpace($clientName)) { throw "Nom d'appareil vide." }

    $defaultEndpoint = Get-DefaultEndpoint -ListenPort $ListenPort -BaseDir $BaseDir
    $endpointInput = (Read-UiHost "Endpoint public ou DNS [$defaultEndpoint]").Trim()
    $endpoint = if ([string]::IsNullOrWhiteSpace($endpointInput)) { $defaultEndpoint } else { $endpointInput }

    $clientNumber = Get-NextClientNumber -TunnelName $TunnelName -BaseDir $BaseDir
    Write-UiHost "IP VPN attribuee automatiquement : 10.66.66.$clientNumber" -ForegroundColor DarkCyan
    Write-Ultra "Ajout appareil: ClientName=$clientName Endpoint=$endpoint ClientNumber=$clientNumber ListenPort=$ListenPort TunnelName=$TunnelName Script=$scriptPath"

    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ClientName $clientName -Endpoint $endpoint -ClientNumber $clientNumber -ListenPort $ListenPort -TunnelName $TunnelName 2>&1
    $code = $LASTEXITCODE
    Write-Ultra "Code retour script ajout: $code"
    $outputText = ($output | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($outputText)) {
        Write-Ultra "Sortie script ajout: $outputText"
        Write-UiHost $outputText
    }

    $added = Test-DeviceAdded -ClientName $clientName -TunnelName $TunnelName -BaseDir $BaseDir
    Write-Ultra "Verification ajout: added=$added clientConf=$(Join-Path $BaseDir "clients\$clientName.conf") serverConfig=$(Get-ServerConfigPath -TunnelName $TunnelName -BaseDir $BaseDir)"
    if ($code -ne 0 -and -not $added) {
        $details = ($output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($details)) { $details = "Aucun detail retourne par le script d'ajout." }
        throw "Echec de l'ajout de l'appareil '$clientName'. Details: $details"
    }

    $clientDir = Join-Path $BaseDir "clients"
    if (Test-Path $clientDir) { Start-Process explorer.exe $clientDir }

    $qrMessage = ""
    if (Test-QrFeatureEnabled -BaseDir $BaseDir) {
        try {
            $qrMessage = "`n" + (Generate-DeviceQrFromConsole -BaseDir $BaseDir -ClientName $clientName)
        } catch {
            $qrMessage = "`nQR non genere automatiquement : $($_.Exception.Message)"
        }
    }

    if ($code -ne 0 -and $added) {
        return "Appareil ajoute : $clientName. Note : le script a retourne une erreur apres creation, probablement pendant le rechargement du service. Fichier .conf genere dans $clientDir. Si besoin, utilise 3 pour redemarrer le serveur VPN.$qrMessage"
    }

    return "Appareil ajoute : $clientName. Fichier .conf genere dans $clientDir.$qrMessage"
}

function Remove-DeviceFromConsole([string]$TunnelName, [string]$BaseDir) {
    Write-Ultra "Action: suppression appareil"
    Assert-ProjectInstalled -TunnelName $TunnelName -BaseDir $BaseDir
    $scriptPath = Join-Path $PSScriptRoot "scripts\Remove-WireGuardPeer.ps1"
    if (-not (Test-Path $scriptPath)) { throw "Script de suppression introuvable : $scriptPath" }

    $clientDir = Join-Path $BaseDir "clients"
    $clients = @()
    if (Test-Path $clientDir) { $clients = @(Get-ChildItem $clientDir -Filter "*.conf" -ErrorAction SilentlyContinue) }

    Write-UiHost ""
    Write-UiHost "Supprimer un appareil" -ForegroundColor Cyan
    Write-UiHost "---------------------" -ForegroundColor DarkGray
    if ($clients.Length -eq 1) {
        $clientName = $clients[0].BaseName
        Write-UiHost "1 - $clientName" -ForegroundColor DarkCyan
        Write-UiHost ""
        Write-UiHost "Un seul appareil est configure. Selection automatique : $clientName" -ForegroundColor Yellow
    } elseif ($clients.Length -gt 1) {
        Write-UiHost "0 - Annuler"
        for ($i = 0; $i -lt $clients.Length; $i++) {
            Write-UiHost ("{0} - {1}" -f ($i + 1), $clients[$i].BaseName)
        }
        Write-UiHost ""
        $choice = (Read-UiHost "Tape le numero de l'appareil a supprimer, ou son nom exact").Trim()
        if ($choice -eq '0') { return "Suppression annulee." }
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $clients.Length) {
            $clientName = $clients[[int]$choice - 1].BaseName
        } else {
            $clientName = $choice
        }
    } else {
        Write-UiHost "Aucun fichier .conf trouve dans $clientDir" -ForegroundColor Yellow
        $clientName = (Read-UiHost "Nom exact de l'appareil a supprimer, ou laisse vide pour annuler").Trim()
        if ([string]::IsNullOrWhiteSpace($clientName)) { return "Suppression annulee." }
    }

    if ([string]::IsNullOrWhiteSpace($clientName)) { return "Suppression annulee." }
    $confirm = (Read-UiHost "Confirmer la suppression de '$clientName' ? Tape O pour confirmer [o/N]").Trim().ToLowerInvariant()
    if ($confirm -notin @('o','oui','y','yes')) { return "Suppression annulee." }

    Write-Ultra "Suppression appareil: ClientName=$clientName TunnelName=$TunnelName Script=$scriptPath"
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ClientName $clientName -TunnelName $TunnelName 2>&1
    $code = $LASTEXITCODE
    Write-Ultra "Code retour script suppression: $code"
    $outputText = ($output | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($outputText)) {
        Write-Ultra "Sortie script suppression: $outputText"
        Write-UiHost $outputText
    }

    $removed = Test-DeviceRemoved -ClientName $clientName -TunnelName $TunnelName -BaseDir $BaseDir
    Write-Ultra "Verification suppression: removed=$removed clientConf=$(Join-Path $BaseDir "clients\$clientName.conf") serverConfig=$(Get-ServerConfigPath -TunnelName $TunnelName -BaseDir $BaseDir)"
    if ($code -ne 0 -and -not $removed) {
        throw "Echec de la suppression de l'appareil '$clientName'."
    }

    if ($code -ne 0 -and $removed) {
        return "Appareil supprime : $clientName. Note : le script a retourne une erreur apres suppression, probablement pendant le rechargement du service. Si besoin, utilise 3 pour redemarrer le serveur VPN."
    }

    return "Appareil supprime : $clientName"
}


function Show-BandwidthMenu([string]$BaseDir) {
    $settings = Get-BandwidthSettings -BaseDir $BaseDir
    while ($true) {
        Clear-Host
        Write-UiHost "WinWG - Parametres bande passante" -ForegroundColor Green
        Write-UiHost "==================================" -ForegroundColor DarkGray
        Write-UiHost "Mode actuel : monitoring uniquement (alerte/affichage, pas de bridage reseau dur)." -ForegroundColor Yellow
        Write-UiHost "RX = trafic recu par le serveur depuis les peers. TX = trafic envoye par le serveur vers les peers." -ForegroundColor DarkGray
        Write-UiHost ""
        Write-UiHost ("Limite globale RX : " + (Format-Mbps ([double]$settings.Global.RxMbps))) -ForegroundColor Cyan
        Write-UiHost ("Limite globale TX : " + (Format-Mbps ([double]$settings.Global.TxMbps))) -ForegroundColor Cyan
        Write-UiHost ""
        Write-UiHost "Limites par peer:" -ForegroundColor Cyan
        $peerProps = @($settings.Peers.PSObject.Properties)
        if ($peerProps.Count -eq 0) {
            Write-UiHost "  aucune" -ForegroundColor DarkGray
        } else {
            foreach ($prop in $peerProps) {
                Write-UiHost ("  " + $prop.Name + " -> RX " + (Format-Mbps ([double]$prop.Value.RxMbps)) + " / TX " + (Format-Mbps ([double]$prop.Value.TxMbps))) -ForegroundColor DarkCyan
            }
        }
        Write-UiHost ""
        Write-UiHost "1 - Definir limite globale"
        Write-UiHost "2 - Definir limite pour un peer/appareil"
        Write-UiHost "3 - Supprimer limite d'un peer/appareil"
        Write-UiHost "4 - Reinitialiser toutes les limites"
        Write-UiHost "Q - Retour"
        Write-UiHost ""
        $choice = (Read-UiHost "Choix").Trim().ToLowerInvariant()
        switch ($choice) {
            '1' {
                $rx = Read-MbpsValue -Prompt "Limite globale RX en Mbps, 0 = illimite" -Default ([double]$settings.Global.RxMbps)
                $tx = Read-MbpsValue -Prompt "Limite globale TX en Mbps, 0 = illimite" -Default ([double]$settings.Global.TxMbps)
                $settings.Global.RxMbps = $rx
                $settings.Global.TxMbps = $tx
                Save-BandwidthSettings -BaseDir $BaseDir -Settings $settings | Out-Null
            }
            '2' {
                $clientDir = Join-Path $BaseDir "clients"
                $clients = @()
                if (Test-Path $clientDir) { $clients = @(Get-ChildItem $clientDir -Filter "*.conf" -ErrorAction SilentlyContinue) }
                if ($clients.Count -gt 0) {
                    for ($i = 0; $i -lt $clients.Count; $i++) { Write-UiHost ("{0} - {1}" -f ($i + 1), $clients[$i].BaseName) }
                }
                $nameInput = (Read-UiHost "Nom du peer/appareil ou numero").Trim()
                if ($nameInput -match '^\d+$' -and [int]$nameInput -ge 1 -and [int]$nameInput -le $clients.Count) { $peerName = $clients[[int]$nameInput - 1].BaseName } else { $peerName = $nameInput }
                if ([string]::IsNullOrWhiteSpace($peerName)) { continue }
                $current = Get-PeerLimitSettings -Settings $settings -PeerName $peerName
                $defaultRx = if ($current) { [double]$current.RxMbps } else { 0 }
                $defaultTx = if ($current) { [double]$current.TxMbps } else { 0 }
                $rx = Read-MbpsValue -Prompt "Limite RX pour $peerName en Mbps, 0 = illimite" -Default $defaultRx
                $tx = Read-MbpsValue -Prompt "Limite TX pour $peerName en Mbps, 0 = illimite" -Default $defaultTx
                Set-PeerLimitSettings -Settings $settings -PeerName $peerName -RxMbps $rx -TxMbps $tx
                Save-BandwidthSettings -BaseDir $BaseDir -Settings $settings | Out-Null
            }
            '3' {
                $peerName = (Read-UiHost "Nom exact du peer/appareil").Trim()
                if (-not [string]::IsNullOrWhiteSpace($peerName)) {
                    Remove-PeerLimitSettings -Settings $settings -PeerName $peerName
                    Save-BandwidthSettings -BaseDir $BaseDir -Settings $settings | Out-Null
                }
            }
            '4' {
                $settings = New-DefaultBandwidthSettings
                Save-BandwidthSettings -BaseDir $BaseDir -Settings $settings | Out-Null
            }
            'q' { return "Parametres bande passante enregistres." }
        }
    }
}

function Show-Status([string]$LastMessage = "") {
    Clear-Host
    Write-UiHost "WinWG OneClick Server - Console serveur unifiee" -ForegroundColor Green
    Write-UiHost "Surveillance + controle du service VPN dans une seule console." -ForegroundColor DarkGray
    Write-UiHost "Menu interactif: pas de rafraichissement automatique." -ForegroundColor Cyan
    $verboseText = if ($script:UltraVerboseMode) { "active" } else { "desactive" }
    Write-UiHost "Mode ultra verbeux: $verboseText" -ForegroundColor DarkYellow
    if ($script:UltraVerboseMode -and $script:LogFilePath) { Write-UiHost "Log: $script:LogFilePath" -ForegroundColor DarkGray }
    Write-UiHost "============================================================" -ForegroundColor DarkGray
    if (-not [string]::IsNullOrWhiteSpace($LastMessage)) {
        Write-UiHost ""
        Write-UiHost $LastMessage -ForegroundColor Yellow
    }
    Write-UiHost ""

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
        foreach ($c in $clients) { Write-UiHost "  - $($c.FullName)" -ForegroundColor DarkCyan }
    } else {
        Write-Line "Configs telephone" "dossier introuvable" Yellow
    }

    Write-UiHost ""
    if ($svc -and $svc.Status -eq 'Running' -and $installed) {
        $show = Get-WgShow -TunnelName $TunnelName
        if ([string]::IsNullOrWhiteSpace($show)) {
            Write-UiHost "Aucune sortie wg show." -ForegroundColor Yellow
        } else {
            Write-PeerDashboard -WgShowText $show -ServerConfigPath $serverConfig -BaseDir $BaseDir
            Write-UiHost ""
            Write-UiHost "Details WireGuard bruts" -ForegroundColor Cyan
            Write-UiHost "-----------------------" -ForegroundColor DarkGray
            Write-UiHost $show
        }
    } else {
        Write-UiHost "WireGuard n'est pas actif, aucun handshake a afficher." -ForegroundColor Yellow
    }

    Write-UiHost ""
    Write-UiHost "Aide rapide" -ForegroundColor Cyan
    Write-UiHost "- Si le telephone est connecte, il apparait dans 'Telephones / peers' avec un handshake recent."
    Write-UiHost "- La vitesse RX/TX est calculee entre deux rafraichissements du statut. Utilise S pour mesurer."
}

function Show-MainMenu {
    Write-UiHost ""
    Write-UiHost "Actions" -ForegroundColor Cyan
    Write-UiHost "-------" -ForegroundColor DarkGray
    Write-UiHost "1 / A - Activer / demarrer le serveur VPN"
    Write-UiHost "2 / D - Desactiver / arreter le serveur VPN"
    Write-UiHost "3     - Redemarrer le serveur VPN"
    Write-UiHost "4 / N - Ajouter un nouvel appareil"
    Write-UiHost "5 / R - Retirer / supprimer un appareil"
    if (Test-QrFeatureEnabled -BaseDir $BaseDir) { Write-UiHost "6 / G - Generer un QR code pour un appareil" }
    Write-UiHost "S     - Rafraichir le statut"
    Write-UiHost "V     - Activer/desactiver le mode ultra verbeux"
    Write-UiHost "Q     - Quitter"
    Write-UiHost ""
}


function Pause-ConsoleAction([string]$Message) {
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Write-UiHost ""
        Write-UiHost $Message -ForegroundColor Yellow
    }
    Write-UiHost ""
    [void](Read-UiHost "Appuie sur Entree pour revenir au menu")
}

try {
    Assert-Admin
    Initialize-ConsoleLog -BaseDir $BaseDir
    Write-Ultra "Console demarree. BaseDir=$BaseDir TunnelName=$TunnelName ListenPort=$ListenPort"
    $host.UI.RawUI.WindowTitle = "WinWG OneClick Server - Console serveur unifiee"
    $lastMessage = ""
    while ($true) {
        Show-Status -LastMessage $lastMessage
        $lastMessage = ""
        Show-MainMenu
        $choice = (Read-UiHost "Choix").Trim().ToLowerInvariant()
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
            { $_ -in @('6','g') } {
                if (Test-QrFeatureEnabled -BaseDir $BaseDir) {
                    try { $lastMessage = Generate-DeviceQrFromConsole -BaseDir $BaseDir } catch { $lastMessage = "ERREUR QR code : $($_.Exception.Message)" }
                    Pause-ConsoleAction $lastMessage
                    $lastMessage = ""
                } else {
                    $lastMessage = "Option QR desactivee. Elle n'apparait pas dans le menu car la dependance QR n'a pas ete installee/activee."
                }
            }
            { $_ -in @('7','b') } {
                try { $lastMessage = Show-BandwidthMenu -BaseDir $BaseDir } catch { $lastMessage = "ERREUR bande passante : $($_.Exception.Message)" }
            }
            's' { $lastMessage = "Statut rafraichi." }
            'v' {
                $script:UltraVerboseMode = -not $script:UltraVerboseMode
                $state = if ($script:UltraVerboseMode) { "active" } else { "desactive" }
                $lastMessage = "Mode ultra verbeux $state. Log: $script:LogFilePath"
                Write-Log $lastMessage
            }
            'q' { return }
            default { $lastMessage = "Choix invalide. Utilise 1/2/3/4/5/6/7, A/D/N/R/G/B, S, V ou Q." }
        }
    }
} catch {
    Write-UiHost "ERREUR : $($_.Exception.Message)" -ForegroundColor Red
    Write-UiHost "Appuie sur une touche pour fermer..."
    [void][Console]::ReadKey($true)
    exit 1
}
