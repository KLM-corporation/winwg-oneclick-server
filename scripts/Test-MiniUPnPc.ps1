<#
.SYNOPSIS
  Temporary diagnostic using miniupnpc/upnpc.exe as a reference implementation.

.DESCRIPTION
  Downloads the official prebuilt upnpc Windows executable from miniupnp.free.fr,
  runs discovery/status, optionally tries to create UDP port mapping, and saves a log.

  This is a diagnostic helper. It is not part of the normal WinWG flow.
#>
[CmdletBinding()]
param(
    [int]$Port = 51820,
    [string]$DownloadUrl = 'http://miniupnp.free.fr/files/upnpc-exe-win32-20220515.zip',
    [string]$BaseDir = "$env:ProgramData\WinWGOneClickServer"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$logLines = New-Object System.Collections.Generic.List[string]

function Write-LogLine([string]$Text = '', [ConsoleColor]$Color = [ConsoleColor]::White) {
    Write-Host $Text -ForegroundColor $Color
    $script:logLines.Add($Text) | Out-Null
}

function Invoke-LoggedCommand([string]$Exe, [string[]]$Arguments, [string]$Title) {
    Write-LogLine ""
    Write-LogLine "==> $Title" Cyan
    Write-LogLine ("Command: " + $Exe + " " + ($Arguments -join ' ')) DarkGray

    # Use ProcessStartInfo instead of PowerShell native redirection.
    # Some upnpc messages are written to stderr and PowerShell 5.1 can convert them
    # into NativeCommandError records when $ErrorActionPreference='Stop'.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
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
    $code = $process.ExitCode

    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        foreach ($line in ($stdout -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { Write-LogLine $line }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        foreach ($line in ($stderr -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { Write-LogLine ("STDERR: " + $line) Yellow }
        }
    }

    Write-LogLine "Exit code: $code" DarkGray
    return [pscustomobject]@{ ExitCode = $code; Output = ($stdout + "`n" + $stderr) }
}

function Get-PrimaryIPv4Info {
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
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
    throw 'Unable to detect primary IPv4 interface.'
}

function Ensure-MiniUPnPc {
    $toolsDir = Join-Path $BaseDir 'tools\miniupnpc'
    $zipPath = Join-Path $toolsDir 'upnpc.zip'
    $extractDir = Join-Path $toolsDir 'extracted'
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    $existing = Get-ChildItem -Path $extractDir -Recurse -Filter 'upnpc*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) { return $existing.FullName }

    Write-LogLine "Downloading miniupnpc/upnpc from:" Yellow
    Write-LogLine $DownloadUrl Yellow
    Write-LogLine "Only the diagnostic binary is downloaded. No WireGuard config/key is uploaded." DarkGray
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    $exe = Get-ChildItem -Path $extractDir -Recurse -Filter 'upnpc*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { throw "Could not find upnpc.exe after extracting $zipPath" }
    return $exe.FullName
}

Write-LogLine 'WinWG temporary miniupnpc diagnostic' Green
Write-LogLine '------------------------------------' DarkGray
Write-LogLine 'This uses miniupnpc as a reference tool to compare with WinWG PowerShell UPnP.' Yellow
Write-LogLine 'It may create a real temporary router port mapping if you confirm.' Yellow
Write-LogLine ''

$net = Get-PrimaryIPv4Info
Write-LogLine "Local IP : $($net.LocalIP)"
Write-LogLine "Gateway  : $($net.Gateway)"
Write-LogLine "Interface: $($net.InterfaceAlias) / index $($net.InterfaceIndex)"
Write-LogLine "Target   : UDP $Port -> $($net.LocalIP):$Port"

$upnpc = Ensure-MiniUPnPc
Write-LogLine "upnpc.exe: $upnpc" Green

Invoke-LoggedCommand -Exe $upnpc -Arguments @('-s') -Title 'miniupnpc status/discovery: upnpc -s' | Out-Null
Invoke-LoggedCommand -Exe $upnpc -Arguments @('-l') -Title 'miniupnpc current mappings: upnpc -l' | Out-Null

Write-LogLine ''
$answer = (Read-Host "Try to create mapping UDP $Port -> $($net.LocalIP):$Port with upnpc? Type YES to continue").Trim()
if ($answer -eq 'YES') {
    Invoke-LoggedCommand -Exe $upnpc -Arguments @('-a', $net.LocalIP, "$Port", "$Port", 'UDP') -Title "miniupnpc add mapping: UDP $Port" | Out-Null
    Invoke-LoggedCommand -Exe $upnpc -Arguments @('-l') -Title 'miniupnpc mappings after add: upnpc -l' | Out-Null
} else {
    Write-LogLine 'Mapping creation skipped by user.' Yellow
}

$logDir = Join-Path $BaseDir 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logPath = Join-Path $logDir ('miniupnpc-test-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
$logLines | Set-Content -Path $logPath -Encoding UTF8
Write-LogLine ''
Write-LogLine "Diagnostic saved to: $logPath" Green
