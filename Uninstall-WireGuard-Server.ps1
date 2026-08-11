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
  - optionnellement l'application WireGuard elle-meme.
#>
[CmdletBinding()]
param(
    [string]$TunnelName = "wg-phone-server",
    [int]$ListenPort = 51820,
    [string]$BaseDir = "$env:ProgramData\WireGuardPhoneServer",
    [switch]$Quiet,
    [switch]$RemoveWireGuardApp,
    [switch]$KeepConfigs,
    [switch]$DisableIPv4Router
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
    $suffix = if ($DefaultYes) { "O/n" } else { "o/N" }
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
            default { Write-Host "Reponds par oui ou non." -ForegroundColor Yellow }
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
    Write-Step "Suppression du tunnel/service WireGuard"
    $wireguardExe = Join-Path $env:ProgramFiles "WireGuard\wireguard.exe"
    if (-not (Test-Path $wireguardExe)) {
        Write-Warn "wireguard.exe introuvable. Le service sera quand meme verifie via PowerShell."
    } else {
        $result = Invoke-ExternalNoThrow -FileName $wireguardExe -Arguments @('/uninstalltunnelservice', $TunnelName)
        $msg = ($result.StdErr + $result.StdOut).Trim()
        if ($result.ExitCode -eq 0) {
            Write-Ok "Tunnel WireGuard supprime : $TunnelName"
        } elseif ($msg -match 'does not exist|n.existe pas|service.*introuvable|specified service') {
            Write-Ok "Aucun tunnel WireGuard a supprimer : $TunnelName"
        } else {
            Write-Warn "WireGuard a retourne une erreur : $msg"
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
                Write-Ok "Service supprime : $($_.Name)"
            } catch {
                Write-Warn "Impossible de supprimer le service $($_.Name) : $($_.Exception.Message)"
            }
        }
    }
}

function Remove-FirewallRules([int]$Port) {
    Write-Step "Suppression des regles pare-feu"
    $rules = @(Get-NetFirewallRule -DisplayName "WireGuard Server UDP $Port" -ErrorAction SilentlyContinue)
    $rules += @(Get-NetFirewallRule -DisplayName "WinWG OneClick Server*" -ErrorAction SilentlyContinue)

    # Important Windows PowerShell 5.1 + StrictMode : apres un pipeline,
    # un seul objet redevient un scalaire sans propriete Count.
    # On force donc toujours le resultat en tableau.
    $rules = @($rules | Where-Object { $null -ne $_ } | Sort-Object Name -Unique)

    if ($rules.Length -eq 0) {
        Write-Ok "Aucune regle pare-feu specifique trouvee"
        return
    }
    $rules | Remove-NetFirewallRule
    Write-Ok "$($rules.Length) regle(s) pare-feu supprimee(s)"
}

function Remove-WindowsNat {
    Write-Step "Suppression du NAT Windows"
    $nat = Get-NetNat -Name "WireGuardPhoneServerNAT" -ErrorAction SilentlyContinue
    if ($null -eq $nat) {
        Write-Ok "Aucun NAT WireGuardPhoneServerNAT trouve"
    } else {
        $nat | Remove-NetNat -Confirm:$false
        Write-Ok "NAT WireGuardPhoneServerNAT supprime"
    }
}

function Remove-UpnpMapping([int]$Port) {
    Write-Step "Suppression de la redirection UPnP si presente"
    try {
        $nat = New-Object -ComObject HNetCfg.NATUPnP
        $mappings = $nat.StaticPortMappingCollection
        if ($null -eq $mappings) {
            Write-Ok "UPnP indisponible ou desactive, rien a supprimer"
            return
        }
        try {
            $mappings.Remove($Port, "UDP")
            Write-Ok "Redirection UPnP UDP $Port supprimee"
        } catch {
            Write-Ok "Aucune redirection UPnP UDP $Port trouvee"
        }
    } catch {
        Write-Warn "Impossible de verifier UPnP : $($_.Exception.Message)"
    }
}

function Remove-ConfigDirectory([string]$BaseDir) {
    Write-Step "Suppression des fichiers de configuration"
    if (-not (Test-Path $BaseDir)) {
        Write-Ok "Aucun dossier de configuration trouve : $BaseDir"
        return
    }

    if ($KeepConfigs) {
        Write-Warn "Conservation demandee des configurations : $BaseDir"
        return
    }

    $removeConfigs = Ask-YesNo "Supprimer les fichiers de configuration et cles dans $BaseDir ?" $true
    if (-not $removeConfigs) {
        Write-Warn "Configurations conservees : $BaseDir"
        return
    }

    Remove-Item $BaseDir -Recurse -Force
    Write-Ok "Dossier supprime : $BaseDir"
}

