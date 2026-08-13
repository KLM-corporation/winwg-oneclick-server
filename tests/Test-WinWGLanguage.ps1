<#
.SYNOPSIS
  Unit tests for WinWG FR/EN console translations.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$languageScript = Join-Path $repoRoot 'scripts\WinWG-Language.ps1'
if (-not (Test-Path $languageScript)) {
    throw "Language helper not found: $languageScript"
}

. $languageScript

$requiredKeys = @(
    'ConsoleTitle',
    'ConsoleSubtitle',
    'MenuNoAutoRefresh',
    'VerboseMode',
    'AdvancedMode',
    'Installation',
    'Service',
    'Tunnel',
    'UdpPort',
    'LocalIp',
    'ServerConfig',
    'Firewall',
    'Nat',
    'UdpEndpoint',
    'PhoneConfigs',
    'Actions',
    'QuickHelp',
    'HelpPeerConnected',
    'HelpSpeedRefresh',
    'StartVpn',
    'StopVpn',
    'RestartVpn',
    'AddDevice',
    'RemoveDevice',
    'GenerateQr',
    'Refresh',
    'ToggleVerbose',
    'AdvancedTools',
    'Language',
    'Quit',
    'Choice',
    'LanguageChanged'
)

$failures = New-Object System.Collections.Generic.List[string]

foreach ($key in $requiredKeys) {
    foreach ($lang in @('fr', 'en')) {
        $value = Get-WinWGText -Language $lang -Key $key
        if ([string]::IsNullOrWhiteSpace($value)) {
            $failures.Add("$lang/$key is empty")
            continue
        }
        if ($value -eq $key) {
            $failures.Add("$lang/$key is missing and fell back to key name")
        }
    }
}

# These keys must be genuinely translated and should not be identical between FR and EN.
$mustDiffer = @(
    'ConsoleTitle',
    'ConsoleSubtitle',
    'MenuNoAutoRefresh',
    'QuickHelp',
    'HelpPeerConnected',
    'HelpSpeedRefresh',
    'StartVpn',
    'StopVpn',
    'RestartVpn',
    'AddDevice',
    'RemoveDevice',
    'GenerateQr',
    'Refresh',
    'ToggleVerbose',
    'AdvancedTools',
    'Quit',
    'Choice',
    'LanguageChanged'
)

foreach ($key in $mustDiffer) {
    $fr = Get-WinWGText -Language 'fr' -Key $key
    $en = Get-WinWGText -Language 'en' -Key $key
    if ($fr -eq $en) {
        $failures.Add("$key has identical FR/EN text: '$en'")
    }
}

# Common French words that should not appear in English-only user-facing strings.
# Keep this list conservative to avoid false positives on bilingual labels.
$frenchPatterns = @(
    '\bAide rapide\b',
    '\btelephone\b',
    '\bconnecte\b',
    '\bapparait\b',
    '\brafraichissements\b',
    '\bmesurer\b',
    '\bActiver / demarrer\b',
    '\bDesactiver / arreter\b',
    '\bRedemarrer\b',
    '\bAjouter un nouvel appareil\b',
    '\bRetirer / supprimer\b',
    '\bQuitter\b'
)

foreach ($key in $requiredKeys) {
    $en = Get-WinWGText -Language 'en' -Key $key
    foreach ($pattern in $frenchPatterns) {
        if ($en -match $pattern) {
            $failures.Add("English translation for $key appears to contain French text: '$en'")
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    throw "Translation tests failed: $($failures.Count) issue(s)."
}

Write-Host "WinWG language tests passed for $($requiredKeys.Count) keys."
