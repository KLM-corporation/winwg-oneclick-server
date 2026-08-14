<#
.SYNOPSIS
  Installation one-click d'un serveur WireGuard sur Windows pour connexion appareil hors LAN.

.DESCRIPTION
  Double-clique INSTALLER-ONE-CLICK.bat. Ce script :
  - s'eleve en admin via le .bat ;
  - installe WireGuard si absent ;
  - detecte l'IP publique ;
  - demande seulement le nom de l'appareil et l'endpoint si besoin ;
  - genere serveur + device ;
  - active routage, firewall, NAT ;
  - installe le tunnel WireGuard ;
  - tente une redirection UPnP UDP 51820 sur la box si disponible ;
  - ouvre le dossier contenant la config appareil.
#>
[CmdletBinding()]
param(
    [int]$ListenPort = 51820,
    [string]$TunnelName = "winwg-server",
    [string]$VpnCidr = "10.66.66.0/24",
    [string]$ServerVpnIp = "10.66.66.1",
    [string]$DeviceVpnIp = "10.66.66.2",
    [string]$Dns = "1.1.1.1, 8.8.8.8"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$script:InstallLanguage = "en"
$languageScript = Join-Path $PSScriptRoot "WinWG-Language.ps1"
if (Test-Path $languageScript) { . $languageScript }

function TInstall([string]$Fr, [string]$En) {
    if ($script:InstallLanguage -eq "fr") { return $Fr }
    return $En
}

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Ok([string]$Text) {
    Write-Host "OK - $Text" -ForegroundColor Green
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Ce script doit etre lance en administrateur. Utilise INSTALLER-ONE-CLICK.bat."
    }
}

function Ask-Text([string]$Title, [string]$Prompt, [string]$Default) {
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
        $value = [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $Default)
        if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
        return $value.Trim()
    } catch {
        Write-Host "$Prompt [$Default] : " -NoNewline
        $value = Read-Host
        if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
        return $value.Trim()
    }
}


function Ask-YesNo([string]$Title, [string]$Prompt, [bool]$DefaultYes = $true) {
    $defaultText = if ($DefaultYes) { "yes/oui" } else { "no/non" }
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
        $value = [Microsoft.VisualBasic.Interaction]::InputBox("$Prompt`n`nAnswer yes/no or oui/non.", $Title, $defaultText)
        if ([string]::IsNullOrWhiteSpace($value)) { return $DefaultYes }
        $v = $value.Trim().ToLowerInvariant()
        return ($v -in @('o','oui','y','yes','1','true'))
    } catch {
        $suffix = if ($DefaultYes) { "Y/o / n" } else { "y/o / N" }
        $value = Read-Host "$Prompt [$suffix]"
        if ([string]::IsNullOrWhiteSpace($value)) { return $DefaultYes }
        $v = $value.Trim().ToLowerInvariant()
        return ($v -in @('o','oui','y','yes','1','true'))
    }
}


function Ask-YesNoRequired([string]$Title, [string]$Prompt) {
    while ($true) {
        try {
            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
            $value = [Microsoft.VisualBasic.Interaction]::InputBox("$Prompt`n`nType yes/no or oui/non. Empty is not accepted.", $Title, "")
            $v = $value.Trim().ToLowerInvariant()
        } catch {
            $v = (Read-Host "$Prompt [yes/no - oui/non]").Trim().ToLowerInvariant()
        }

        if ($v -in @('o','oui','y','yes','1','true')) { return $true }
        if ($v -in @('n','non','no','0','false')) { return $false }

        Write-Host "Please answer yes/no or oui/non. Empty input is not accepted." -ForegroundColor Yellow
    }
}

function Get-PublicEndpoint([int]$Port) {
    $services = @(
        "https://api.ipify.org",
        "https://ifconfig.me/ip",
        "https://icanhazip.com"
    )
    foreach ($svc in $services) {
        try {
            $ip = (Invoke-RestMethod -Uri $svc -TimeoutSec 8).ToString().Trim()
            if ($ip -match '^[0-9]{1,3}(\.[0-9]{1,3}){3}$') { return $ip }
        } catch {}
    }
    return "TON_IP_PUBLIQUE_OU_DNS"
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
    return $null
}

function Ensure-WireGuard {
    $wgExe = Join-Path $env:ProgramFiles "WireGuard\wg.exe"
    $wireguardExe = Join-Path $env:ProgramFiles "WireGuard\wireguard.exe"
    if ((Test-Path $wgExe) -and (Test-Path $wireguardExe)) {
        Write-Ok (TInstall "WireGuard est deja installe" "WireGuard is already installed")
        return [pscustomobject]@{ WgExe = $wgExe; WireGuardExe = $wireguardExe }
    }

    Write-Step (TInstall "Installation de WireGuard" "Installing WireGuard")
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Start-Process "https://www.wireguard.com/install/"
        throw "winget est introuvable. Installe WireGuard manuellement, puis relance l'installeur."
    }

    & winget install --id WireGuard.WireGuard -e --accept-source-agreements --accept-package-agreements | Out-Host

    if (-not ((Test-Path $wgExe) -and (Test-Path $wireguardExe))) {
        throw "WireGuard n'a pas ete trouve apres installation. Redemarre PowerShell ou installe WireGuard manuellement."
    }
    Write-Ok (TInstall "WireGuard installe" "WireGuard installed")
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

