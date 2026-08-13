<#
.SYNOPSIS
  Language helpers for WinWG OneClick Server.
#>

function Get-WinWGDefaultLanguage {
    try {
        $culture = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName.ToLowerInvariant()
        if ($culture -eq 'fr') { return 'fr' }
    } catch {}
    return 'en'
}

function Get-WinWGLanguagePath([string]$BaseDir) {
    return (Join-Path $BaseDir 'settings\language.txt')
}

function Get-WinWGLanguage([string]$BaseDir) {
    $path = Get-WinWGLanguagePath -BaseDir $BaseDir
    if (Test-Path $path) {
        $value = (Get-Content $path -Raw -ErrorAction SilentlyContinue).Trim().ToLowerInvariant()
        if ($value -in @('fr','en')) { return $value }
    }
    return Get-WinWGDefaultLanguage
}

function Set-WinWGLanguage([string]$BaseDir, [string]$Language) {
    $Language = $Language.Trim().ToLowerInvariant()
    if ($Language -notin @('fr','en')) { throw "Unsupported language: $Language" }
    $settingsDir = Join-Path $BaseDir 'settings'
    if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null }
    Set-Content -Path (Get-WinWGLanguagePath -BaseDir $BaseDir) -Value $Language -Encoding ASCII
    return $Language
}

function Select-WinWGLanguage([string]$BaseDir) {
    $default = Get-WinWGLanguage -BaseDir $BaseDir
    Write-Host ""
    Write-Host "Language / Langue" -ForegroundColor Cyan
    Write-Host "-----------------" -ForegroundColor DarkGray
    Write-Host "fr = Francais"
    Write-Host "en = English"
    Write-Host ""
    $choice = (Read-Host "Choose language / Choisir la langue [$default]").Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = $default }
    if ($choice -notin @('fr','en')) {
        Write-Host "Invalid language, using default: $default" -ForegroundColor Yellow
        $choice = $default
    }
    return (Set-WinWGLanguage -BaseDir $BaseDir -Language $choice)
}

function Get-WinWGText([string]$Language, [string]$Key) {
    $texts = @{
        fr = @{
            ConsoleTitle = 'WinWG OneClick Server - Console serveur unifiee'
            ConsoleSubtitle = 'Surveillance + controle du service VPN dans une seule console.'
            MenuNoAutoRefresh = 'Menu interactif: pas de rafraichissement automatique.'
            VerboseMode = 'Mode ultra verbeux'
            AdvancedMode = 'Mode avance'
            Installation = 'Installation'
            Service = 'Service'
            Tunnel = 'Tunnel'
            UdpPort = 'Port UDP'
            LocalIp = 'IP locale PC'
            ServerConfig = 'Config serveur'
            Firewall = 'Pare-feu'
            Nat = 'NAT Windows'
            UdpEndpoint = 'Endpoint UDP local'
            PhoneConfigs = 'Configs telephone'
            Actions = 'Actions'
            QuickHelp = 'Aide rapide'
            HelpPeerConnected = "Si le telephone est connecte, il apparait dans 'Telephones / peers' avec un handshake recent."
            HelpSpeedRefresh = 'La vitesse RX/TX est calculee entre deux rafraichissements du statut. Utilise S pour mesurer.'
            StartVpn = 'Activer / demarrer le serveur VPN'
            StopVpn = 'Desactiver / arreter le serveur VPN'
            RestartVpn = 'Redemarrer le serveur VPN'
            AddDevice = 'Ajouter un nouvel appareil'
            RemoveDevice = 'Retirer / supprimer un appareil'
            GenerateQr = 'Generer un QR code pour un appareil'
            Refresh = 'Rafraichir le statut'
            ToggleVerbose = 'Activer/desactiver le mode ultra verbeux'
            AdvancedTools = 'Mode avance / outils experts'
            Language = 'Changer la langue / Change language'
            Quit = 'Quitter'
            Choice = 'Choix'
            LanguageChanged = 'Langue modifiee'
        }
        en = @{
            ConsoleTitle = 'WinWG OneClick Server - Unified server console'
            ConsoleSubtitle = 'Monitoring + VPN service control in one console.'
            MenuNoAutoRefresh = 'Interactive menu: no automatic refresh.'
            VerboseMode = 'Ultra verbose mode'
            AdvancedMode = 'Advanced mode'
            Installation = 'Installation'
            Service = 'Service'
            Tunnel = 'Tunnel'
            UdpPort = 'UDP port'
            LocalIp = 'PC local IP'
            ServerConfig = 'Server config'
            Firewall = 'Firewall'
            Nat = 'Windows NAT'
            UdpEndpoint = 'Local UDP endpoint'
            PhoneConfigs = 'Device configs'
            Actions = 'Actions'
            QuickHelp = 'Quick help'
            HelpPeerConnected = "If the device is connected, it appears in 'Phones / peers' with a recent handshake."
            HelpSpeedRefresh = 'RX/TX speed is calculated between two status refreshes. Press S to measure.'
            StartVpn = 'Enable / start VPN server'
            StopVpn = 'Disable / stop VPN server'
            RestartVpn = 'Restart VPN server'
            AddDevice = 'Add a new device'
            RemoveDevice = 'Remove a device'
            GenerateQr = 'Generate a QR code for a device'
            Refresh = 'Refresh status'
            ToggleVerbose = 'Enable/disable ultra verbose mode'
            AdvancedTools = 'Advanced mode / expert tools'
            Language = 'Change language / Changer la langue'
            Quit = 'Quit'
            Choice = 'Choice'
            LanguageChanged = 'Language changed'
        }
    }
    if (-not $texts.ContainsKey($Language)) { $Language = 'en' }
    if ($texts[$Language].ContainsKey($Key)) { return $texts[$Language][$Key] }
    return $Key
}
