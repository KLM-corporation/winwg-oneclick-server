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
    $defaultText = if ($DefaultYes) { "oui" } else { "non" }
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
        $value = [Microsoft.VisualBasic.Interaction]::InputBox("$Prompt`n`nReponds par oui ou non.", $Title, $defaultText)
        if ([string]::IsNullOrWhiteSpace($value)) { return $DefaultYes }
        $v = $value.Trim().ToLowerInvariant()
        return ($v -in @('o','oui','y','yes','1','true'))
    } catch {
        $suffix = if ($DefaultYes) { "O/n" } else { "o/N" }
        $value = Read-Host "$Prompt [$suffix]"
        if ([string]::IsNullOrWhiteSpace($value)) { return $DefaultYes }
        $v = $value.Trim().ToLowerInvariant()
        return ($v -in @('o','oui','y','yes','1','true'))
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
        Write-Ok "WireGuard est deja installe"
        return [pscustomobject]@{ WgExe = $wgExe; WireGuardExe = $wireguardExe }
    }

    Write-Step "Installation de WireGuard"
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Start-Process "https://www.wireguard.com/install/"
        throw "winget est introuvable. Installe WireGuard manuellement, puis relance l'installeur."
    }

    & winget install --id WireGuard.WireGuard -e --accept-source-agreements --accept-package-agreements | Out-Host

    if (-not ((Test-Path $wgExe) -and (Test-Path $wireguardExe))) {
        throw "WireGuard n'a pas ete trouve apres installation. Redemarre PowerShell ou installe WireGuard manuellement."
    }
    Write-Ok "WireGuard installe"
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
    Write-Step "Activation du routage IPv4 Windows"
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name IPEnableRouter -Value 1
    Get-NetIPInterface -AddressFamily IPv4 | ForEach-Object {
        try { Set-NetIPInterface -InterfaceIndex $_.InterfaceIndex -Forwarding Enabled -ErrorAction Stop } catch {}
    }
    Write-Ok "Routage IPv4 active"
}

function Ensure-Firewall([int]$Port) {
    Write-Step "Configuration du pare-feu Windows"
    $fwName = "WireGuard Server UDP $Port"
    Get-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $fwName -Direction Inbound -Action Allow -Protocol UDP -LocalPort $Port | Out-Null
    Write-Ok "Port UDP $Port autorise dans le pare-feu"
}

function Ensure-Nat([string]$Cidr) {
    Write-Step "Configuration du NAT Windows"
    $natName = "WireGuardPhoneServerNAT"
    Get-NetNat -Name $natName -ErrorAction SilentlyContinue | Remove-NetNat -Confirm:$false
    New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix $Cidr | Out-Null
    Write-Ok "NAT cree pour $Cidr"
}

function Try-UpnpPortForward([int]$Port, [string]$LanIp) {
    if (-not $LanIp) { return $false }
    Write-Step "Tentative de redirection automatique du port sur la box via UPnP"
    try {
        $nat = New-Object -ComObject HNetCfg.NATUPnP
        $mappings = $nat.StaticPortMappingCollection
        if ($null -eq $mappings) {
            Write-Host "UPnP indisponible sur cette box ou desactive." -ForegroundColor Yellow
            return $false
        }
        try { $mappings.Remove($Port, "UDP") } catch {}
        $mappings.Add($Port, "UDP", $Port, $LanIp, $true, "WinWG OneClick Server") | Out-Null
        Write-Ok "Redirection UPnP ajoutee : UDP $Port -> $LanIp`:$Port"
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
            Write-Ok "Dependance QR deja presente : QRCoder"
            return $dll
        }
    }

    Ensure-Directory $toolsDir
    Ensure-Directory $qrDir

    $nupkg = Join-Path $toolsDir "QRCoder.nupkg"
    $zip = Join-Path $toolsDir "QRCoder.zip"
    $url = "https://www.nuget.org/api/v2/package/QRCoder"

    Write-Step "Installation de la dependance optionnelle QR code"
    Write-Host "Telechargement de QRCoder depuis NuGet. Les configurations WireGuard ne sont pas envoyees a Internet." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $url -OutFile $nupkg -UseBasicParsing
    Copy-Item $nupkg $zip -Force
    Expand-Archive -Path $zip -DestinationPath $qrDir -Force

    foreach ($dll in $dllCandidates) {
        if (Test-Path $dll) {
            Write-Ok "Dependance QR installee : QRCoder"
            return $dll
        }
    }

    throw "Impossible d'installer la dependance QR QRCoder."
}

function Install-Tunnel([string]$WireGuardExe, [string]$TunnelName, [string]$ConfigPath) {
    Write-Step "Installation/redemarrage du tunnel WireGuard"

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
    Write-Ok "Tunnel installe : $TunnelName"
}