function Ensure-Directory([string]$Path) { if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null } }

function Enable-IPv4Forwarding {
    Write-Step (TInstall "Activation du routage IPv4 Windows" "Enabling Windows IPv4 routing")
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name IPEnableRouter -Value 1
    Get-NetIPInterface -AddressFamily IPv4 | ForEach-Object {
        try { Set-NetIPInterface -InterfaceIndex $_.InterfaceIndex -Forwarding Enabled -ErrorAction Stop } catch {}
    }
    Write-Ok (TInstall "Routage IPv4 active" "IPv4 routing enabled")
}

function Ensure-Firewall([int]$Port) {
    Write-Step (TInstall "Configuration du pare-feu Windows" "Configuring Windows Firewall")
    $fwName = "WireGuard Server UDP $Port"
    Get-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $fwName -Direction Inbound -Action Allow -Protocol UDP -LocalPort $Port | Out-Null
    Write-Ok (TInstall "Port UDP $Port autorise dans le pare-feu" "UDP port $Port allowed in firewall")
}

function Ensure-Nat([string]$Cidr) {
    Write-Step (TInstall "Configuration du NAT Windows" "Configuring Windows NAT")
    $natName = "WinWGOneClickServerNAT"
    Get-NetNat -Name $natName -ErrorAction SilentlyContinue | Remove-NetNat -Confirm:$false
    New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix $Cidr | Out-Null
    Write-Ok (TInstall "NAT cree pour $Cidr" "NAT created for $Cidr")
}

function Try-UpnpPortForward([int]$Port, [string]$LanIp) {
    if (-not $LanIp) { return $false }

    Write-Step (TInstall "Tentative rapide de redirection automatique UPnP" "Quick automatic UPnP port-forwarding attempt")

    try {
        $nat = New-Object -ComObject HNetCfg.NATUPnP
        $mappings = $nat.StaticPortMappingCollection
        if ($null -eq $mappings) {
            Write-Host (TInstall "UPnP automatique indisponible ou non expose par la box." "Automatic UPnP unavailable or not exposed by the router.") -ForegroundColor Yellow
            Write-Host (TInstall "Pour un diagnostic detaille, lance DEBUG-UPNP.bat." "For detailed diagnostics, run DEBUG-UPNP.bat.") -ForegroundColor Yellow
            return $false
        }

        try { $mappings.Remove($Port, "UDP") } catch {}
        $description = "WinWG OneClick Server UDP $Port"
        $mappings.Add($Port, "UDP", $Port, $LanIp, $true, $description) | Out-Null
        Start-Sleep -Milliseconds 500

        try {
            $mapping = $mappings.Item($Port, "UDP")
            if ($mapping -and [string]$mapping.InternalClient -eq $LanIp -and [int]$mapping.InternalPort -eq $Port) {
                Write-Ok (TInstall "Redirection UPnP verifiee : UDP $Port -> $LanIp`:$Port" "UPnP forwarding verified: UDP $Port -> $LanIp`:$Port")
                return $true
            }
        } catch {}

        Write-Host (TInstall "UPnP a tente de creer la regle, mais la verification a echoue." "UPnP tried to create the rule, but verification failed.") -ForegroundColor Yellow
        Write-Host (TInstall "Pour analyser la box, lance DEBUG-UPNP.bat." "To analyze the router, run DEBUG-UPNP.bat.") -ForegroundColor Yellow
        return $false
    } catch {
        Write-Host (TInstall "UPnP automatique impossible : $($_.Exception.Message)" "Automatic UPnP failed: $($_.Exception.Message)") -ForegroundColor Yellow
        Write-Host (TInstall "Pour un diagnostic detaille, lance DEBUG-UPNP.bat." "For detailed diagnostics, run DEBUG-UPNP.bat.") -ForegroundColor Yellow
        return $false
    }
}



function Get-PublicIPv6Candidate {
    try {
        $defaultRoute = Get-NetRoute -AddressFamily IPv6 -DestinationPrefix '::/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric, InterfaceMetric |
            Select-Object -First 1

        $addresses = @(Get-NetIPAddress -AddressFamily IPv6 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notmatch '^fe80:' -and
                $_.IPAddress -ne '::1' -and
                $_.IPAddress -notmatch '^(fc|fd)' -and
                $_.IPAddress -match '^(2|3)' -and
                $_.AddressState -ne 'Deprecated'
            })

        if ($defaultRoute) {
            $preferred = $addresses | Where-Object { $_.InterfaceIndex -eq $defaultRoute.InterfaceIndex } | Select-Object -First 1
            if ($preferred) { return $preferred.IPAddress }
        }

        $fallback = $addresses | Select-Object -First 1
        if ($fallback) { return $fallback.IPAddress }
    } catch {}
    return $null
}

function Ensure-IPv6Firewall([int]$Port) {
    Write-Step (TInstall "Configuration du pare-feu Windows IPv6" "Configuring Windows IPv6 firewall")
    $fwName = "WinWG WireGuard UDP $Port IPv6"
    Get-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $fwName -Direction Inbound -Action Allow -Protocol UDP -LocalPort $Port -RemoteAddress Any -LocalAddress Any | Out-Null
    Write-Ok (TInstall "Pare-feu IPv6 autorise sur UDP $Port" "IPv6 firewall allowed on UDP $Port")
}

