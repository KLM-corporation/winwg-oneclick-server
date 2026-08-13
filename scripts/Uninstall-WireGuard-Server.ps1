<#
.SYNOPSIS
  Desinstalle proprement WinWG OneClick Server.

.DESCRIPTION
  Ce script supprime tout ce que l'installeur one-click a cree :
  - service/tunnel WireGuard wg-phone-server ;
  - regle pare-feu UDP 51820 ;
  - NAT Windows WireGuardPhoneServerNAT ;
  - redirection UPnP UDP 51820 si presente ;
  - fichiers de configuration dans C:\ProgramData\WireGuardPhoneServer ;
  - dependance QR optionnelle QRCoder, QR codes generes et flags de fonctionnalite ;
  - optionnellement l'application WireGuard elle-meme.
#>
[CmdletBinding()]
param(
    [string]$TunnelName = "wg-phone-server",
    [int]$ListenPort = 51820,
    [string]$BaseDir = "$env:ProgramData\WireGuardPhoneServer",
    [switch]$Quiet,
    [switch]$RemoveWireGuardApp,
    [switch]$KeepConfigs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$script:UninstallLanguage = "en"
$languageScript = Join-Path $PSScriptRoot "WinWG-Language.ps1"
if (Test-Path $languageScript) { . $languageScript }

function TUninstall([string]$Fr, [string]$En) {
    if ($script:UninstallLanguage -eq "fr") { return $Fr }
    return $En
}

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Ok([string]$Text) {
    Write-Host "OK - $Text" -ForegroundColor Green
}

function Write-Warn([string]$Text) {
    Write-Host "ATTENTION - $Text" -ForegroundColor Yellow
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Ce script doit etre lance en administrateur. Utilise UNINSTALLER-ONE-CLICK.bat."
    }
}

function Ask-YesNo([string]$Question, [bool]$DefaultYes = $true) {
    if ($Quiet) { return $DefaultYes }
    $suffix = if ($DefaultYes) { (TUninstall "O/n" "Y/n") } else { (TUninstall "o/N" "y/N") }
    while ($true) {
        $answer = Read-Host "$Question [$suffix]"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
        switch ($answer.Trim().ToLowerInvariant()) {
            "o" { return $true }
            "oui" { return $true }
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "non" { return $false }
            "no" { return $false }
            default { Write-Host (TUninstall "Reponds par oui ou non." "Please answer yes or no.") -ForegroundColor Yellow }
        }
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

function Remove-WireGuardTunnel([string]$TunnelName) {
    Write-Step (TUninstall "Suppression du tunnel/service WireGuard" "Removing WireGuard tunnel/service")
    $wireguardExe = Join-Path $env:ProgramFiles "WireGuard\wireguard.exe"
    if (-not (Test-Path $wireguardExe)) {
        Write-Warn (TUninstall "wireguard.exe introuvable. Le service sera quand meme verifie via PowerShell." "wireguard.exe not found. The service will still be checked through PowerShell.")
    } else {
        $result = Invoke-ExternalNoThrow -FileName $wireguardExe -Arguments @('/uninstalltunnelservice', $TunnelName)
        $msg = ($result.StdErr + $result.StdOut).Trim()
        if ($result.ExitCode -eq 0) {
            Write-Ok (TUninstall "Tunnel WireGuard supprime : $TunnelName" "WireGuard tunnel removed: $TunnelName")
        } elseif ($msg -match 'does not exist|n.existe pas|service.*introuvable|specified service') {
            Write-Ok (TUninstall "Aucun tunnel WireGuard a supprimer : $TunnelName" "No WireGuard tunnel to remove: $TunnelName")
        } else {
            Write-Warn (TUninstall "WireGuard a retourne une erreur : $msg" "WireGuard returned an error: $msg")
        }
    }

    $servicePatterns = @(
        "WireGuardTunnel`$$TunnelName",
        "WireGuardTunnel*$TunnelName*"
    )
    foreach ($pattern in $servicePatterns) {
        Get-Service -Name $pattern -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if ($_.Status -ne 'Stopped') { Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue }
                sc.exe delete $_.Name | Out-Null
                Write-Ok (TUninstall "Service supprime : $($_.Name)" "Service removed: $($_.Name)")
            } catch {
                Write-Warn (TUninstall "Impossible de supprimer le service $($_.Name) : $($_.Exception.Message)" "Unable to remove service $($_.Name): $($_.Exception.Message)")
            }
        }
    }
}

function Remove-FirewallRules([int]$Port) {
    Write-Step (TUninstall "Suppression des regles pare-feu" "Removing firewall rules")
    $rules = @(Get-NetFirewallRule -DisplayName "WireGuard Server UDP $Port" -ErrorAction SilentlyContinue)
    $rules += @(Get-NetFirewallRule -DisplayName "WinWG OneClick Server*" -ErrorAction SilentlyContinue)

    # Important Windows PowerShell 5.1 + StrictMode : apres un pipeline,
    # un seul objet redevient un scalaire sans propriete Count.
    # On force donc toujours le resultat en tableau.
    $rules = @($rules | Where-Object { $null -ne $_ } | Sort-Object Name -Unique)

    if ($rules.Length -eq 0) {
        Write-Ok (TUninstall "Aucune regle pare-feu specifique trouvee" "No specific firewall rule found")
        return
    }
    $rules | Remove-NetFirewallRule
    Write-Ok (TUninstall "$($rules.Length) regle(s) pare-feu supprimee(s)" "$($rules.Length) firewall rule(s) removed")
}

