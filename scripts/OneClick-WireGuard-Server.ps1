<#
.SYNOPSIS
  Installation one-click d'un serveur WireGuard sur Windows pour connexion telephone hors LAN.

.DESCRIPTION
  Double-clique INSTALLER-ONE-CLICK.bat. Ce script :
  - s'eleve en admin via le .bat ;
  - installe WireGuard si absent ;
  - detecte l'IP publique ;
  - demande seulement le nom du telephone et l'endpoint si besoin ;
  - genere serveur + client ;
  - active routage, firewall, NAT ;
  - installe le tunnel WireGuard ;
  - tente une redirection UPnP UDP 51820 sur la box si disponible ;
  - ouvre le dossier contenant la config telephone.
#>
[CmdletBinding()]
param(
    [int]$ListenPort = 51820,
    [string]$TunnelName = "wg-phone-server",
    [string]$VpnCidr = "10.66.66.0/24",
    [string]$ServerVpnIp = "10.66.66.1",
    [string]$ClientVpnIp = "10.66.66.2",
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
    $natName = "WireGuardPhoneServerNAT"
    Get-NetNat -Name $natName -ErrorAction SilentlyContinue | Remove-NetNat -Confirm:$false
    New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix $Cidr | Out-Null
    Write-Ok (TInstall "NAT cree pour $Cidr" "NAT created for $Cidr")
}