function Select-IPv6FallbackOrManual([int]$Port, [string]$LanIp) {
    Write-Host ""
    Write-Host (TInstall "La redirection automatique IPv4 a echoue." "Automatic IPv4 port forwarding failed.") -ForegroundColor Yellow
    Write-Host (TInstall "Choisis comment continuer :" "Choose how to continue:") -ForegroundColor Cyan
    Write-Host (TInstall "1 - Redirection manuelle IPv4 : UDP $Port -> $LanIp`:$Port" "1 - Manual IPv4 forwarding: UDP $Port -> $LanIp`:$Port")
    Write-Host (TInstall "2 - Essayer la methode IPv6 automatique (endpoint IPv6, pas de NAT IPv4)" "2 - Try automatic IPv6 method (IPv6 endpoint, no IPv4 NAT)")
    Write-Host ""
    $choice = (Read-Host (TInstall "Choix [1]" "Choice [1]")).Trim()
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }

    if ($choice -ne '2') {
        return [pscustomobject]@{
            UseIPv6 = $false
            Endpoint = $null
            Succeeded = $false
            Method = 'manual-required'
            Message = 'Manual IPv4 forwarding selected or required'
        }
    }

    $ipv6 = Get-PublicIPv6Candidate
    if ([string]::IsNullOrWhiteSpace($ipv6)) {
        Write-Host (TInstall "Aucune IPv6 publique globale detectee sur ce PC." "No global public IPv6 address detected on this PC.") -ForegroundColor Yellow
        Write-Host (TInstall "Retour a la redirection manuelle IPv4." "Falling back to manual IPv4 forwarding.") -ForegroundColor Yellow
        return [pscustomobject]@{
            UseIPv6 = $false
            Endpoint = $null
            Succeeded = $false
            Method = 'manual-required'
            Message = 'No public IPv6 detected; manual IPv4 forwarding required'
        }
    }

    Ensure-IPv6Firewall -Port $Port
    $endpoint = "[$ipv6]"
    Write-Host (TInstall "Endpoint IPv6 propose : $endpoint`:$Port" "Suggested IPv6 endpoint: $endpoint`:$Port") -ForegroundColor Green
    Write-Host (TInstall "Important : la box et le pare-feu IPv6 doivent autoriser UDP $Port vers ce PC." "Important: the router and IPv6 firewall must allow UDP $Port to this PC.") -ForegroundColor Yellow

    return [pscustomobject]@{
        UseIPv6 = $true
        Endpoint = $endpoint
        Succeeded = $true
        Method = 'ipv6-endpoint'
        Message = "IPv6 endpoint selected: $endpoint`:$Port"
    }
}

function Save-PortForwardStatus([string]$BaseDir, [int]$Port, [string]$LanIp, [bool]$Succeeded, [string]$Method, [string]$Message) {
    $settingsDir = Join-Path $BaseDir "settings"
    Ensure-Directory $settingsDir
    $path = Join-Path $settingsDir "port-forwarding.json"
    $status = [ordered]@{
        checkedAt = (Get-Date).ToUniversalTime().ToString('o')
        port = $Port
        protocol = 'UDP'
        lanIp = $LanIp
        succeeded = $Succeeded
        method = $Method
        message = $Message
        manualRule = "UDP $Port -> $LanIp`:$Port"
    }
    [pscustomobject]$status | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8
    return $path
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
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut = $stdout
        StdErr = $stderr
    }
}


function Set-QrFeaturePreference([string]$BaseDir, [bool]$Enabled) {
    $featureDir = Join-Path $BaseDir "features"
    Ensure-Directory $featureDir
    $enabledFlag = Join-Path $featureDir "qr-enabled.flag"
    $disabledFlag = Join-Path $featureDir "qr-disabled.flag"
    if ($Enabled) {
        Set-Content -Path $enabledFlag -Value "enabled" -Encoding ASCII
        Remove-Item $disabledFlag -Force -ErrorAction SilentlyContinue
    } else {
        Set-Content -Path $disabledFlag -Value "disabled" -Encoding ASCII
        Remove-Item $enabledFlag -Force -ErrorAction SilentlyContinue
    }
}

function Install-QrDependency([string]$BaseDir) {
    $toolsDir = Join-Path $BaseDir "tools"
    $qrDir = Join-Path $toolsDir "QRCoder"
    $dllCandidates = @(
        (Join-Path $qrDir "lib\netstandard2.0\QRCoder.dll"),
        (Join-Path $qrDir "lib\net6.0\QRCoder.dll"),
        (Join-Path $qrDir "lib\net5.0\QRCoder.dll"),
        (Join-Path $qrDir "lib\net40\QRCoder.dll")
    )

    foreach ($dll in $dllCandidates) {
        if (Test-Path $dll) {
            Write-Ok (TInstall "Dependance QR deja presente : QRCoder" "QR dependency already present: QRCoder")
            return $dll
        }
    }

    Ensure-Directory $toolsDir
    Ensure-Directory $qrDir

    $nupkg = Join-Path $toolsDir "QRCoder.nupkg"
    $zip = Join-Path $toolsDir "QRCoder.zip"
    $url = "https://www.nuget.org/api/v2/package/QRCoder"

    Write-Step (TInstall "Installation de la dependance optionnelle QR code" "Installing optional QR code dependency")
    Write-Host (TInstall "Telechargement de QRCoder depuis NuGet. Les configurations WireGuard ne sont pas envoyees a Internet." "Downloading QRCoder from NuGet. WireGuard configurations are not sent to the Internet.") -ForegroundColor Yellow
    Invoke-WebRequest -Uri $url -OutFile $nupkg -UseBasicParsing
    Copy-Item $nupkg $zip -Force
    Expand-Archive -Path $zip -DestinationPath $qrDir -Force

    foreach ($dll in $dllCandidates) {
        if (Test-Path $dll) {
            Write-Ok (TInstall "Dependance QR installee : QRCoder" "QR dependency installed: QRCoder")
            return $dll
        }
    }

    throw "Impossible d'installer la dependance QR QRCoder."
}