function Remove-WindowsNat {
    Write-Step (TUninstall "Suppression du NAT Windows" "Removing Windows NAT")
    $nat = Get-NetNat -Name "WireGuardPhoneServerNAT" -ErrorAction SilentlyContinue
    if ($null -eq $nat) {
        Write-Ok (TUninstall "Aucun NAT WireGuardPhoneServerNAT trouve" "No WireGuardPhoneServerNAT NAT found")
    } else {
        $nat | Remove-NetNat -Confirm:$false
        Write-Ok (TUninstall "NAT WireGuardPhoneServerNAT supprime" "WireGuardPhoneServerNAT NAT removed")
    }
}

function Remove-UpnpMapping([int]$Port) {
    Write-Step (TUninstall "Suppression de la redirection UPnP si presente" "Removing UPnP port mapping if present")
    try {
        $nat = New-Object -ComObject HNetCfg.NATUPnP
        $mappings = $nat.StaticPortMappingCollection
        if ($null -eq $mappings) {
            Write-Ok (TUninstall "UPnP indisponible ou desactive, rien a supprimer" "UPnP unavailable or disabled, nothing to remove")
            return
        }
        try {
            $mappings.Remove($Port, "UDP")
            Write-Ok (TUninstall "Redirection UPnP UDP $Port supprimee" "UDP $Port UPnP mapping removed")
        } catch {
            Write-Ok (TUninstall "Aucune redirection UPnP UDP $Port trouvee" "No UDP $Port UPnP mapping found")
        }
    } catch {
        Write-Warn (TUninstall "Impossible de verifier UPnP : $($_.Exception.Message)" "Unable to check UPnP: $($_.Exception.Message)")
    }
}

function Remove-ConfigDirectory([string]$BaseDir) {
    Write-Step (TUninstall "Suppression des fichiers de configuration" "Removing configuration files")
    if (-not (Test-Path $BaseDir)) {
        Write-Ok (TUninstall "Aucun dossier de configuration trouve : $BaseDir" "No configuration folder found: $BaseDir")
        return
    }

    if ($KeepConfigs) {
        Write-Warn (TUninstall "Conservation demandee des configurations : $BaseDir" "Keeping configurations as requested: $BaseDir")
        return
    }

    $removeConfigs = Ask-YesNo (TUninstall "Supprimer les fichiers de configuration, cles, QR codes et dependances optionnelles dans $BaseDir ?" "Remove configuration files, keys, QR codes and optional dependencies in $BaseDir ?") $true
    if (-not $removeConfigs) {
        Write-Warn (TUninstall "Configurations conservees : $BaseDir" "Configurations kept: $BaseDir")
        return
    }

    Remove-Item $BaseDir -Recurse -Force
    Write-Ok (TUninstall "Dossier supprime : $BaseDir" "Folder removed: $BaseDir")
    Write-Ok (TUninstall "Configurations, cles, QR codes, flags de fonctionnalite et dependance QRCoder supprimes si presents" "Configurations, keys, QR codes, feature flags and QRCoder dependency removed if present")
}

function Uninstall-WireGuardAppIfRequested {
    if (-not $RemoveWireGuardApp) {
        $removeApp = Ask-YesNo (TUninstall "Desinstaller aussi l'application WireGuard de Windows ?" "Also uninstall the WireGuard Windows application ?") $false
        if (-not $removeApp) {
            Write-Ok (TUninstall "Application WireGuard conservee" "WireGuard application kept")
            return
        }
    }

    Write-Step (TUninstall "Desinstallation de l'application WireGuard" "Uninstalling WireGuard application")

    $wireguardExe = Join-Path $env:ProgramFiles "WireGuard\wireguard.exe"
    if (-not (Test-Path $wireguardExe)) {
        Write-Ok (TUninstall "Application WireGuard deja absente ou chemin introuvable" "WireGuard application already absent or path not found")
        return
    }

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        $result = Invoke-ExternalNoThrow -FileName "winget" -Arguments @('uninstall', '--id', 'WireGuard.WireGuard', '-e', '--accept-source-agreements')
        $msg = ($result.StdErr + $result.StdOut).Trim()
        if ($result.ExitCode -eq 0) {
            Write-Ok (TUninstall "WireGuard desinstalle via winget" "WireGuard uninstalled through winget")
            return
        }
        if ($msg -match 'No installed package found|Aucun package installe|aucun package installe|not found|introuvable') {
            Write-Warn (TUninstall "Aucun paquet WireGuard trouve via winget, verification du registre Windows..." "No WireGuard package found through winget, checking Windows registry...")
        } else {
            Write-Warn (TUninstall "winget n'a pas reussi : $msg" "winget failed: $msg")
        }
    }

    # Fallback registre. Sous StrictMode, certains objets de desinstallation n'ont pas DisplayName.
    # On verifie donc l'existence des proprietes avant de les lire.
    $uninstallKeys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $found = $false
    foreach ($key in $uninstallKeys) {
        $items = @(Get-ItemProperty $key -ErrorAction SilentlyContinue)
        foreach ($item in $items) {
            $hasDisplayName = $null -ne $item.PSObject.Properties['DisplayName']
            $hasUninstallString = $null -ne $item.PSObject.Properties['UninstallString']
            if (-not $hasDisplayName -or -not $hasUninstallString) { continue }
            if ($item.DisplayName -like 'WireGuard*' -and -not [string]::IsNullOrWhiteSpace($item.UninstallString)) {
                $found = $true
                Write-Warn (TUninstall "WireGuard est detecte mais n'a pas pu etre desinstalle automatiquement. Desinstalle-le manuellement via Parametres Windows > Applications." "WireGuard was detected but could not be uninstalled automatically. Uninstall it manually through Windows Settings > Apps.")
                Write-Host "UninstallString: $($item.UninstallString)" -ForegroundColor DarkGray
            }
        }
    }

    if (-not $found) {
        Write-Ok (TUninstall "Aucune installation WireGuard restante detectee" "No remaining WireGuard installation detected")
    }
}

