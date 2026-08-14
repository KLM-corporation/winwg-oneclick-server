<#
.SYNOPSIS
  Diagnostic UPnP/PCP/NAT-PMP pour WinWG OneClick Server.

.DESCRIPTION
  Outil de diagnostic non destructif. Il ne cree pas de redirection de port.
  Il affiche les reponses SSDP brutes, les descriptions XML, les services NAT detectes,
  et teste la presence de reponses PCP/NAT-PMP sur UDP 5351.
#>
[CmdletBinding()]
param(
    [int]$Port = 51820,
    [int]$TimeoutMs = 2500,
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$lines = New-Object System.Collections.Generic.List[string]

function Write-Diag([string]$Text = "", [ConsoleColor]$Color = [ConsoleColor]::White) {
    Write-Host $Text -ForegroundColor $Color
    $script:lines.Add($Text) | Out-Null
}

function Get-PrimaryIPv4Info {
    try {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
            Sort-Object RouteMetric, InterfaceMetric |
            Select-Object -First 1
        if ($route) {
            $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction Stop |
                Where-Object { $_.IPAddress -notlike '169.254.*' } |
                Select-Object -First 1
            return [pscustomobject]@{
                LocalIP = $ip.IPAddress
                Gateway = $route.NextHop
                InterfaceIndex = $route.InterfaceIndex
                InterfaceAlias = $ip.InterfaceAlias
            }
        }
    } catch {}
    return [pscustomobject]@{ LocalIP = $null; Gateway = $null; InterfaceIndex = $null; InterfaceAlias = $null }
}

function Send-MSearch([string]$Target, [string]$LocalIp, [string]$Gateway, [string]$Mode, [int]$TimeoutMs) {
    $responses = @()
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.UdpClient
        $client.Client.ReceiveTimeout = $TimeoutMs
        $client.EnableBroadcast = $true
        $client.MulticastLoopback = $false

        if ($Mode -eq 'bound' -and $LocalIp) {
            $client.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($LocalIp), 0))
        }

        $request = "M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 2`r`nST: $Target`r`n`r`n"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($request)

        if ($Mode -eq 'unicast' -and $Gateway) {
            [void]$client.Send($bytes, $bytes.Length, $Gateway, 1900)
        } else {
            [void]$client.Send($bytes, $bytes.Length, '239.255.255.250', 1900)
        }

        $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
        while ((Get-Date) -lt $deadline) {
            try {
                $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
                $buffer = $client.Receive([ref]$remote)
                $text = [System.Text.Encoding]::ASCII.GetString($buffer)
                $responses += [pscustomobject]@{ Remote = $remote.ToString(); Text = $text; Mode = $Mode }
            } catch { break }
        }
    } catch {
        Write-Diag "[SSDP/$Mode] Error for ${Target}: $($_.Exception.Message)" Yellow
    } finally { if ($client) { $client.Close() } }
    return $responses
}

function Get-HeaderValue([string]$Response, [string]$Header) {
    foreach ($line in ($Response -split "`r?`n")) {
        if ($line -match ("^(?i)" + [regex]::Escape($Header) + "\s*:\s*(.+)$")) {
            return $Matches[1].Trim()
        }
    }
    return $null
}

function Join-UriSafe([string]$BaseUri, [string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $BaseUri }
    if ($Path -match '^https?://') { return $Path }
    $base = [System.Uri]$BaseUri
    $root = $base.Scheme + '://' + $base.Authority
    if ($Path.StartsWith('/')) { return ($root + $Path) }
    $baseText = $base.AbsoluteUri
    $lastSlash = $baseText.LastIndexOf('/')
    if ($lastSlash -ge 0) { return ($baseText.Substring(0, $lastSlash + 1) + $Path) }
    return ($root + '/' + $Path)
}

function Get-XmlFirstText($XmlDocument, [string]$Name) {
    try {
        $nodes = $XmlDocument.GetElementsByTagName($Name)
        if ($nodes -and $nodes.Count -gt 0) { return $nodes.Item(0).InnerText }
    } catch {}
    return $null
}

function Get-XmlChildText($Node, [string]$Name) {
    foreach ($child in $Node.ChildNodes) {
        if ($child.LocalName -eq $Name) { return $child.InnerText }
    }
    return $null
}

function Test-Udp5351([string]$Gateway, [string]$LocalIp, [byte[]]$Payload, [string]$Name) {
    if (-not $Gateway) { Write-Diag "[$Name] Gateway missing" Yellow; return }
    $client = $null
    try {
        $client = [System.Net.Sockets.UdpClient]::new()
        $client.Client.ReceiveTimeout = 2500
        if ($LocalIp) {
            $client.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($LocalIp), 0))
        }
        $ep = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($Gateway), 5351)
        [void]$client.Send($Payload, $Payload.Length, $ep)
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        $resp = $client.Receive([ref]$remote)
        $hex = ($resp | ForEach-Object { $_.ToString('X2') }) -join ' '
        Write-Diag "[$Name] Response from $($remote.ToString()) length=$($resp.Length) bytes=$hex" Green
    } catch {
        Write-Diag "[$Name] No response or error: $($_.Exception.Message)" Yellow
    } finally { if ($client) { $client.Close() } }
}

function New-NatPmpProbe([int]$Port) {
    $b = New-Object byte[] 12
    $b[0]=0; $b[1]=1
    $b[4]=[byte](($Port -shr 8) -band 255); $b[5]=[byte]($Port -band 255)
    $b[6]=[byte](($Port -shr 8) -band 255); $b[7]=[byte]($Port -band 255)
    $lifetime=[uint32]3600
    $b[8]=[byte](($lifetime -shr 24) -band 255); $b[9]=[byte](($lifetime -shr 16) -band 255); $b[10]=[byte](($lifetime -shr 8) -band 255); $b[11]=[byte]($lifetime -band 255)
    return $b
}