function Install-Tunnel([string]$WireGuardExe, [string]$TunnelName, [string]$ConfigPath) {
    Write-Step (TInstall "Installation/redemarrage du tunnel WireGuard" "Installing/restarting WireGuard tunnel")

    # WireGuard renvoie une erreur si le service n'existe pas encore.
    # C'est normal lors de la premiere installation, donc on l'ignore.
    $remove = Invoke-WireGuardNoThrow -WireGuardExe $WireGuardExe -Arguments @('/uninstalltunnelservice', $TunnelName)
    if ($remove.ExitCode -ne 0 -and $remove.StdErr -notmatch 'does not exist|n.existe pas|service.*introuvable|specified service') {
        Write-Host (TInstall "Ancien tunnel non supprime, nouvelle tentative possible : $($remove.StdErr.Trim())" "Previous tunnel was not removed cleanly, retry may be needed: $($remove.StdErr.Trim())") -ForegroundColor Yellow
    }

    Start-Sleep -Seconds 2

    $install = Invoke-WireGuardNoThrow -WireGuardExe $WireGuardExe -Arguments @('/installtunnelservice', $ConfigPath)
    if ($install.ExitCode -ne 0) {
        $message = ($install.StdErr + $install.StdOut).Trim()

        if ($message -match 'already installed|already running|deja installe|deja en cours|Tunnel already') {
            Write-Host (TInstall "Tunnel deja installe/demarre detecte. Nettoyage puis nouvelle tentative..." "Tunnel already installed/running detected. Cleaning up and retrying...") -ForegroundColor Yellow
            [void](Invoke-WireGuardNoThrow -WireGuardExe $WireGuardExe -Arguments @('/uninstalltunnelservice', $TunnelName))
            Start-Sleep -Seconds 3
            $install = Invoke-WireGuardNoThrow -WireGuardExe $WireGuardExe -Arguments @('/installtunnelservice', $ConfigPath)
        }

        if ($install.ExitCode -ne 0) {
            $message = ($install.StdErr + $install.StdOut).Trim()
            if ([string]::IsNullOrWhiteSpace($message)) { $message = "wireguard.exe a retourne le code $($install.ExitCode)" }
            throw $message
        }
    }
    Write-Ok (TInstall "Tunnel installe : $TunnelName" "Tunnel installed: $TunnelName")
}



function Save-DeviceMetadata([string]$BaseDir, [string]$DeviceName, [string]$VpnIp) {
    $deviceDir = Join-Path $BaseDir "devices"
    if (-not (Test-Path $deviceDir)) { New-Item -ItemType Directory -Path $deviceDir -Force | Out-Null }
    $path = Join-Path $deviceDir "$DeviceName.meta.json"
    $metadata = [ordered]@{
        name = $DeviceName
        type = 'permanent'
        temporary = $false
        createdAt = (Get-Date).ToUniversalTime().ToString('o')
        expiresAt = $null
        vpnIp = $VpnIp
        configPath = (Join-Path $deviceDir "$DeviceName.conf")
    }
    [pscustomobject]$metadata | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8
    return $path
}

function Get-ExistingServerListenPort([string]$ServerConfigPath, [int]$DefaultPort) {
    if (Test-Path $ServerConfigPath) {
        $content = Get-Content $ServerConfigPath -Raw -ErrorAction SilentlyContinue
        if ($content -match '(?m)^ListenPort\s*=\s*(\d+)') { return [int]$Matches[1] }
    }
    return $DefaultPort
}