try {
    Assert-Admin
    $host.UI.RawUI.WindowTitle = "WinWG OneClick Server - One Click"

    Write-Host "WinWG OneClick Server - installation one click" -ForegroundColor Green
    Write-Host "Ce script va configurer ce PC comme serveur VPN WireGuard pour ton telephone."

    $defaultEndpoint = Get-PublicEndpoint -Port $ListenPort
    $clientName = Ask-Text "WireGuard" "Nom du telephone/client" "telephone"
    $endpoint = Ask-Text "WireGuard" "IP publique ou DNS a utiliser cote telephone. Laisse la valeur detectee si tu n'as pas de DNS dynamique." $defaultEndpoint
    $Dns = Ask-Text "WireGuard" "DNS a utiliser sur cet appareil. Exemples : 1.1.1.1, 8.8.8.8 ou l'IP DNS de ta box comme 192.168.1.1" $Dns

    $tools = @(Ensure-WireGuard)[-1]
    if (-not $tools -or -not $tools.PSObject.Properties["WgExe"] -or -not $tools.PSObject.Properties["WireGuardExe"]) { throw "Impossible de recuperer les chemins WireGuard apres installation." }
    $wgExe = $tools.WgExe
    $wireguardExe = $tools.WireGuardExe

    $baseDir = Join-Path $env:ProgramData "WireGuardPhoneServer"
    $serverDir = Join-Path $baseDir "server"
    $clientDir = Join-Path $baseDir "clients"
    Ensure-Directory $serverDir
    Ensure-Directory $clientDir

    $enableQrFeature = Ask-YesNo "WinWG QR Code" "Installer le generateur de QR code integre ? Cela permet d'importer la configuration dans l'app WireGuard mobile en scannant un QR code. La dependance QRCoder sera telechargee depuis NuGet, mais tes cles/configurations ne sont pas envoyees a Internet." $true
    if ($enableQrFeature) {
        try {
            Install-QrDependency -BaseDir $baseDir | Out-Null
            Set-QrFeaturePreference -BaseDir $baseDir -Enabled $true
        } catch {
            Write-Host "Installation QR impossible : $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "La fonctionnalite QR sera desactivee. Tu pourras toujours importer le fichier .conf manuellement." -ForegroundColor Yellow
            Set-QrFeaturePreference -BaseDir $baseDir -Enabled $false
        }
    } else {
        Set-QrFeaturePreference -BaseDir $baseDir -Enabled $false
        Write-Host "Fonctionnalite QR desactivee par choix utilisateur." -ForegroundColor Yellow
    }

    Write-Step "Generation des cles et configurations"
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
    Write-Ok "Configuration telephone creee : $clientConfigPath"

    Enable-IPv4Forwarding
    Ensure-Firewall -Port $ListenPort
    Ensure-Nat -Cidr $VpnCidr
    Install-Tunnel -WireGuardExe $wireguardExe -TunnelName $TunnelName -ConfigPath $serverConfigPath

    $lanIp = Get-PrimaryIPv4
    $upnpOk = Try-UpnpPortForward -Port $ListenPort -LanIp $lanIp

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "INSTALLATION TERMINEE" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "Tunnel serveur : $TunnelName"
    Write-Host "Port WireGuard : UDP $ListenPort"
    Write-Host "IP VPN serveur : $ServerVpnIp"
    Write-Host "IP VPN telephone : $ClientVpnIp"
    Write-Host "Fichier a importer dans l'app WireGuard du telephone :"
    Write-Host "  $clientConfigPath" -ForegroundColor Yellow
    Write-Host ""

    if ($upnpOk) {
        Write-Host "La redirection de port automatique UPnP a reussi. Tu peux tester en 4G/5G." -ForegroundColor Green
    } else {
        Write-Host "Action manuelle probablement necessaire sur ta box :" -ForegroundColor Yellow
        Write-Host "  Rediriger UDP $ListenPort vers l'IP locale du PC : $lanIp"
        Write-Host "Si ta box est en CG-NAT, il faudra demander une IPv4 publique a ton operateur."
    }

    Write-Host ""
    Write-Host "Etapes telephone :"
    Write-Host "1. Installe l'app WireGuard."
    Write-Host "2. Copie/import le fichier .conf ci-dessus."
    Write-Host "3. Coupe le Wi-Fi, passe en 4G/5G, active le tunnel."
    Write-Host "4. Verifie l'IP sur https://ifconfig.me."

    Start-Process explorer.exe $clientDir

    $consoleBat = Join-Path $PSScriptRoot "SERVER-CONSOLE.bat"
    if (Test-Path $consoleBat) {
        Write-Host ""
        Write-Host "Ouverture de la console serveur de supervision..." -ForegroundColor Cyan
        Start-Process -FilePath $consoleBat
    }
} catch {
    Write-Host ""
    Write-Host "ERREUR : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Consulte docs\TROUBLESHOOTING.md ou relance le script en administrateur."
    exit 1
}