function New-PcpMapProbe([string]$LocalIp, [int]$Port) {
    $b = New-Object byte[] 60
    $b[0]=2; $b[1]=1
    $lifetime=[uint32]3600
    $b[4]=[byte](($lifetime -shr 24) -band 255); $b[5]=[byte](($lifetime -shr 16) -band 255); $b[6]=[byte](($lifetime -shr 8) -band 255); $b[7]=[byte]($lifetime -band 255)
    $v4=[System.Net.IPAddress]::Parse($LocalIp).GetAddressBytes()
    $b[18]=0xff; $b[19]=0xff; $b[20]=$v4[0]; $b[21]=$v4[1]; $b[22]=$v4[2]; $b[23]=$v4[3]
    $rng=[System.Security.Cryptography.RandomNumberGenerator]::Create(); $nonce=New-Object byte[] 12; $rng.GetBytes($nonce); [Array]::Copy($nonce,0,$b,24,12)
    $b[36]=17
    $b[40]=[byte](($Port -shr 8) -band 255); $b[41]=[byte]($Port -band 255)
    $b[42]=[byte](($Port -shr 8) -band 255); $b[43]=[byte]($Port -band 255)
    return $b
}

$net = Get-PrimaryIPv4Info
Write-Diag "WinWG UPnP / PCP / NAT-PMP diagnostic" Cyan
Write-Diag "Local IP      : $($net.LocalIP)"
Write-Diag "Gateway       : $($net.Gateway)"
Write-Diag "Interface     : $($net.InterfaceAlias) / index $($net.InterfaceIndex)"
Write-Diag "Target mapping: UDP $Port -> $($net.LocalIP):$Port"
Write-Diag ""

$targets = @('ssdp:all','upnp:rootdevice','urn:schemas-upnp-org:device:InternetGatewayDevice:1','urn:schemas-upnp-org:device:InternetGatewayDevice:2','urn:schemas-upnp-org:service:WANIPConnection:1','urn:schemas-upnp-org:service:WANIPConnection:2','urn:schemas-upnp-org:service:WANPPPConnection:1')
$locations = New-Object System.Collections.ArrayList
$ssdpModes = @('bound', 'unbound', 'unicast')
foreach ($target in $targets) {
    foreach ($mode in $ssdpModes) {
        Write-Diag "[SSDP/$mode] M-SEARCH $target" Cyan
        foreach ($r in (Send-MSearch -Target $target -LocalIp $net.LocalIP -Gateway $net.Gateway -Mode $mode -TimeoutMs $TimeoutMs)) {
            $location = Get-HeaderValue -Response $r.Text -Header 'LOCATION'
            $st = Get-HeaderValue -Response $r.Text -Header 'ST'
            $usn = Get-HeaderValue -Response $r.Text -Header 'USN'
            $server = Get-HeaderValue -Response $r.Text -Header 'SERVER'
            Write-Diag "  From     : $($r.Remote)"
            Write-Diag "  Mode     : $($r.Mode)"
            Write-Diag "  ST       : $st"
            Write-Diag "  USN      : $usn"
            Write-Diag "  LOCATION : $location"
            Write-Diag "  SERVER   : $server"
            Write-Diag ""
            if ($location -and -not $locations.Contains($location)) { [void]$locations.Add($location) }
        }
    }
}

Write-Diag "== Device descriptions ==" Cyan
foreach ($location in @($locations | Select-Object -Unique)) {
    Write-Diag "[DESC] $location" Cyan
    try {
        $resp = Invoke-WebRequest -Uri $location -UseBasicParsing -TimeoutSec 5
        $content = [string]$resp.Content
        [xml]$xml = $content
        Write-Diag "  DeviceType  : $(Get-XmlFirstText $xml 'deviceType')"
        Write-Diag "  FriendlyName: $(Get-XmlFirstText $xml 'friendlyName')"
        Write-Diag "  Manufacturer: $(Get-XmlFirstText $xml 'manufacturer')"
        $found = $false
        foreach ($svc in $xml.GetElementsByTagName('service')) {
            $type = Get-XmlChildText $svc 'serviceType'
            $control = Get-XmlChildText $svc 'controlURL'
            $scpd = Get-XmlChildText $svc 'SCPDURL'
            if ($type) {
                Write-Diag "  Service     : $type"
                Write-Diag "    controlURL: $control"
                Write-Diag "    SCPDURL   : $scpd"
                if ($type -match 'WANIPConnection|WANPPPConnection') {
                    $found = $true
                    Write-Diag "    NAT       : YES -> $(Join-UriSafe $location $control)" Green
                }
            }
        }
        if (-not $found) { Write-Diag "  NAT service : NO" DarkGray }
    } catch {
        Write-Diag "  Could not parse description: $($_.Exception.Message)" Yellow
    }
    Write-Diag ""
}

Write-Diag "== PCP / NAT-PMP UDP 5351 probes ==" Cyan
Test-Udp5351 -Gateway $net.Gateway -LocalIp $net.LocalIP -Payload (New-PcpMapProbe -LocalIp $net.LocalIP -Port $Port) -Name 'PCP MAP'
Test-Udp5351 -Gateway $net.Gateway -LocalIp $net.LocalIP -Payload (New-NatPmpProbe -Port $Port) -Name 'NAT-PMP UDP MAP'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $outDir = Join-Path $env:ProgramData 'WinWGOneClickServer\logs'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $OutputPath = Join-Path $outDir ('upnp-debug-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
}
$lines | Set-Content -Path $OutputPath -Encoding UTF8
Write-Diag ""
Write-Diag "Diagnostic saved to: $OutputPath" Green
