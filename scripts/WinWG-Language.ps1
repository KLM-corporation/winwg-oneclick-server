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
            Enabled = 'active'
            Disabled = 'desactive'
            Present = 'presente'
            Missing = 'manquant'
            NotInstalledDisabled = 'introuvable / desactive'
            AbsentUninstalled = 'absente / desinstallee'
            FirewallPresent = 'regle presente'
            FirewallMissing = 'regle manquante'
            UdpPresent = 'present'
            UdpNotVisible = 'non visible / normal selon driver'
            FileCount = 'fichier(s)'
            PhonesPeers = 'Telephones / peers'
            NoPeerDetected = 'Aucun telephone/peer detecte dans wg show.'
            Online = 'connecte'
            Offline = 'hors ligne'
            Never = 'jamais'
            VpnIp = 'IP VPN'
            Handshake = 'Handshake'
            Transfer = 'Transfert'
            Speed = 'Vitesse'
            PublicKey = 'Public key'
            SpeedNextRefresh = 'calcul au prochain refresh'
            DelayTooShort = 'delai trop court'
            RawWireGuardDetails = 'Details WireGuard bruts'
            UnknownDevice = 'appareil inconnu'
            FolderMissing = 'dossier introuvable'
            NoActiveTunnel = "WireGuard n'est pas actif, aucun handshake a afficher."
            StatusRefreshed = 'Statut rafraichi.'
            QrDisabled = "Option QR desactivee. Elle n'apparait pas dans le menu car la dependance QR n'a pas ete installee/activee."
            InvalidChoiceMain = 'Choix invalide. Utilise 1/2/3/4/5/6, A/D/N/R/G, S, V, M, L ou Q.'
            AdvancedWarningTitle = 'WinWG OneClick Server - Mode avance'
            Warning = 'ATTENTION'
            AdvancedWarningIntro1 = 'Le mode avance est destine aux personnes qui connaissent deja WireGuard.'
            AdvancedWarningIntro2 = 'Il peut donner acces a des actions et fichiers sensibles.'
            PossibleRisks = 'Risques possibles :'
            RiskBreakConfig = '- casser la configuration serveur ;'
            RiskExposeKey = '- exposer une cle privee si tu partages une capture ou un fichier ;'
            RiskCutAccess = '- couper l''acces VPN a tes appareils ;'
            RiskUnreachable = '- rendre le serveur inaccessible depuis l''exterieur.'
            NeverShareSecrets = 'Ne partage jamais les fichiers .conf, les QR codes, les cles privees ou les logs non relus.'
            AdvancedEnablePrompt = 'Pour activer, tape exactement JE COMPRENDS'
            AdvancedEnabled = 'Mode avance active. Sois prudent.'
            AdvancedNotEnabled = 'Mode avance non active.'
            AdvancedToolsTitle = 'WinWG OneClick Server - Outils avances'
            AdvancedToolsActive = 'Mode avance actif - attention aux cles et fichiers .conf'
            AdvRawWgShow = 'Afficher wg show brut'
            AdvOpenServerFolder = 'Ouvrir le dossier serveur'
            AdvOpenClientsFolder = 'Ouvrir le dossier clients'
            AdvOpenQrFolder = 'Ouvrir le dossier QR codes'
            AdvExportDiagnostic = 'Exporter un diagnostic redige'
            AdvEditConfig = 'Modifier configuration avancee (port, DNS, AllowedIPs)'
            AdvOpenServerConf = 'Ouvrir wg-phone-server.conf dans Notepad (contient la cle privee)'
            AdvDisable = 'Desactiver le mode avance'
            Back = 'Retour'
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
            Enabled = 'enabled'
            Disabled = 'disabled'
            Present = 'present'
            Missing = 'missing'
            NotInstalledDisabled = 'not installed / disabled'
            AbsentUninstalled = 'absent / uninstalled'
            FirewallPresent = 'rule present'
            FirewallMissing = 'rule missing'
            UdpPresent = 'present'
            UdpNotVisible = 'not visible / normal depending on driver'
            FileCount = 'file(s)'
            PhonesPeers = 'Phones / peers'
            NoPeerDetected = 'No phone/peer detected in wg show.'
            Online = 'online'
            Offline = 'offline'
            Never = 'never'
            VpnIp = 'VPN IP'
            Handshake = 'Handshake'
            Transfer = 'Transfer'
            Speed = 'Speed'
            PublicKey = 'Public key'
            SpeedNextRefresh = 'calculated on next refresh'
            DelayTooShort = 'delay too short'
            RawWireGuardDetails = 'Raw WireGuard details'
            UnknownDevice = 'unknown device'
            FolderMissing = 'folder not found'
            NoActiveTunnel = 'WireGuard is not active, no handshake to display.'
            StatusRefreshed = 'Status refreshed.'
            QrDisabled = 'QR option disabled. It is hidden from the menu because the QR dependency was not installed/enabled.'
            InvalidChoiceMain = 'Invalid choice. Use 1/2/3/4/5/6, A/D/N/R/G, S, V, M, L or Q.'
            AdvancedWarningTitle = 'WinWG OneClick Server - Advanced mode'
            Warning = 'WARNING'
            AdvancedWarningIntro1 = 'Advanced mode is intended for users who already understand WireGuard.'
            AdvancedWarningIntro2 = 'It can expose sensitive actions and files.'
            PossibleRisks = 'Possible risks:'
            RiskBreakConfig = '- break the server configuration;'
            RiskExposeKey = '- expose a private key if you share a screenshot or file;'
            RiskCutAccess = '- cut VPN access for your devices;'
            RiskUnreachable = '- make the server unreachable from outside.'
            NeverShareSecrets = 'Never share .conf files, QR codes, private keys, or logs you have not reviewed.'
            AdvancedEnablePrompt = 'To enable, type exactly JE COMPRENDS'
            AdvancedEnabled = 'Advanced mode enabled. Be careful.'
            AdvancedNotEnabled = 'Advanced mode not enabled.'
            AdvancedToolsTitle = 'WinWG OneClick Server - Advanced tools'
            AdvancedToolsActive = 'Advanced mode enabled - be careful with keys and .conf files'
            AdvRawWgShow = 'Show raw wg show output'
            AdvOpenServerFolder = 'Open server folder'
            AdvOpenClientsFolder = 'Open clients folder'
            AdvOpenQrFolder = 'Open QR codes folder'
            AdvExportDiagnostic = 'Export redacted diagnostic'
            AdvEditConfig = 'Edit advanced configuration (port, DNS, AllowedIPs)'
            AdvOpenServerConf = 'Open wg-phone-server.conf in Notepad (contains private key)'
            AdvDisable = 'Disable advanced mode'
            Back = 'Back'
        }
    }
    if (-not $texts.ContainsKey($Language)) { $Language = 'en' }
    if ($texts[$Language].ContainsKey($Key)) { return $texts[$Language][$Key] }
    return $Key
}