function Show-RemainingState([string]$TunnelName, [int]$Port, [string]$BaseDir) {
    Write-Step (TUninstall "Verification finale" "Final verification")
    $services = @(Get-Service -Name "WireGuardTunnel*$TunnelName*" -ErrorAction SilentlyContinue)
    $fw = @(Get-NetFirewallRule -DisplayName "WireGuard Server UDP $Port" -ErrorAction SilentlyContinue)
    $nat = @(Get-NetNat -Name "WireGuardPhoneServerNAT" -ErrorAction SilentlyContinue)

    if ($services.Length -eq 0 -and $fw.Length -eq 0 -and $nat.Length -eq 0 -and -not (Test-Path $BaseDir)) {
        Write-Ok (TUninstall "Nettoyage complet confirme" "Complete cleanup confirmed")
    } else {
        if ($services.Length -gt 0) { Write-Warn (TUninstall "Service(s) restant(s): $($services.Name -join ', ')" "Remaining service(s): $($services.Name -join ', ')") }
        if ($fw.Length -gt 0) { Write-Warn (TUninstall "Regle(s) pare-feu restante(s): $($fw.DisplayName -join ', ')" "Remaining firewall rule(s): $($fw.DisplayName -join ', ')") }
        if ($nat.Length -gt 0) { Write-Warn (TUninstall "NAT restant: WireGuardPhoneServerNAT" "Remaining NAT: WireGuardPhoneServerNAT") }
        if (Test-Path $BaseDir) { Write-Warn (TUninstall "Dossier encore present: $BaseDir" "Folder still present: $BaseDir") }
    }
}

try {
    Assert-Admin
    if (Get-Command Get-WinWGLanguage -ErrorAction SilentlyContinue) { $script:UninstallLanguage = Get-WinWGLanguage -BaseDir $BaseDir }
    $host.UI.RawUI.WindowTitle = "WinWG OneClick Server - Uninstaller"

    Write-Host (TUninstall "WinWG OneClick Server - desinstallation propre" "WinWG OneClick Server - clean uninstall") -ForegroundColor Green
    Write-Host (TUninstall "Ce script va supprimer la configuration serveur WireGuard creee par ce projet." "This script will remove the WireGuard server configuration created by this project.")

    if (-not $Quiet) {
        $continue = Ask-YesNo (TUninstall "Continuer la desinstallation ?" "Continue uninstall?") $true
        if (-not $continue) { throw (TUninstall "Desinstallation annulee par l'utilisateur." "Uninstall cancelled by user.") }
    }

    Remove-WireGuardTunnel -TunnelName $TunnelName
    Remove-FirewallRules -Port $ListenPort
    Remove-WindowsNat
    Remove-UpnpMapping -Port $ListenPort
    Remove-ConfigDirectory -BaseDir $BaseDir
    Uninstall-WireGuardAppIfRequested
    Show-RemainingState -TunnelName $TunnelName -Port $ListenPort -BaseDir $BaseDir

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host (TUninstall "DESINSTALLATION TERMINEE" "UNINSTALL COMPLETE") -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host (TUninstall "Si tu avais cree une redirection de port manuelle sur ta box, supprime-la aussi : UDP $ListenPort vers ce PC." "If you created a manual port-forwarding rule on your router, remove it too: UDP $ListenPort to this PC.")
} catch {
    Write-Host ""
    Write-Host (TUninstall "ERREUR : $($_.Exception.Message)" "ERROR: $($_.Exception.Message)") -ForegroundColor Red
    Write-Host (TUninstall "Tu peux relancer ce script en administrateur." "You can rerun this script as administrator.")
    exit 1
}