function Try-UpnpPortForward([int]$Port, [string]$LanIp) {
    if (-not $LanIp) { return $false }
    Write-Step (TInstall "Tentative de redirection automatique du port sur la box via UPnP" "Trying automatic router port forwarding via UPnP")
    try {
        $nat = New-Object -ComObject HNetCfg.NATUPnP
        $mappings = $nat.StaticPortMappingCollection
        if ($null -eq $mappings) {
            Write-Host "UPnP indisponible sur cette box ou desactive." -ForegroundColor Yellow
            return $false
        }
        try { $mappings.Remove($Port, "UDP") } catch {}
        $mappings.Add($Port, "UDP", $Port, $LanIp, $true, "WinWG OneClick Server") | Out-Null
        Write-Ok (TInstall "Redirection UPnP ajoutee : UDP $Port -> $LanIp`:$Port" "UPnP forwarding added: UDP $Port -> $LanIp`:$Port")
        return $true
    } catch {
        Write-Host "Redirection UPnP impossible : $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
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
    if ($remove.ExitCode -ne 0 -and $remove.StdErr -notmatch 'does not exist|n.existe pas|service.*introuvable') {
        Write-Host "Ancien tunnel non supprime, tentative d'installation quand meme : $($remove.StdErr.Trim())" -ForegroundColor Yellow
    }

    $install = Invoke-WireGuardNoThrow -WireGuardExe $WireGuardExe -Arguments @('/installtunnelservice', $ConfigPath)
    if ($install.ExitCode -ne 0) {
        $message = ($install.StdErr + $install.StdOut).Trim()
        if ([string]::IsNullOrWhiteSpace($message)) { $message = "wireguard.exe a retourne le code $($install.ExitCode)" }
        throw $message
    }
    Write-Ok (TInstall "Tunnel installe : $TunnelName" "Tunnel installed: $TunnelName")
}

try {
    Assert-Admin
    $host.UI.RawUI.WindowTitle = "WinWG OneClick Server - One Click"

    $baseDir = Join-Path $env:ProgramData "WireGuardPhoneServer"
    $serverDir = Join-Path $baseDir "server"
    $clientDir = Join-Path $baseDir "clients"
    Ensure-Directory $serverDir
    Ensure-Directory $clientDir

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
        Write-Host "Ce script va configurer ce PC comme serveur VPN WireGuard pour ton telephone."
        $clientNamePrompt = "Nom du telephone/client"
        $endpointPrompt = "IP publique ou DNS a utiliser cote telephone. Laisse la valeur detectee si tu n'as pas de DNS dynamique."
        $dnsPrompt = "DNS a utiliser sur cet appareil. Laisse vide / ne tape rien pour garder le DNS par defaut. Exemples : 1.1.1.1, 8.8.8.8 ou l'IP DNS de ta box comme 192.168.1.1"
        $qrPrompt = "Installer le generateur de QR code integre ? Cela permet d'importer la configuration dans l'app WireGuard mobile en scannant un QR code. La dependance QRCoder sera telechargee depuis NuGet, mais tes cles/configurations ne sont pas envoyees a Internet. Tape oui ou non ; laisser le champ vide n'est pas accepte."
    } else {
        Write-Host "Selected language: English" -ForegroundColor Green
        Write-Host "WinWG OneClick Server - one-click installation" -ForegroundColor Green
        Write-Host "This script will configure this PC as a WireGuard VPN server for your device."
        $clientNamePrompt = "Phone/device name"
        $endpointPrompt = "Public IP or DNS to use on the device side. Keep the detected value if you do not have dynamic DNS."
        $dnsPrompt = "DNS to use on this device. Leave empty / type nothing to keep the default DNS. Examples: 1.1.1.1, 8.8.8.8 or your router DNS such as 192.168.1.1"
        $qrPrompt = "Install the integrated QR code generator? This lets you import the configuration in the WireGuard mobile app by scanning a QR code. The QRCoder dependency will be downloaded from NuGet, but your keys/configurations are not sent to the Internet. Please type yes or no; leaving the field empty is not accepted."
    }

    $defaultEndpoint = Get-PublicEndpoint -Port $ListenPort
    $clientName = Ask-Text "WireGuard" $clientNamePrompt "telephone"
    $endpoint = Ask-Text "WireGuard" $endpointPrompt $defaultEndpoint
    $Dns = Ask-Text "WireGuard" $dnsPrompt $Dns

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

    Write-Step (TInstall "Generation des cles et configurations" "Generating keys and configurations")
    $serverPrivateKey = New-WgPrivateKey $wgExe
    $serverPublicKey = Get-WgPublicKey $wgExe $serverPrivateKey
    $clientPrivateKey = New-WgPrivateKey $wgExe
    $clientPublicKey = Get-WgPublicKey $wgExe $clientPrivateKey
    $psk = New-WgPresharedKey $wgExe

    $safeClientName = ($clientName -replace '[^a-zA-Z0-9_-]', '_')
    $serverConfigPath = Join-Path $serverDir "$TunnelName.conf"
    $clientConfigPath = Join-Path $clientDir "$safeClientName.conf"

    $serverConfig = @"
[Interface]
PrivateKey = $serverPrivateKey
Address = $ServerVpnIp/24
ListenPort = $ListenPort

# $safeClientName
[Peer]
PublicKey = $clientPublicKey
PresharedKey = $psk
AllowedIPs = $ClientVpnIp/32
"@

    $clientConfig = @"
[Interface]
PrivateKey = $clientPrivateKey
Address = $ClientVpnIp/32
DNS = $Dns

[Peer]
PublicKey = $serverPublicKey
PresharedKey = $psk
Endpoint = $endpoint`:$ListenPort
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
"@

    Set-Content -Path $serverConfigPath -Value $serverConfig -Encoding ASCII
    Set-Content -Path $clientConfigPath -Value $clientConfig -Encoding ASCII
    Write-Ok (TInstall "Configuration telephone creee : $clientConfigPath" "Device configuration created: $clientConfigPath")

    if ($enableQrFeature) {
        $generateFirstQrPrompt = TInstall "Generer un QR code pour ce premier appareil ? Tape oui ou non ; laisser le champ vide n'est pas accepte." "Generate a QR code for this first device? Please type yes or no; leaving the field empty is not accepted."
        $generateFirstQr = Ask-YesNoRequired "WinWG QR Code" $generateFirstQrPrompt
        if ($generateFirstQr) {
            $qrScript = Join-Path $PSScriptRoot "Generate-WireGuardClientQr.ps1"
            if (Test-Path $qrScript) {
                Write-Step (TInstall "Generation du QR code du premier appareil" "Generating QR code for the first device")
                $qrOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $qrScript -ClientName $safeClientName -BaseDir $baseDir -Language $Language -Open 2>&1
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

    Enable-IPv4Forwarding
    Ensure-Firewall -Port $ListenPort
    Ensure-Nat -Cidr $VpnCidr
    Install-Tunnel -WireGuardExe $wireguardExe -TunnelName $TunnelName -ConfigPath $serverConfigPath

    $lanIp = Get-PrimaryIPv4
    $upnpOk = Try-UpnpPortForward -Port $ListenPort -LanIp $lanIp

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host (TInstall "INSTALLATION TERMINEE" "INSTALLATION COMPLETE") -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host (TInstall "Tunnel serveur : $TunnelName" "Server tunnel: $TunnelName")
    Write-Host (TInstall "Port WireGuard : UDP $ListenPort" "WireGuard port: UDP $ListenPort")
    Write-Host (TInstall "IP VPN serveur : $ServerVpnIp" "VPN server IP: $ServerVpnIp")
    Write-Host (TInstall "IP VPN telephone : $ClientVpnIp" "Device VPN IP: $ClientVpnIp")
    Write-Host (TInstall "Fichier a importer dans l'app WireGuard du telephone :" "File to import into the WireGuard app:")
    Write-Host "  $clientConfigPath" -ForegroundColor Yellow
    Write-Host ""

    if ($upnpOk) {
        Write-Host (TInstall "La redirection de port automatique UPnP a reussi. Tu peux tester en 4G/5G." "Automatic UPnP port forwarding succeeded. You can test from mobile data.") -ForegroundColor Green
    } else {
        Write-Host (TInstall "Action manuelle probablement necessaire sur ta box :" "Manual action probably required on your router:") -ForegroundColor Yellow
        Write-Host (TInstall "  Rediriger UDP $ListenPort vers l'IP locale du PC : $lanIp" "  Forward UDP $ListenPort to the PC local IP: $lanIp")
        Write-Host (TInstall "Si ta box est en CG-NAT, il faudra demander une IPv4 publique a ton operateur." "If your ISP uses CG-NAT, ask for a public/full-stack IPv4 address.")
    }

    Write-Host ""
    Write-Host (TInstall "Etapes telephone :" "Device steps:")
    Write-Host (TInstall "1. Installe l'app WireGuard." "1. Install the WireGuard app.")
    Write-Host (TInstall "2. Copie/import le fichier .conf ci-dessus." "2. Copy/import the .conf file above.")
    Write-Host (TInstall "3. Coupe le Wi-Fi, passe en 4G/5G, active le tunnel." "3. Disable Wi-Fi, use mobile data, enable the tunnel.")
    Write-Host (TInstall "4. Verifie l'IP sur https://ifconfig.me." "4. Check the IP on https://ifconfig.me.")

    Start-Process explorer.exe $clientDir

    $projectRoot = Split-Path $PSScriptRoot -Parent
    $consoleBat = Join-Path $projectRoot "SERVER-CONSOLE.bat"
    if (Test-Path $consoleBat) {
        Write-Host ""
        Write-Host (TInstall "Ouverture de la console serveur de supervision..." "Opening the server monitoring console...") -ForegroundColor Cyan
        Start-Process -FilePath $consoleBat
    }
} catch {
    Write-Host ""
    Write-Host "ERREUR : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Consulte docs\TROUBLESHOOTING.md ou relance le script en administrateur."
    exit 1
}
