<#
.SYNOPSIS
  Genere un QR code PNG pour une configuration WireGuard telephone/appareil.

.DESCRIPTION
  Genere un QR code localement a partir d'un fichier .conf existant.
  Le contenu du .conf contient une cle privee : il ne doit jamais etre envoye a un service tiers.

  Pour eviter cela, ce script utilise la bibliotheque .NET locale QRCoder.
  Si QRCoder n'est pas encore present, il est telecharge depuis NuGet dans ProgramData.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ClientName,

    [string]$BaseDir = "$env:ProgramData\WireGuardPhoneServer",
    [switch]$Open,
    [ValidateSet("fr","en")]
    [string]$Language = "fr"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function TQr([string]$Fr, [string]$En) { if ($Language -eq "fr") { return $Fr }; return $En }
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Lance PowerShell en administrateur."
    }
}

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Ensure-QRCoder {
    $toolsDir = Join-Path $BaseDir "tools"
    $qrDir = Join-Path $toolsDir "QRCoder"
    $dllCandidates = @(
        (Join-Path $qrDir "lib\netstandard2.0\QRCoder.dll"),
        (Join-Path $qrDir "lib\net6.0\QRCoder.dll"),
        (Join-Path $qrDir "lib\net5.0\QRCoder.dll"),
        (Join-Path $qrDir "lib\net40\QRCoder.dll")
    )

    foreach ($dll in $dllCandidates) {
        if (Test-Path $dll) { return $dll }
    }

    Ensure-Directory $toolsDir
    Ensure-Directory $qrDir

    $nupkg = Join-Path $toolsDir "QRCoder.nupkg"
    $zip = Join-Path $toolsDir "QRCoder.zip"
    $url = "https://www.nuget.org/api/v2/package/QRCoder"

    Write-Host (TQr "QRCoder introuvable. Telechargement local depuis NuGet..." "QRCoder not found. Downloading locally from NuGet...") -ForegroundColor Yellow
    Write-Host (TQr "Le fichier WireGuard .conf n'est pas envoye a NuGet ; seule la bibliotheque QR est telechargee." "The WireGuard .conf file is not sent to NuGet; only the QR library is downloaded.") -ForegroundColor DarkGray

    Invoke-WebRequest -Uri $url -OutFile $nupkg -UseBasicParsing
    Copy-Item $nupkg $zip -Force
    Expand-Archive -Path $zip -DestinationPath $qrDir -Force

    foreach ($dll in $dllCandidates) {
        if (Test-Path $dll) { return $dll }
    }

    throw "Impossible de trouver QRCoder.dll apres telechargement."
}

Assert-Admin

$clientConfigPath = Join-Path $BaseDir "clients\$ClientName.conf"
if (-not (Test-Path $clientConfigPath)) {
    throw "Configuration appareil introuvable : $clientConfigPath"
}

$confText = Get-Content $clientConfigPath -Raw
if ([string]::IsNullOrWhiteSpace($confText)) {
    throw "Configuration vide : $clientConfigPath"
}

$qrcoderDll = Ensure-QRCoder
Add-Type -Path $qrcoderDll

$qrDir = Join-Path $BaseDir "qrcodes"
Ensure-Directory $qrDir
$qrPath = Join-Path $qrDir "$ClientName.png"

$generator = [QRCoder.QRCodeGenerator]::new()
$data = $generator.CreateQrCode($confText, [QRCoder.QRCodeGenerator+ECCLevel]::Q)
$pngQr = [QRCoder.PngByteQRCode]::new($data)
$bytes = $pngQr.GetGraphic(20)
[System.IO.File]::WriteAllBytes($qrPath, $bytes)

Write-Host ((TQr "OK - QR code genere" "OK - QR code generated") + " : $qrPath") -ForegroundColor Green
Write-Host (TQr "Scanne ce QR code avec l'application WireGuard sur Android/iOS." "Scan this QR code with the WireGuard app on Android/iOS.") -ForegroundColor Cyan
Write-Host (TQr "Attention : ce QR contient la cle privee de l'appareil. Ne le partage pas publiquement." "Warning: this QR contains the device private key. Do not share it publicly.") -ForegroundColor Yellow

if ($Open) {
    Start-Process $qrPath
}

return $qrPath