function Disable-IPv4ForwardingIfRequested {
    if (-not $DisableIPv4Router) {
        $disable = Ask-YesNo "Desactiver aussi le routage IPv4 Windows global ? Attention si tu l'utilises pour autre chose." $false
        if (-not $disable) {
            Write-Ok "Routage IPv4 global laisse tel quel"
            return
        }
    }

    Write-Step "Desactivation du routage IPv4 Windows"
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name IPEnableRouter -Value 0
    Get-NetIPInterface -AddressFamily IPv4 | ForEach-Object {
        try { Set-NetIPInterface -InterfaceIndex $_.InterfaceIndex -Forwarding Disabled -ErrorAction Stop } catch {}
    }
    Write-Ok "Routage IPv4 desactive"
}

function Uninstall-WireGuardAppIfRequested {
    if (-not $RemoveWireGuardApp) {
        $removeApp = Ask-YesNo "Desinstaller aussi l'application WireGuard de Windows ?" $false
        if (-not $removeApp) {
            Write-Ok "Application WireGuard conservee"
            return
        }
    }

    Write-Step "Desinstallation de l'application WireGuard"
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        $result = Invoke-ExternalNoThrow -FileName "winget" -Arguments @('uninstall', '--id', 'WireGuard.WireGuard', '-e', '--accept-source-agreements')
        $msg = ($result.StdErr + $result.StdOut).Trim()
        if ($result.ExitCode -eq 0) {
            Write-Ok "WireGuard desinstalle via winget"
            return
        }
        Write-Warn "winget n'a pas reussi : $msg"
    }

    $uninstallKeys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $uninstallKeys) {
        Get-ItemProperty $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like 'WireGuard*' -and $_.UninstallString } |
            ForEach-Object {
                Write-Warn "Desinstalle WireGuard manuellement via Parametres Windows si necessaire. UninstallString: $($_.UninstallString)"
            }
    }
}

function Show-RemainingState([string]$TunnelName, [int]$Port, [string]$BaseDir) {
    Write-Step "Verification finale"
    $services = @(Get-Service -Name "WireGuardTunnel*$TunnelName*" -ErrorAction SilentlyContinue)
    $fw = @(Get-NetFirewallRule -DisplayName "WireGuard Server UDP $Port" -ErrorAction SilentlyContinue)
    $nat = @(Get-NetNat -Name "WireGuardPhoneServerNAT" -ErrorAction SilentlyContinue)

    if ($services.Length -eq 0 -and $fw.Length -eq 0 -and $nat.Length -eq 0 -and -not (Test-Path $BaseDir)) {
        Write-Ok "Nettoyage complet confirme"
    } else {
        if ($services.Length -gt 0) { Write-Warn "Service(s) restant(s): $($services.Name -join ', ')" }
        if ($fw.Length -gt 0) { Write-Warn "Regle(s) pare-feu restante(s): $($fw.DisplayName -join ', ')" }
        if ($nat.Length -gt 0) { Write-Warn "NAT restant: WireGuardPhoneServerNAT" }
        if (Test-Path $BaseDir) { Write-Warn "Dossier encore present: $BaseDir" }
    }
}

try {
    Assert-Admin
    $host.UI.RawUI.WindowTitle = "WinWG OneClick Server - Uninstaller"

    Write-Host "WinWG OneClick Server - desinstallation propre" -ForegroundColor Green
    Write-Host "Ce script va supprimer la configuration serveur WireGuard creee par ce projet."

    if (-not $Quiet) {
        $continue = Ask-YesNo "Continuer la desinstallation ?" $true
        if (-not $continue) { throw "Desinstallation annulee par l'utilisateur." }
    }

    Remove-WireGuardTunnel -TunnelName $TunnelName
    Remove-FirewallRules -Port $ListenPort
    Remove-WindowsNat
    Remove-UpnpMapping -Port $ListenPort
    Remove-ConfigDirectory -BaseDir $BaseDir
    Disable-IPv4ForwardingIfRequested
    Uninstall-WireGuardAppIfRequested
    Show-RemainingState -TunnelName $TunnelName -Port $ListenPort -BaseDir $BaseDir

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "DESINSTALLATION TERMINEE" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "Si tu avais cree une redirection de port manuelle sur ta box, supprime-la aussi : UDP $ListenPort vers ce PC."
} catch {
    Write-Host ""
    Write-Host "ERREUR : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Tu peux relancer ce script en administrateur."
    exit 1
}