function Get-NextExistingDeviceNumber([string]$ServerConfigPath) {
    $used = @()
    if (Test-Path $ServerConfigPath) {
        foreach ($line in Get-Content $ServerConfigPath) {
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

function Show-ExistingConfigMenu([string]$Language, [string]$ServerConfigPath) {
    Write-Host ""
    if ($Language -eq 'fr') {
        Write-Host "Configuration existante detectee" -ForegroundColor Yellow
        Write-Host "--------------------------------" -ForegroundColor DarkGray
        Write-Host "Une configuration serveur existe deja : $ServerConfigPath"
        Write-Host ""
        Write-Host "1 - Restaurer/reinstaller le service avec cette configuration"
        Write-Host "2 - Ajouter un nouvel appareil a cette configuration"
        Write-Host "3 - Reinstaller proprement et regenerer toutes les cles"
        Write-Host "4 - Annuler"
        Write-Host ""
        return (Read-Host "Choix").Trim()
    }

    Write-Host "Existing configuration detected" -ForegroundColor Yellow
    Write-Host "-------------------------------" -ForegroundColor DarkGray
    Write-Host "A server configuration already exists: $ServerConfigPath"
    Write-Host ""
    Write-Host "1 - Restore/reinstall the service with this configuration"
    Write-Host "2 - Add a new device to this configuration"
    Write-Host "3 - Clean reinstall and regenerate all keys"
    Write-Host "4 - Cancel"
    Write-Host ""
    return (Read-Host "Choice").Trim()
}

function Start-ConsoleIfAvailable {
    $projectRoot = Split-Path $PSScriptRoot -Parent
    $consoleBat = Join-Path $projectRoot "SERVER-CONSOLE.bat"
    if (Test-Path $consoleBat) {
        Write-Host ""
        Write-Host (TInstall "Ouverture de la console serveur de supervision..." "Opening the server monitoring console...") -ForegroundColor Cyan
        Start-Process -FilePath $consoleBat
    } else {
        Write-Host (TInstall "Console serveur introuvable : $consoleBat" "Server console not found: $consoleBat") -ForegroundColor Yellow
    }
}

function Restore-ExistingInstallation([string]$BaseDir, [string]$ServerConfigPath, [string]$TunnelName, [int]$ListenPort, [string]$VpnCidr) {
    $tools = @(Ensure-WireGuard)[-1]
    if (-not $tools -or -not $tools.PSObject.Properties["WireGuardExe"]) { throw "Impossible de recuperer les chemins WireGuard apres installation." }
    $wireguardExe = $tools.WireGuardExe

    $existingPort = Get-ExistingServerListenPort -ServerConfigPath $ServerConfigPath -DefaultPort $ListenPort
    Enable-IPv4Forwarding
    Ensure-Firewall -Port $existingPort
    Ensure-Nat -Cidr $VpnCidr
    Install-Tunnel -WireGuardExe $wireguardExe -TunnelName $TunnelName -ConfigPath $ServerConfigPath
    $lanIp = Get-PrimaryIPv4
    $restoreUpnpOk = Try-UpnpPortForward -Port $existingPort -LanIp $lanIp
    if ($restoreUpnpOk) {
        [void](Save-PortForwardStatus -BaseDir $BaseDir -Port $existingPort -LanIp $lanIp -Succeeded $true -Method 'UPnP' -Message 'Automatic port forwarding succeeded during restore')
    } else {
        [void](Save-PortForwardStatus -BaseDir $BaseDir -Port $existingPort -LanIp $lanIp -Succeeded $false -Method 'manual-required' -Message 'Automatic port forwarding failed or unavailable during restore')
    }

    Write-Host ""
    Write-Host (TInstall "Configuration existante restauree." "Existing configuration restored.") -ForegroundColor Green
    Write-Host (TInstall "Tunnel serveur : $TunnelName" "Server tunnel: $TunnelName")
    Write-Host (TInstall "Port WireGuard : UDP $existingPort" "WireGuard port: UDP $existingPort")
    Start-ConsoleIfAvailable
}

function Add-DeviceToExistingInstallation([string]$BaseDir, [string]$ServerConfigPath, [string]$TunnelName, [int]$ListenPort, [string]$Dns) {
    $tools = @(Ensure-WireGuard)[-1]
    if (-not $tools -or -not $tools.PSObject.Properties["WireGuardExe"]) { throw "Impossible de recuperer les chemins WireGuard apres installation." }

    $existingPort = Get-ExistingServerListenPort -ServerConfigPath $ServerConfigPath -DefaultPort $ListenPort
    $defaultEndpoint = Get-PublicEndpoint -Port $existingPort
    $deviceName = Ask-Text "WireGuard" (TInstall "Nom du nouvel appareil" "New device name") "device"
    $endpoint = Ask-Text "WireGuard" (TInstall "IP publique ou DNS a utiliser cote appareil. Laisse la valeur detectee si tu n'as pas de DNS dynamique." "Public IP or DNS to use on the device side. Keep the detected value if you do not have dynamic DNS.") $defaultEndpoint
    $deviceDns = Ask-Text "WireGuard" (TInstall "DNS a utiliser sur cet appareil. Laisse vide / ne tape rien pour garder le DNS par defaut." "DNS to use on this device. Leave empty / type nothing to keep the default DNS.") $Dns
    $deviceNumber = Get-NextExistingDeviceNumber -ServerConfigPath $ServerConfigPath

    $addScript = Join-Path $PSScriptRoot "Add-WireGuardPeer.ps1"
    if (-not (Test-Path $addScript)) { throw "Script d'ajout introuvable : $addScript" }

    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $addScript -DeviceName $deviceName -Endpoint $endpoint -DeviceNumber $deviceNumber -ListenPort $existingPort -Dns $deviceDns -TunnelName $TunnelName -Language $Language 2>&1
    if ($output) { $output | Out-Host }
    if ($LASTEXITCODE -ne 0) { throw (TInstall "Echec de l'ajout de l'appareil." "Failed to add device.") }

    $featuresDir = Join-Path $BaseDir "features"
    $qrEnabled = Test-Path (Join-Path $featuresDir "qr-enabled.flag")
    if ($qrEnabled) {
        $generateQr = Ask-YesNoRequired "WinWG QR Code" (TInstall "Generer un QR code pour ce nouvel appareil ? Tape oui ou non ; laisser le champ vide n'est pas accepte." "Generate a QR code for this new device? Please type yes or no; leaving the field empty is not accepted.")
        if ($generateQr) {
            $qrScript = Join-Path $PSScriptRoot "Generate-WireGuardDeviceQr.ps1"
            if (Test-Path $qrScript) {
                $safeName = ($deviceName -replace '[^a-zA-Z0-9_-]', '_')
                $qrOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $qrScript -DeviceName $safeName -BaseDir $BaseDir -Language $Language -Open 2>&1
                if ($qrOutput) { $qrOutput | Out-Host }
            }
        }
    }

    Start-ConsoleIfAvailable
}

try {
    Assert-Admin
    $host.UI.RawUI.WindowTitle = "WinWG OneClick Server - One Click"

    $baseDir = Join-Path $env:ProgramData "WinWGOneClickServer"
    $serverDir = Join-Path $baseDir "server"
    $deviceDir = Join-Path $baseDir "devices"
    Ensure-Directory $serverDir
    Ensure-Directory $deviceDir

    # First interactive action: language selection.
    # Keep this prompt bilingual so English/French users can understand before any other question.
    $Language = "en"
    if (Get-Command Select-WinWGLanguage -ErrorAction SilentlyContinue) {
        $Language = Select-WinWGLanguage -BaseDir $baseDir
    }

    $script:InstallLanguage = $Language

    if ($Language -eq "fr") {
        Write-Host "Langue selectionnee : Francais" -ForegroundColor Green
        Write-Host "WinWG OneClick Server - installation one click" -ForegroundColor Green
        Write-Host "Ce script va configurer ce PC comme serveur VPN WireGuard pour ton appareil."
        $deviceNamePrompt = "Nom de l'appareil/device"
        $endpointPrompt = "IP publique ou DNS a utiliser cote appareil. Laisse la valeur detectee si tu n'as pas de DNS dynamique."
        $dnsPrompt = "DNS a utiliser sur cet appareil. Laisse vide / ne tape rien pour garder le DNS par defaut. Exemples : 1.1.1.1, 8.8.8.8 ou l'IP DNS de ta box comme 192.168.1.1"
        $qrPrompt = "Installer le generateur de QR code integre ? Cela permet d'importer la configuration dans l'app WireGuard mobile en scannant un QR code. La dependance QRCoder sera telechargee depuis NuGet, mais tes cles/configurations ne sont pas envoyees a Internet. Tape oui ou non ; laisser le champ vide n'est pas accepte."
    } else {
        Write-Host "Selected language: English" -ForegroundColor Green
        Write-Host "WinWG OneClick Server - one-click installation" -ForegroundColor Green
        Write-Host "This script will configure this PC as a WireGuard VPN server for your device."
        $deviceNamePrompt = "Device name"
        $endpointPrompt = "Public IP or DNS to use on the device side. Keep the detected value if you do not have dynamic DNS."
        $dnsPrompt = "DNS to use on this device. Leave empty / type nothing to keep the default DNS. Examples: 1.1.1.1, 8.8.8.8 or your router DNS such as 192.168.1.1"
        $qrPrompt = "Install the integrated QR code generator? This lets you import the configuration in the WireGuard mobile app by scanning a QR code. The QRCoder dependency will be downloaded from NuGet, but your keys/configurations are not sent to the Internet. Please type yes or no; leaving the field empty is not accepted."
    }

    $serverConfigPath = Join-Path $serverDir "$TunnelName.conf"
    if (Test-Path $serverConfigPath) {
        $existingChoice = Show-ExistingConfigMenu -Language $Language -ServerConfigPath $serverConfigPath
        switch ($existingChoice) {
            '1' {
                Restore-ExistingInstallation -BaseDir $baseDir -ServerConfigPath $serverConfigPath -TunnelName $TunnelName -ListenPort $ListenPort -VpnCidr $VpnCidr
                return
            }
            '2' {
                Add-DeviceToExistingInstallation -BaseDir $baseDir -ServerConfigPath $serverConfigPath -TunnelName $TunnelName -ListenPort $ListenPort -Dns $Dns
                return
            }
            '3' {
                $confirmText = TInstall "Tape REINSTALLER pour supprimer l'ancienne configuration et regenerer toutes les cles" "Type REINSTALL to delete the old configuration and regenerate all keys"
                $confirm = (Read-Host $confirmText).Trim()
                if ($confirm -ne 'REINSTALL' -and $confirm -ne 'REINSTALLER') { throw (TInstall "Reinstallation annulee." "Reinstall cancelled.") }
                $existingWireGuardExe = Join-Path $env:ProgramFiles "WireGuard\wireguard.exe"
                if (Test-Path $existingWireGuardExe) {
                    Write-Host (TInstall "Suppression de l'ancien service tunnel avant reinstallation..." "Removing previous tunnel service before reinstall...") -ForegroundColor Yellow
                    [void](Invoke-WireGuardNoThrow -WireGuardExe $existingWireGuardExe -Arguments @('/uninstalltunnelservice', $TunnelName))
                    Start-Sleep -Seconds 2
                }
                Remove-Item $baseDir -Recurse -Force
                Ensure-Directory $serverDir
                Ensure-Directory $deviceDir
                if (Get-Command Set-WinWGLanguage -ErrorAction SilentlyContinue) { Set-WinWGLanguage -BaseDir $baseDir -Language $Language | Out-Null }
            }
            default { throw (TInstall "Installation annulee." "Installation cancelled.") }
        }
    }

    $tools = @(Ensure-WireGuard)[-1]
    if (-not $tools -or -not $tools.PSObject.Properties["WgExe"] -or -not $tools.PSObject.Properties["WireGuardExe"]) { throw "Impossible de recuperer les chemins WireGuard apres installation." }
    $wgExe = $tools.WgExe
    $wireguardExe = $tools.WireGuardExe

    $enableQrFeature = Ask-YesNoRequired "WinWG QR Code" $qrPrompt
    if ($enableQrFeature) {
        try {
            Install-QrDependency -BaseDir $baseDir | Out-Null
            Set-QrFeaturePreference -BaseDir $baseDir -Enabled $true
        } catch {
            Write-Host "Installation QR impossible : $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "La fonctionnalite QR sera desactivee. Tu pourras toujours importer le fichier .conf manuellement." -ForegroundColor Yellow
            Set-QrFeaturePreference -BaseDir $baseDir -Enabled $false
            $enableQrFeature = $false
        }
    } else {
        Set-QrFeaturePreference -BaseDir $baseDir -Enabled $false
        Write-Host "Fonctionnalite QR desactivee par choix utilisateur." -ForegroundColor Yellow
    }

    Write-Step (TInstall "Generation de la configuration serveur" "Generating server configuration")
    $serverPrivateKey = New-WgPrivateKey $wgExe
    $serverPublicKey = Get-WgPublicKey $wgExe $serverPrivateKey

    # Important: the first device/peer is created later, after the server service,
    # firewall, NAT and automatic port mapping attempts are completed.
    $serverConfig = @"
[Interface]
PrivateKey = $serverPrivateKey
Address = $ServerVpnIp/24
ListenPort = $ListenPort
"@

    Set-Content -Path $serverConfigPath -Value $serverConfig -Encoding ASCII
    Write-Ok (TInstall "Configuration serveur creee : $serverConfigPath" "Server configuration created: $serverConfigPath")

    Enable-IPv4Forwarding
    Ensure-Firewall -Port $ListenPort
    Ensure-Nat -Cidr $VpnCidr
    Install-Tunnel -WireGuardExe $wireguardExe -TunnelName $TunnelName -ConfigPath $serverConfigPath

    $lanIp = Get-PrimaryIPv4
    $upnpOk = Try-UpnpPortForward -Port $ListenPort -LanIp $lanIp
    $endpointOverride = $null
    $portForwardMethod = 'UPnP'
    $portForwardMessage = 'Automatic port forwarding succeeded'
    $portForwardSucceeded = $upnpOk

    if (-not $upnpOk) {
        $fallbackChoice = Select-IPv6FallbackOrManual -Port $ListenPort -LanIp $lanIp
        $endpointOverride = $fallbackChoice.Endpoint
        $portForwardMethod = $fallbackChoice.Method
        $portForwardMessage = $fallbackChoice.Message
        $portForwardSucceeded = [bool]$fallbackChoice.Succeeded
    }

    [void](Save-PortForwardStatus -BaseDir $baseDir -Port $ListenPort -LanIp $lanIp -Succeeded $portForwardSucceeded -Method $portForwardMethod -Message $portForwardMessage)

    Write-Step (TInstall "Parametres du premier appareil" "First device settings")
    $defaultEndpoint = if ($endpointOverride) { $endpointOverride } else { Get-PublicEndpoint -Port $ListenPort }
    $deviceName = Ask-Text "WireGuard" $deviceNamePrompt "appareil"
    $endpoint = Ask-Text "WireGuard" $endpointPrompt $defaultEndpoint
    $Dns = Ask-Text "WireGuard" $dnsPrompt $Dns
    $safeDeviceName = ($deviceName -replace '[^a-zA-Z0-9_-]', '_')
    $deviceConfigPath = Join-Path $deviceDir "$safeDeviceName.conf"

    Write-Step (TInstall "Creation du premier appareil / peer" "Creating first device / peer")
    $devicePrivateKey = New-WgPrivateKey $wgExe
    $devicePublicKey = Get-WgPublicKey $wgExe $devicePrivateKey
    $psk = New-WgPresharedKey $wgExe

    $peerBlock = @"

# $safeDeviceName
[Peer]
PublicKey = $devicePublicKey
PresharedKey = $psk
AllowedIPs = $DeviceVpnIp/32
"@
    Add-Content -Path $serverConfigPath -Value $peerBlock -Encoding ASCII

    $deviceConfig = @"
[Interface]
PrivateKey = $devicePrivateKey
Address = $DeviceVpnIp/32
DNS = $Dns

[Peer]
PublicKey = $serverPublicKey
PresharedKey = $psk
Endpoint = $endpoint`:$ListenPort
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
"@

    Set-Content -Path $deviceConfigPath -Value $deviceConfig -Encoding ASCII
    $metaPath = Save-DeviceMetadata -BaseDir $baseDir -DeviceName $safeDeviceName -VpnIp $DeviceVpnIp
    Write-Ok (TInstall "Configuration appareil creee : $deviceConfigPath" "Device configuration created: $deviceConfigPath")
    Write-Ok (TInstall "Metadonnees appareil creees : $metaPath" "Device metadata created: $metaPath")

    Write-Step (TInstall "Rechargement du tunnel avec le premier appareil" "Reloading tunnel with the first device")
    Install-Tunnel -WireGuardExe $wireguardExe -TunnelName $TunnelName -ConfigPath $serverConfigPath

    if ($enableQrFeature) {
        $generateFirstQrPrompt = TInstall "Generer un QR code pour ce premier appareil ? Tape oui ou non ; laisser le champ vide n'est pas accepte." "Generate a QR code for this first device? Please type yes or no; leaving the field empty is not accepted."
        $generateFirstQr = Ask-YesNoRequired "WinWG QR Code" $generateFirstQrPrompt
        if ($generateFirstQr) {
            $qrScript = Join-Path $PSScriptRoot "Generate-WireGuardDeviceQr.ps1"
            if (Test-Path $qrScript) {
                Write-Step (TInstall "Generation du QR code du premier appareil" "Generating QR code for the first device")
                $qrOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $qrScript -DeviceName $safeDeviceName -BaseDir $baseDir -Language $Language -Open 2>&1
                $qrCode = $LASTEXITCODE
                if ($qrOutput) { $qrOutput | Out-Host }
                if ($qrCode -ne 0) {
                    Write-Host (TInstall "QR code non genere automatiquement. Tu peux le generer plus tard depuis la console." "QR code was not generated automatically. You can generate it later from the console.") -ForegroundColor Yellow
                }
            } else {
                Write-Host (TInstall "Script QR introuvable. Tu peux importer le fichier .conf manuellement." "QR script not found. You can import the .conf file manually.") -ForegroundColor Yellow
            }
        } else {
            Write-Host (TInstall "QR code non genere pour ce premier appareil. Le fichier .conf reste disponible." "QR code not generated for this first device. The .conf file is still available.") -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host (TInstall "INSTALLATION TERMINEE" "INSTALLATION COMPLETE") -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host (TInstall "Tunnel serveur : $TunnelName" "Server tunnel: $TunnelName")
    Write-Host (TInstall "Port WireGuard : UDP $ListenPort" "WireGuard port: UDP $ListenPort")
    Write-Host (TInstall "IP VPN serveur : $ServerVpnIp" "VPN server IP: $ServerVpnIp")
    Write-Host (TInstall "IP VPN appareil : $DeviceVpnIp" "Device VPN IP: $DeviceVpnIp")
    Write-Host (TInstall "Fichier a importer dans l'app WireGuard de l’appareil :" "File to import into the WireGuard app:")
    Write-Host "  $deviceConfigPath" -ForegroundColor Yellow
    Write-Host ""

    if ($upnpOk) {
        Write-Host (TInstall "La redirection de port automatique UPnP a reussi. Tu peux tester en 4G/5G." "Automatic UPnP port forwarding succeeded. You can test from mobile data.") -ForegroundColor Green
    } elseif ($portForwardMethod -eq 'ipv6-endpoint') {
        Write-Host (TInstall "Mode IPv6 selectionne : aucune redirection NAT IPv4 n'est necessaire pour les clients compatibles IPv6." "IPv6 mode selected: no IPv4 NAT forwarding is required for IPv6-capable clients.") -ForegroundColor Green
        Write-Host (TInstall "Endpoint utilise : $endpoint`:$ListenPort" "Endpoint used: $endpoint`:$ListenPort") -ForegroundColor Green
        Write-Host (TInstall "Si l'appareil distant n'a pas IPv6, il faudra utiliser la redirection IPv4 manuelle." "If the remote device has no IPv6, manual IPv4 forwarding will still be required.") -ForegroundColor Yellow
    } else {
        Write-Host (TInstall "Action manuelle probablement necessaire sur ta box :" "Manual action probably required on your router:") -ForegroundColor Yellow
        Write-Host (TInstall "  Rediriger UDP $ListenPort vers l'IP locale du PC : $lanIp" "  Forward UDP $ListenPort to the PC local IP: $lanIp")
        Write-Host (TInstall "Si ta box est en CG-NAT, il faudra demander une IPv4 publique a ton operateur." "If your ISP uses CG-NAT, ask for a public/full-stack IPv4 address.")
    }

    Write-Host ""
    Write-Host (TInstall "Etapes appareil :" "Device steps:")
    Write-Host (TInstall "1. Installe l'app WireGuard." "1. Install the WireGuard app.")
    Write-Host (TInstall "2. Copie/import le fichier .conf ci-dessus." "2. Copy/import the .conf file above.")
    Write-Host (TInstall "3. Coupe le Wi-Fi, passe en 4G/5G, active le tunnel." "3. Disable Wi-Fi, use mobile data, enable the tunnel.")
    Write-Host (TInstall "4. Verifie l'IP sur https://ifconfig.me." "4. Check the IP on https://ifconfig.me.")

    Start-Process explorer.exe $deviceDir

    Start-ConsoleIfAvailable
} catch {
    Write-Host ""
    Write-Host "ERREUR : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Consulte docs\TROUBLESHOOTING.md ou relance le script en administrateur."
    exit 1
}
