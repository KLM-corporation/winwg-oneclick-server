<#
.SYNOPSIS
  Interface graphique WPF pour WinWG OneClick Server.

.DESCRIPTION
  Centre de controle graphique simple, sans dependance externe : statut, actions
  serveur, appareils, QR, diagnostic rapide et endpoint IPv4/IPv6.
#>
[CmdletBinding()]
param(
    [string]$TunnelName = "winwg-server",
    [int]$ListenPort = 51820,
    [string]$BaseDir = "$env:ProgramData\WinWGOneClickServer"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName Microsoft.VisualBasic

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        [System.Windows.MessageBox]::Show("Lance WINWG-GUI.bat en administrateur.", "WinWG OneClick Server", "OK", "Error") | Out-Null
        exit 1
    }
}

function Get-WireGuardExe {
    $wireguardExe = Join-Path $env:ProgramFiles "WireGuard\wireguard.exe"
    if (Test-Path $wireguardExe) { return $wireguardExe }
    return $null
}

function Get-ServerConfigPath { return (Join-Path (Join-Path $BaseDir "server") "$TunnelName.conf") }
function Get-DeviceDir { return (Join-Path $BaseDir "devices") }
function Get-QrDir { return (Join-Path $BaseDir "qrcodes") }

function Get-ServiceName { return "WireGuardTunnel`$$TunnelName" }
function Get-ServiceState {
    return Get-Service -Name (Get-ServiceName) -ErrorAction SilentlyContinue
}

function Get-PrimaryIPv4 {
    try {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop | Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
        if ($route) {
            $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction Stop | Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
            if ($ip) { return $ip.IPAddress }
        }
    } catch {}
    return "inconnue"
}

function Normalize-EndpointBase([string]$Endpoint) {
    if ([string]::IsNullOrWhiteSpace($Endpoint)) { return $Endpoint }
    $value = $Endpoint.Trim()
    if ($value -match '^\[(.+)\]:(\d+)$') { return "[$($Matches[1])]" }
    if ($value -match '^\[(.+)\]$') { return $value }
    if ($value -match '^(.+):(\d+)$' -and $value -notmatch '^[0-9a-fA-F:]+$') { return $Matches[1] }
    if ($value -match '^[0-9a-fA-F:]+$' -and $value -match ':') { return "[$value]" }
    return $value
}

function Get-ConfiguredDeviceEndpoint {
    $deviceDir = Get-DeviceDir
    if (-not (Test-Path $deviceDir)) { return $null }
    $firstDevice = Get-ChildItem $deviceDir -Filter "*.conf" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $firstDevice) { return $null }
    $content = Get-Content $firstDevice.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match '(?m)^Endpoint\s*=\s*(.+)$') { return (Normalize-EndpointBase $Matches[1]) }
    return $null
}

function Get-PortForwardStatus {
    $path = Join-Path $BaseDir "settings\port-forwarding.json"
    if (-not (Test-Path $path)) { return $null }
    try { return (Get-Content $path -Raw | ConvertFrom-Json) } catch { return $null }
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
            $onDefaultRoute = @($addresses | Where-Object { $_.InterfaceIndex -eq $defaultRoute.InterfaceIndex })
            $stablePreferred = $onDefaultRoute | Where-Object { $_.AddressState -eq 'Preferred' -and [string]$_.SuffixOrigin -ne 'Random' } | Select-Object -First 1
            if ($stablePreferred) { return $stablePreferred.IPAddress }
            $anyStable = $onDefaultRoute | Where-Object { [string]$_.SuffixOrigin -ne 'Random' } | Select-Object -First 1
            if ($anyStable) { return $anyStable.IPAddress }
            $preferred = $onDefaultRoute | Select-Object -First 1
            if ($preferred) { return $preferred.IPAddress }
        }

        $fallbackStable = $addresses | Where-Object { $_.AddressState -eq 'Preferred' -and [string]$_.SuffixOrigin -ne 'Random' } | Select-Object -First 1
        if ($fallbackStable) { return $fallbackStable.IPAddress }
        $fallback = $addresses | Select-Object -First 1
        if ($fallback) { return $fallback.IPAddress }
    } catch {}
    return $null
}

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Save-PortForwardStatus([bool]$Succeeded, [string]$Method, [string]$Message) {
    $settingsDir = Join-Path $BaseDir "settings"
    Ensure-Directory $settingsDir
    $path = Join-Path $settingsDir "port-forwarding.json"
    $lanIp = Get-PrimaryIPv4
    $status = [ordered]@{
        checkedAt = (Get-Date).ToUniversalTime().ToString('o')
        port = $ListenPort
        protocol = 'UDP'
        lanIp = $lanIp
        succeeded = $Succeeded
        method = $Method
        message = $Message
        manualRule = "UDP $ListenPort -> $lanIp`:$ListenPort"
    }
    ($status | ConvertTo-Json -Depth 4) | Set-Content -Path $path -Encoding UTF8
}

function Update-AllDeviceEndpoints([string]$EndpointBase) {
    $deviceDir = Get-DeviceDir
    if (-not (Test-Path $deviceDir)) { throw "Dossier devices introuvable." }
    $endpointBase = Normalize-EndpointBase $EndpointBase
    $endpointLine = "Endpoint = $endpointBase`:$ListenPort"
    $updated = 0
    foreach ($conf in Get-ChildItem $deviceDir -Filter "*.conf" -ErrorAction SilentlyContinue) {
        $content = Get-Content $conf.FullName -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($content)) { continue }
        $newContent = [regex]::Replace($content, '(?m)^Endpoint\s*=\s*.+$', $endpointLine, 1)
        if ($newContent -ne $content) {
            Set-Content -Path $conf.FullName -Value $newContent -Encoding ASCII
            $updated++
        }
    }
    return [pscustomobject]@{ Updated = $updated; EndpointLine = $endpointLine }
}

function Invoke-External([string]$FileName, [string[]]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $psi.Arguments = (($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return [pscustomobject]@{ ExitCode=$p.ExitCode; StdOut=$stdout; StdErr=$stderr }
}

function Start-WinWGTunnel {
    $svc = Get-ServiceState
    if ($svc) {
        Start-Service -Name $svc.Name -ErrorAction Stop
        return "Service demarre."
    }
    $wg = Get-WireGuardExe
    if (-not $wg) { throw "WireGuard introuvable." }
    $conf = Get-ServerConfigPath
    if (-not (Test-Path $conf)) { throw "Configuration serveur introuvable : $conf" }
    $r = Invoke-External $wg @('/installtunnelservice', $conf)
    if ($r.ExitCode -ne 0) { throw (($r.StdErr + "`n" + $r.StdOut).Trim()) }
    return "Tunnel installe et demarre."
}

function Stop-WinWGTunnel {
    $svc = Get-ServiceState
    if (-not $svc) { return "Service deja absent." }
    Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
    return "Service arrete."
}

function Restart-WinWGTunnel {
    $wg = Get-WireGuardExe
    $conf = Get-ServerConfigPath
    if (-not $wg) { throw "WireGuard introuvable." }
    if (-not (Test-Path $conf)) { throw "Configuration serveur introuvable : $conf" }
    Invoke-External $wg @('/uninstalltunnelservice', $TunnelName) | Out-Null
    Start-Sleep -Seconds 1
    $r = Invoke-External $wg @('/installtunnelservice', $conf)
    if ($r.ExitCode -ne 0) { throw (($r.StdErr + "`n" + $r.StdOut).Trim()) }
    return "Tunnel recharge."
}

function Get-NextDeviceNumber {
    $serverConfig = Get-ServerConfigPath
    $used = @()
    if (Test-Path $serverConfig) {
        foreach ($line in Get-Content $serverConfig) {
            if ($line -match 'AllowedIPs\s*=\s*10\.66\.66\.(\d+)/32') { $used += [int]$Matches[1] }
        }
    }
    for ($i = 2; $i -lt 255; $i++) { if ($used -notcontains $i) { return $i } }
    throw "Aucune IP VPN disponible."
}

function Add-DeviceGui {
    $name = [Microsoft.VisualBasic.Interaction]::InputBox("Nom de l'appareil", "Ajouter un appareil", "android")
    if ([string]::IsNullOrWhiteSpace($name)) { return "Annule." }
    $endpointDefault = Get-ConfiguredDeviceEndpoint
    if ([string]::IsNullOrWhiteSpace($endpointDefault)) { $endpointDefault = "TON_IP_PUBLIQUE_OU_DNS" }
    $endpoint = [Microsoft.VisualBasic.Interaction]::InputBox("Endpoint public / DNS / IPv6", "Ajouter un appareil", $endpointDefault)
    if ([string]::IsNullOrWhiteSpace($endpoint)) { return "Annule." }
    $dns = [Microsoft.VisualBasic.Interaction]::InputBox("DNS pour l'appareil", "Ajouter un appareil", "1.1.1.1, 8.8.8.8")
    if ([string]::IsNullOrWhiteSpace($dns)) { $dns = "1.1.1.1, 8.8.8.8" }
    $script = Join-Path $PSScriptRoot "Add-WireGuardPeer.ps1"
    $num = Get-NextDeviceNumber
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -DeviceName $name.Trim() -Endpoint (Normalize-EndpointBase $endpoint) -DeviceNumber $num -ListenPort $ListenPort -Dns $dns -TunnelName $TunnelName -Language fr 2>&1
    return (($out | Out-String).Trim())
}

function Remove-DeviceGui {
    $name = [Microsoft.VisualBasic.Interaction]::InputBox("Nom exact de l'appareil a supprimer", "Supprimer un appareil", "")
    if ([string]::IsNullOrWhiteSpace($name)) { return "Annule." }
    $confirm = [System.Windows.MessageBox]::Show("Supprimer l'appareil '$name' ?", "Confirmation", "YesNo", "Warning")
    if ($confirm -ne 'Yes') { return "Annule." }
    $script = Join-Path $PSScriptRoot "Remove-WireGuardPeer.ps1"
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -DeviceName $name.Trim() -TunnelName $TunnelName -Language fr 2>&1
    return (($out | Out-String).Trim())
}

function Generate-QrGui {
    $deviceDir = Get-DeviceDir
    if (-not (Test-Path $deviceDir)) { throw "Dossier devices introuvable." }
    $devices = @(Get-ChildItem $deviceDir -Filter "*.conf" | ForEach-Object { $_.BaseName })
    if ($devices.Count -eq 0) { throw "Aucun appareil." }
    $default = $devices[0]
    $name = [Microsoft.VisualBasic.Interaction]::InputBox("Nom exact de l'appareil", "Generer QR", $default)
    if ([string]::IsNullOrWhiteSpace($name)) { return "Annule." }
    $script = Join-Path $PSScriptRoot "Generate-WireGuardDeviceQr.ps1"
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -DeviceName $name.Trim() -BaseDir $BaseDir -Language fr -Open 2>&1
    return (($out | Out-String).Trim())
}

function Get-HealthText {
    $lines = New-Object System.Collections.Generic.List[string]
    $svc = Get-ServiceState
    $conf = Get-ServerConfigPath
    $fw = @(Get-NetFirewallRule -DisplayName "WireGuard Server UDP $ListenPort" -ErrorAction SilentlyContinue)
    $fw6 = @(Get-NetFirewallRule -DisplayName "WinWG WireGuard UDP $ListenPort IPv6" -ErrorAction SilentlyContinue)
    $nat = Get-NetNat -Name "WinWGOneClickServerNAT" -ErrorAction SilentlyContinue
    $devices = @()
    if (Test-Path (Get-DeviceDir)) { $devices = @(Get-ChildItem (Get-DeviceDir) -Filter "*.conf" -ErrorAction SilentlyContinue) }
    $pf = Get-PortForwardStatus

    $lines.Add("Service WireGuard : " + $(if ($svc) { "$($svc.Status)" } else { "absent" }))
    $lines.Add("Config serveur   : " + $(if (Test-Path $conf) { "OK" } else { "manquante" }))
    $lines.Add("Pare-feu IPv4    : " + $(if ($fw.Count -gt 0) { "OK" } else { "manquant" }))
    $lines.Add("Pare-feu IPv6    : " + $(if ($fw6.Count -gt 0) { "OK" } else { "non configure" }))
    $lines.Add("NAT Windows      : " + $(if ($nat) { "OK" } else { "absent" }))
    $lines.Add("Appareils        : $($devices.Count)")
    if ($pf) { $lines.Add("Acces externe    : $($pf.method) / success=$($pf.succeeded) / $($pf.checkedAt)") }
    else { $lines.Add("Acces externe    : inconnu") }
    $lines.Add("")
    $lines.Add("Note IPv6 : si ca marche en Wi-Fi mais pas en 4G/5G, cree une regle pare-feu IPv6 sur la box : UDP $ListenPort vers l'IPv6 du PC.")
    return ($lines -join "`r`n")
}

Assert-Admin

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinWG OneClick Server" Height="720" Width="980" WindowStartupLocation="CenterScreen" Background="#0f172a">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="180"/>
        </Grid.RowDefinitions>
        <DockPanel Grid.Row="0" Margin="0,0,0,12">
            <StackPanel DockPanel.Dock="Left">
                <TextBlock Text="WinWG OneClick Server" Foreground="#e5e7eb" FontSize="28" FontWeight="Bold"/>
                <TextBlock Text="Interface graphique beta - WPF" Foreground="#94a3b8" FontSize="13"/>
            </StackPanel>
            <Button Name="BtnRefresh" Content="Rafraichir" Width="120" Height="34" DockPanel.Dock="Right" Background="#2563eb" Foreground="White"/>
        </DockPanel>

        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="2*"/>
                <ColumnDefinition Width="1.35*"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="#111827" CornerRadius="12" Padding="16" Margin="0,0,10,0">
                <StackPanel>
                    <TextBlock Text="Statut" Foreground="#e5e7eb" FontSize="20" FontWeight="Bold" Margin="0,0,0,12"/>
                    <Grid>
                        <Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/>
                        </Grid.RowDefinitions>
                        <TextBlock Grid.Row="0" Grid.Column="0" Text="Installation" Foreground="#94a3b8"/><TextBlock Name="TxtInstall" Grid.Row="0" Grid.Column="1" Foreground="#e5e7eb"/>
                        <TextBlock Grid.Row="1" Grid.Column="0" Text="Service" Foreground="#94a3b8"/><TextBlock Name="TxtService" Grid.Row="1" Grid.Column="1" Foreground="#e5e7eb"/>
                        <TextBlock Grid.Row="2" Grid.Column="0" Text="Tunnel" Foreground="#94a3b8"/><TextBlock Name="TxtTunnel" Grid.Row="2" Grid.Column="1" Foreground="#e5e7eb"/>
                        <TextBlock Grid.Row="3" Grid.Column="0" Text="Port UDP" Foreground="#94a3b8"/><TextBlock Name="TxtPort" Grid.Row="3" Grid.Column="1" Foreground="#e5e7eb"/>
                        <TextBlock Grid.Row="4" Grid.Column="0" Text="IP locale" Foreground="#94a3b8"/><TextBlock Name="TxtLocalIp" Grid.Row="4" Grid.Column="1" Foreground="#e5e7eb"/>
                        <TextBlock Grid.Row="5" Grid.Column="0" Text="Endpoint" Foreground="#94a3b8"/><TextBlock Name="TxtEndpoint" Grid.Row="5" Grid.Column="1" Foreground="#e5e7eb" TextWrapping="Wrap"/>
                        <TextBlock Grid.Row="6" Grid.Column="0" Text="Acces externe" Foreground="#94a3b8"/><TextBlock Name="TxtAccess" Grid.Row="6" Grid.Column="1" Foreground="#e5e7eb"/>
                        <TextBlock Grid.Row="7" Grid.Column="0" Text="Appareils" Foreground="#94a3b8"/><TextBlock Name="TxtDevices" Grid.Row="7" Grid.Column="1" Foreground="#e5e7eb"/>
                    </Grid>
                    <TextBlock Text="Appareils configures" Foreground="#e5e7eb" FontSize="16" FontWeight="Bold" Margin="0,22,0,8"/>
                    <ListBox Name="ListDevices" Height="210" Background="#020617" Foreground="#e5e7eb" BorderBrush="#334155"/>
                </StackPanel>
            </Border>

            <Border Grid.Column="1" Background="#111827" CornerRadius="12" Padding="16">
                <StackPanel>
                    <TextBlock Text="Actions" Foreground="#e5e7eb" FontSize="20" FontWeight="Bold" Margin="0,0,0,12"/>
                    <UniformGrid Columns="2" Rows="8">
                        <Button Name="BtnStart" Content="Demarrer" Margin="4" Height="42" Background="#16a34a" Foreground="White"/>
                        <Button Name="BtnStop" Content="Arreter" Margin="4" Height="42" Background="#dc2626" Foreground="White"/>
                        <Button Name="BtnRestart" Content="Redemarrer" Margin="4" Height="42" Background="#ca8a04" Foreground="White"/>
                        <Button Name="BtnHealth" Content="Health check" Margin="4" Height="42" Background="#2563eb" Foreground="White"/>
                        <Button Name="BtnAdd" Content="Ajouter appareil" Margin="4" Height="42" Background="#334155" Foreground="White"/>
                        <Button Name="BtnRemove" Content="Supprimer appareil" Margin="4" Height="42" Background="#334155" Foreground="White"/>
                        <Button Name="BtnQr" Content="Generer QR" Margin="4" Height="42" Background="#334155" Foreground="White"/>
                        <Button Name="BtnOpenConsole" Content="Console texte" Margin="4" Height="42" Background="#334155" Foreground="White"/>
                        <Button Name="BtnIPv6" Content="Mode IPv6 direct" Margin="4" Height="42" Background="#7c3aed" Foreground="White"/>
                        <Button Name="BtnIPv4" Content="Mode IPv4/DNS" Margin="4" Height="42" Background="#7c3aed" Foreground="White"/>
                        <Button Name="BtnInstaller" Content="Installer/Reparer" Margin="4" Height="42" Background="#475569" Foreground="White"/>
                        <Button Name="BtnDebugUpnp" Content="DEBUG-UPNP" Margin="4" Height="42" Background="#475569" Foreground="White"/>
                        <Button Name="BtnDevicesFolder" Content="Dossier devices" Margin="4" Height="42" Background="#475569" Foreground="White"/>
                        <Button Name="BtnQrFolder" Content="Dossier QR" Margin="4" Height="42" Background="#475569" Foreground="White"/>
                    </UniformGrid>
                    <TextBlock Text="Note : l'IPv6 direct peut demander une regle pare-feu IPv6 sur la box." Foreground="#facc15" TextWrapping="Wrap" Margin="4,16,4,0"/>
                </StackPanel>
            </Border>
        </Grid>

        <Border Grid.Row="2" Background="#020617" CornerRadius="12" Padding="10" Margin="0,12,0,0">
            <TextBox Name="TxtLog" Background="#020617" Foreground="#d1d5db" BorderThickness="0" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" FontFamily="Consolas"/>
        </Border>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

function C([string]$Name) { return $window.FindName($Name) }

$TxtInstall = C 'TxtInstall'; $TxtService = C 'TxtService'; $TxtTunnel = C 'TxtTunnel'; $TxtPort = C 'TxtPort'; $TxtLocalIp = C 'TxtLocalIp'; $TxtEndpoint = C 'TxtEndpoint'; $TxtAccess = C 'TxtAccess'; $TxtDevices = C 'TxtDevices'; $ListDevices = C 'ListDevices'; $TxtLog = C 'TxtLog'

function Add-Log([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $TxtLog.AppendText("[$(Get-Date -Format HH:mm:ss)] $Text`r`n")
    $TxtLog.ScrollToEnd()
}

function Refresh-Ui {
    $conf = Get-ServerConfigPath
    $svc = Get-ServiceState
    $endpoint = Get-ConfiguredDeviceEndpoint
    $pf = Get-PortForwardStatus
    $devices = @()
    if (Test-Path (Get-DeviceDir)) { $devices = @(Get-ChildItem (Get-DeviceDir) -Filter "*.conf" -ErrorAction SilentlyContinue) }

    $TxtInstall.Text = if (Test-Path $conf) { "presente" } else { "absente" }
    $TxtService.Text = if ($svc) { "$($svc.Name) - $($svc.Status)" } else { "introuvable / desactive" }
    $TxtTunnel.Text = $TunnelName
    $TxtPort.Text = "UDP $ListenPort"
    $TxtLocalIp.Text = Get-PrimaryIPv4
    $TxtEndpoint.Text = if ($endpoint) { "$endpoint`:$ListenPort" } else { "inconnu" }
    $TxtAccess.Text = if ($pf) { "$($pf.method) / success=$($pf.succeeded)" } else { "inconnu" }
    $TxtDevices.Text = "$($devices.Count) fichier(s)"
    $ListDevices.Items.Clear()
    foreach ($d in $devices) { [void]$ListDevices.Items.Add($d.BaseName) }
}

function Run-Action([scriptblock]$Action) {
    try {
        $result = & $Action
        if ($result) { Add-Log $result }
    } catch {
        Add-Log "ERREUR : $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($_.Exception.Message, "WinWG OneClick Server", "OK", "Error") | Out-Null
    } finally {
        Refresh-Ui
    }
}

(C 'BtnRefresh').Add_Click({ Refresh-Ui; Add-Log "Statut rafraichi." })
(C 'BtnStart').Add_Click({ Run-Action { Start-WinWGTunnel } })
(C 'BtnStop').Add_Click({ Run-Action { Stop-WinWGTunnel } })
(C 'BtnRestart').Add_Click({ Run-Action { Restart-WinWGTunnel } })
(C 'BtnHealth').Add_Click({ Run-Action { Get-HealthText } })
(C 'BtnAdd').Add_Click({ Run-Action { Add-DeviceGui } })
(C 'BtnRemove').Add_Click({ Run-Action { Remove-DeviceGui } })
(C 'BtnQr').Add_Click({ Run-Action { Generate-QrGui } })
(C 'BtnOpenConsole').Add_Click({ Start-Process -FilePath (Join-Path (Split-Path $PSScriptRoot -Parent) "SERVER-CONSOLE.bat") | Out-Null })
(C 'BtnInstaller').Add_Click({ Start-Process -FilePath (Join-Path (Split-Path $PSScriptRoot -Parent) "INSTALLER-ONE-CLICK.bat") | Out-Null })
(C 'BtnDebugUpnp').Add_Click({ Start-Process -FilePath (Join-Path (Split-Path $PSScriptRoot -Parent) "DEBUG-UPNP.bat") | Out-Null })
(C 'BtnDevicesFolder').Add_Click({ Ensure-Directory (Get-DeviceDir); Start-Process (Get-DeviceDir) | Out-Null })
(C 'BtnQrFolder').Add_Click({ Ensure-Directory (Get-QrDir); Start-Process (Get-QrDir) | Out-Null })
(C 'BtnIPv6').Add_Click({
    Run-Action {
        $ipv6 = Get-PublicIPv6Candidate
        if ([string]::IsNullOrWhiteSpace($ipv6)) { throw "Aucune IPv6 publique globale detectee sur ce PC." }
        $fwName = "WinWG WireGuard UDP $ListenPort IPv6"
        Get-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        New-NetFirewallRule -DisplayName $fwName -Direction Inbound -Action Allow -Protocol UDP -LocalPort $ListenPort -RemoteAddress Any -LocalAddress Any | Out-Null
        $result = Update-AllDeviceEndpoints "[$ipv6]"
        Save-PortForwardStatus -Succeeded $true -Method 'ipv6-endpoint' -Message "IPv6 endpoint selected from GUI: [$ipv6]:$ListenPort"
        "Mode IPv6 direct active : $($result.EndpointLine)`r`nConfigs mises a jour : $($result.Updated)`r`nImportant : reimporte le .conf ou regenere le QR. Si ca marche en Wi-Fi mais pas en 4G/5G, cree une regle pare-feu IPv6 sur la box : UDP $ListenPort vers l'IPv6 du PC."
    }
})
(C 'BtnIPv4').Add_Click({
    Run-Action {
        $default = Get-ConfiguredDeviceEndpoint
        if ([string]::IsNullOrWhiteSpace($default) -or $default -match '^\[') { $default = "TON_IP_PUBLIQUE_OU_DNS" }
        $endpoint = [Microsoft.VisualBasic.Interaction]::InputBox("IP publique IPv4 ou DNS", "Mode IPv4/DNS", $default)
        if ([string]::IsNullOrWhiteSpace($endpoint)) { return "Annule." }
        $result = Update-AllDeviceEndpoints $endpoint
        Save-PortForwardStatus -Succeeded $false -Method 'manual-required' -Message "Manual IPv4/DNS endpoint selected from GUI: $($result.EndpointLine)"
        "Mode IPv4/DNS active : $($result.EndpointLine)`r`nConfigs mises a jour : $($result.Updated)`r`nImportant : reimporte le .conf ou regenere le QR."
    }
})

Refresh-Ui
Add-Log "GUI demarree."
[void]$window.ShowDialog()
