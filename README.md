# WinWG OneClick Server

English | [Français](README.fr.md)

![Status](https://img.shields.io/badge/status-beta-orange) ![Platform](https://img.shields.io/badge/platform-Windows-blue) ![License](https://img.shields.io/badge/license-MIT-green)

**One script. One click. Your Windows PC becomes a WireGuard VPN server.**


> 💙 **Support the project**: WinWG OneClick Server is free and open source. Donations are optional.  
> BTC: `bc1qp3lzycrpngpk00tecj85pfkhrqqr49gmslzmsg`  
> ETH: `0xbb07ad0dd362c15a3167ececc0640c770c45849a` — see [`docs/DONATE.md`](docs/DONATE.md).

WinWG OneClick Server is a simple Windows project that turns a Windows 10/11 PC into a **WireGuard remote access server** with a **single script / single double-click** installation. It also generates the configuration file to import on a remote device such as a phone, tablet, or laptop.

> ⚠️ Important: to connect from outside your local network, the Windows PC must be reachable from the Internet. In most home setups, this means:
> 1. forwarding a UDP port on your router/Internet box to the Windows PC;
> 2. using your public IP address or a dynamic DNS hostname;
> 3. avoiding CG-NAT, or asking your ISP for a public/full-stack IPv4 address.


## Project status

WinWG OneClick Server is currently in **beta**. It is usable, but it still needs testing on multiple Windows machines before being considered stable.

Use it first for personal, home-lab, or test environments. Avoid installing it directly on a critical machine without validation.


## Application language

WinWG supports French and English.

During one-click installation, the script asks which language should be used. The default is detected from the Windows system language:

```text
fr = Français
en = English
```

The console can also change the language later with:

```text
L - Change language
```

The choice is stored in:

```text
C:\ProgramData\WinWGOneClickServer\settings\language.txt
```

Note: translation is progressive. The main installer/console flow is prioritized first.

## Project promise

The goal of WinWG OneClick Server is simple:

```text
1 script
1 double-click
1 working WireGuard server on Windows
```

The project automatically configures what is usually painful to do manually:

- WireGuard for Windows installation if missing;
- server and remote-device key generation;
- WireGuard tunnel service creation;
- Windows Firewall rule;
- Windows NAT;
- optional UPnP port-forwarding attempt;
- `.conf` file ready to import into the WireGuard mobile app;
- local monitoring console;
- service start/stop toggle;
- clean uninstaller.

> Compatibility note: some internal paths keep the historical name `WinWGOneClickServer`, for example `C:\ProgramData\WinWGOneClickServer`. This is intentional to avoid breaking existing installations.

## Recommended one-click installation

During one-click installation, the first device DNS is also requested. If you do not know what to enter, type nothing and keep the default `1.1.1.1, 8.8.8.8`. You can also use your router DNS, for example `192.168.1.1`.

If the QR feature is enabled during installation, the installer also asks whether a QR code should be generated for the first device. You can answer `yes` or `no`. If you decline, the `.conf` file remains available and you can generate the QR later from the console.


On the Windows PC that should become the VPN server:

1. Download/copy this repository to the PC.
2. Double-click:

```text
INSTALLER-ONE-CLICK.bat
```

The installer asks for Windows administrator rights, installs WireGuard if needed, generates the server + device configuration, configures firewall, routing and NAT, then opens the folder containing the `.conf` file to import into the WireGuard mobile app.

It also tries to create the router port-forwarding automatically via UPnP.
> UPnP note: the installer now tries to make UPnP more reliable by starting Windows SSDP/UPnP services, removing conflicting old mappings, retrying several times and verifying the created mapping. Even with this, UPnP still depends on the router: it may be disabled, unsupported or impossible behind CG-NAT.
 If your router refuses it or UPnP is disabled, the installer shows the PC local IP address and you must manually forward the port:

```text
UDP 51820 -> Windows PC local IP -> UDP 51820
```

Ideally, this local IP should be reserved through a **static DHCP lease** in the router/Internet box.

> Note: no local installer can bypass your ISP CG-NAT. If you are behind CG-NAT, ask your ISP for a public/full-stack IPv4 address or use a relay/VPS.

## Requirements

- Windows 10/11.
- PowerShell running as **administrator**.
- Router/Internet box admin access for port-forwarding if UPnP fails.
- WireGuard app installed on your remote device:
  - Android: Google Play / F-Droid.
  - iPhone: App Store.



## Optional donations

WinWG OneClick Server is free and open source.

Donations are fully optional and are never required to use, modify, redistribute, or contribute to the project.

Bitcoin BTC address:

```text
bc1qp3lzycrpngpk00tecj85pfkhrqqr49gmslzmsg
```

Ethereum ETH address:

```text
0xbb07ad0dd362c15a3167ececc0640c770c45849a
```

More information: [`docs/DONATE.md`](docs/DONATE.md).

## Attribution

License: MIT.

You may use, copy, modify, redistribute, and include this project in other projects, including commercially, as long as the copyright and license notice are preserved.

Original project: **WinWG OneClick Server**  
Author: **KLM-DEV**  
Repository: `https://github.com/KLM-corporation/winwg-oneclick-server`

## Originality, attribution and WireGuard trademark

WinWG OneClick Server is an independent project. It is not a fork and is not based on a copy of another open source project.

It uses the official WireGuard for Windows tools (`wg.exe` and `wireguard.exe`) and native Windows/PowerShell commands (`New-NetNat`, `New-NetFirewallRule`, Windows services, etc.).

WireGuard is a project and trademark owned by its respective authors. This repository is not affiliated with, sponsored by, endorsed by, or approved by the WireGuard project.

The name `WinWG` simply means:

```text
Windows + WireGuard helper
```

## Server vs device configuration

On Windows, there is no official separate “server-only” package. The WireGuard for Windows application also provides the components needed for server mode: `wg.exe`, `wireguard.exe`, the driver, and the tunnel service.

This project does **not** turn your Windows PC into a VPN device. It uses WireGuard to create a **server tunnel** on the PC.

When the script mentions `device` files or the `devices` folder, it means:

```text
configuration to import on the remote device
```

The remote device is the VPN peer/device. The Windows PC remains the server.

## Quick manual install

Open PowerShell **as administrator**, then:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd .\winwg-oneclick-server
.\scripts\Install-WireGuardServer.ps1 -Endpoint "MY_PUBLIC_IP_OR_DNS" -DeviceName "device"
```

Example with dynamic DNS:

```powershell
.\scripts\Install-WireGuardServer.ps1 -Endpoint "home-vpn.duckdns.org" -DeviceName "iphone"
```

At the end, the script shows the device configuration path, for example:

```text
C:\ProgramData\WinWGOneClickServer\devices\iphone.conf
```

Copy this file to your device and import it into the WireGuard app.


## GitHub Actions / CI

The repository contains two GitHub Actions workflows:

```text
.github/workflows/ci.yml
.github/workflows/release-package.yml
```


The CI workflow checks:

- PowerShell syntax with Windows PowerShell 5.1;
- PowerShell syntax with PowerShell 7;
- PSScriptAnalyzer errors;
- absence of generated sensitive files (`.conf`, `.key`, `.psk`, `.env`, etc.);
- presence of important public-facing files;
- broken relative Markdown links.

The release workflow can generate a clean ZIP package through `workflow_dispatch` or a `v*` tag, for example:

```text
v0.1.0-beta
```


## Existing configuration recovery

If you ran the uninstaller while keeping configurations, then run `INSTALLER-ONE-CLICK.bat` again, the installer now detects:

```text
C:\ProgramData\WinWGOneClickServer\server\winwg-server.conf
```

It then offers:

```text
1 - Restore/reinstall the service with this configuration
2 - Add a new device to this configuration
3 - Clean reinstall and regenerate all keys
4 - Cancel
```

This helps avoid accidentally overwriting existing keys.

## One-click uninstall

To cleanly remove everything configured by this project from the Windows PC, double-click:

```text
UNINSTALLER-ONE-CLICK.bat
```

The uninstaller removes:

- the WireGuard tunnel/service `winwg-server`;
- the UDP `51820` firewall rule;
- the Windows NAT `WinWGOneClickServerNAT`;
- the UDP `51820` UPnP mapping if it was automatically created;
- configurations and keys in `C:\ProgramData\WinWGOneClickServer`;
- generated QR codes in `qrcodes`;
- optional QRCoder QR dependency in `tools`;
- feature flags in `features`;
- optionally the WireGuard application itself.

If you manually created port-forwarding on your router, you must also remove it in the router admin UI.

> Safety note: the uninstaller no longer disables global Windows IPv4 routing, to avoid breaking Hyper-V, WSL, Internet Connection Sharing, or other networking tools.

Advanced silent mode:

```powershell
.\scripts\Uninstall-WireGuard-Server.ps1 -Quiet -RemoveWireGuardApp
```


## Unified server console

WireGuard for Windows runs as a background service. WinWG now combines monitoring and service control in a single console:

```text
SERVER-CONSOLE.bat
```

The console lets you:

- view the WireGuard service status;
- view connected devices/devices, their handshakes and their RX/TX speed;
- check firewall, NAT and UDP port status;
- enable/start the VPN server;
- disable/stop the VPN server without deleting configurations;
- restart the VPN server;
- add a remote device such as a phone, tablet, or laptop;
- remove an existing device.

Available menu inside the console:

```text
1 / A - Enable / start the VPN server
2 / D - Disable / stop the VPN server
3     - Restart the VPN server
4 / N - Add a new device
5 / R - Remove a device
6 / G - Generate a QR code for a device
S     - Refresh status
V     - Enable/disable ultra verbose mode
M     - Advanced mode / expert tools
Q     - Quit the console
```

The console does not auto-refresh every 5 seconds anymore: it waits for your keyboard choice, which avoids input issues and constantly moving output.

> Display: the console adds a small left margin to avoid the first letters being clipped in some Windows terminals.

In this version, `R` means `Remove a device`. To restart the VPN server, use number `3`, to avoid confusion between restart and remove.


The console also displays an estimated speed per peer:

```text
Speed: RX 120.50 KiB/s / TX 42.10 KiB/s
```

This speed is calculated between two status displays. Press `S` after a few seconds to get a measurement. On first display, the console shows `calcul au prochain refresh`.

If the uninstaller removed the configurations, the console cannot re-enable the VPN and will ask you to run `INSTALLER-ONE-CLICK.bat` again.

> Note: the old separate `WIREGUARD-SERVICE-TOGGLE.bat` script has been removed in this test version because its functions are now integrated into `SERVER-CONSOLE.bat`.



## UPnP / NAT-PMP / PCP diagnostics

If automatic port forwarding fails, you can run:

```text
DEBUG-UPNP.bat
```

This diagnostic does not create any port mapping. It checks:

- the network interface being used;
- the IPv4 gateway;
- SSDP responses;
- detected UPnP devices;
- whether a NAT service such as `WANIPConnection` / `WANPPPConnection` exists;
- PCP/NAT-PMP responses on UDP 5351.

The result is saved in:

```text
C:\ProgramData\WinWGOneClickServer\logs
```

This helps distinguish:

```text
UPnP present on the network
UPnP IGD NAT actually usable
PCP/NAT-PMP available or not
```

## Router port-forwarding

In your router/Internet box admin panel:

| Setting | Default value |
|---|---|
| Protocol | UDP |
| External port | 51820 |
| Local target IP | Windows PC LAN IP |
| Internal port | 51820 |

Network recommendation: create a **static DHCP lease** / **DHCP reservation** for the Windows PC in your router/Internet box. The goal is for the VPN server to always keep the same LAN address, for example `192.168.1.14`.

In practice, bind:

```text
Windows PC MAC address -> reserved LAN IP address
```

Example:

```text
D4:3A:2E:85:CA:DF -> 192.168.1.14
```

Then point the port-forwarding rule to that reserved IP:

```text
UDP 51820 -> 192.168.1.14 -> UDP 51820
```

This is usually better than manually configuring a static IP inside Windows, because the router remains in charge of the address plan and avoids DHCP conflicts.




### Ultra verbose mode

Inside `SERVER-CONSOLE.bat`, press:

```text
V
```

This mode shows more details during sensitive actions, including:

- called PowerShell script;
- parameters used;
- exit code;
- full script output;
- verification result after adding/removing a device;
- log file path.

A log file is also written to:

```text
C:\ProgramData\WinWGOneClickServer\logs
```

This is useful to diagnose cases where a device is correctly created/removed but the WireGuard service reload returns a warning.



## Advanced mode / expert tools

The console includes an advanced mode intended for users who already understand WireGuard.

```text
M - Advanced mode / expert tools
```

Before activation, the console displays a warning and asks you to type exactly:

```text
JE COMPRENDS
```

This mode may expose sensitive files and actions. It can:

- show raw `wg show` output;
- open server, devices and QR code folders;
- export a redacted diagnostic file;
- edit advanced configuration: WireGuard port, device DNS and `AllowedIPs`;
- open the server `winwg-server.conf` file in Notepad.

Warning: the server configuration file contains the WireGuard private key. Never share this file, its content, or an unredacted screenshot.



### Customizable advanced configuration

Advanced mode also contains:

```text
6 - Edit advanced configuration (port, DNS, AllowedIPs)
```

Available options:

- change the global WireGuard UDP port;
- change DNS for all devices;
- change DNS for a single device;
- change device `AllowedIPs` mode for all devices;
- edit `AllowedIPs` for a single device;
- change `PersistentKeepalive` for all devices;
- change `PersistentKeepalive` for a single device.

Principle: when a setting affects devices, the console offers two levels whenever possible:

```text
Global = apply the same value to all devices
Individual = customize only one device/device
```


### Advanced example: edit PersistentKeepalive

By default, device configurations use:

```ini
PersistentKeepalive = 25
```

This helps keep the device-side NAT mapping open, especially on 4G/5G devices, public Wi-Fi, or strict routers.

Suggested values:

```text
0  = disabled
15 = mobile networks / very strict NAT
25 = recommended / WireGuard default
60 = less frequent
```

As with DNS and `AllowedIPs`, the console can change this value globally for all devices or individually for a single device.

After changing this, you must re-import the `.conf` file or rescan the new QR code on the device.

### Advanced example: edit AllowedIPs

By default, device configurations use:

```ini
AllowedIPs = 0.0.0.0/0
```

This means **IPv4 full tunnel**: all IPv4 traffic from the device goes through the VPN.

In advanced mode, you can edit this value for a device:

```text
6 - Edit AllowedIPs for a device
```

Useful examples:

```ini
AllowedIPs = 0.0.0.0/0
```

Full tunnel: all IPv4 traffic goes through the VPN.

```ini
AllowedIPs = 10.66.66.0/24
```

VPN only: useful for WireGuard LAN party or peer-to-peer VPN access without routing all Internet traffic through the VPN.

```ini
AllowedIPs = 10.66.66.0/24, 192.168.1.0/24
```

VPN + home LAN: allows access to the VPN network and the home LAN.

After changing this, you must re-import the `.conf` file or rescan the new QR code on the device. Otherwise, the device will keep using the previous `AllowedIPs` configuration.



You can also manage the QR feature from the console:

```text
7 / K - QR code settings
```

This menu can enable/disable the QR feature, install/check QRCoder and open the QR code folder.

## WireGuard QR code

The WireGuard Android/iOS app can import a configuration by scanning a QR code.

During installation, WinWG asks whether you want to install the optional QR code generation dependency. If you decline, the QR option is hidden from the console.

If enabled, WinWG can generate this QR locally from `SERVER-CONSOLE.bat`:

```text
6 / G - Generate a QR code for a device
```

After adding a new device, the console also tries to automatically generate its QR code only if the QR feature was enabled during installation.

QR codes are stored here:

```text
C:\ProgramData\WinWGOneClickServer\qrcodes
```

Important: a WireGuard QR code contains the device private key, exactly like the `.conf` file. Never share it publicly.

To generate QR codes locally without sending configurations to a third-party service, WinWG downloads the open source .NET **QRCoder** library from NuGet if needed and uses it locally.


## Temporary devices

WinWG can now create a temporary device from the console.

When adding a device:

```text
4 / N - Add a new device
```

The console asks whether the device should be temporary. If yes, you can choose a duration:

```text
1 - 1 hour
2 - 6 hours
3 - 24 hours
4 - 7 days
5 - custom duration in hours
```

WinWG now creates a metadata file for every device. For a temporary device, this file also contains the expiration date:

```text
C:\ProgramData\WinWGOneClickServer\devices\NAME.meta.json
```

For a permanent device, the same `.meta.json` file is created with `temporary = false` and no expiration.

The console displays the expiration in the peer list only for temporary devices.

To remove expired temporary devices:

```text
8 / E - Remove expired temporary devices
```

Current simple mode: cleanup is manual from the console. There is no automatic Windows scheduled task yet.

## Device management from the console

From `SERVER-CONSOLE.bat`, you can now manage devices without manual PowerShell commands:

```text
N - Add a new device
X - Remove a device
```

Adding a device:

- asks for the device name;
- suggests the already-used public/DNS endpoint when possible;
- asks which DNS should be used by this device, with the option to type nothing and keep the default DNS;
- automatically selects the next available VPN IP;
- generates the `.conf` file to import;
- opens the folder containing the generated configuration.

When adding a device, if the QR feature is globally enabled, the console now asks whether you want to generate a QR code for that specific device. You can answer `yes` or `no`.

> Note: if adding creates the `.conf` file and peer but an error appears while reloading the service, the console reports it as a successful addition with a warning. You can then use `3` to restart the VPN server.

Removing a device:

- lists existing `.conf` files;
- if there is only one device, selects it automatically;
- asks for confirmation;
- removes the peer from the server;
- deletes the matching local `.conf` file;
- reloads the WireGuard service.

> Note: if removal deletes the `.conf` file and peer but an error appears while reloading the service, the console reports it as a successful removal with a warning. You can then use `3` to restart the VPN server.



## Usage

### Add a second device

```powershell
.\scripts\Add-WireGuardPeer.ps1 -DeviceName "android" -Endpoint "home-vpn.duckdns.org"
```

### Remove a device

```powershell
.\scripts\Remove-WireGuardPeer.ps1 -DeviceName "android"
```

### List generated device configurations

```powershell
Get-ChildItem "C:\ProgramData\WinWGOneClickServer\devices"
```

### Restart the tunnel manually

```powershell
& "$env:ProgramFiles\WireGuard\wireguard.exe" /uninstalltunnelservice "winwg-server"
& "$env:ProgramFiles\WireGuard\wireguard.exe" /installtunnelservice "C:\ProgramData\WinWGOneClickServer\server\winwg-server.conf"
```

## Default configuration

| Option | Value |
|---|---|
| Tunnel name | `winwg-server` |
| WireGuard port | `51820/UDP` |
| VPN network | `10.66.66.0/24` |
| VPN server IP | `10.66.66.1` |
| Device DNS | `1.1.1.1, 8.8.8.8` |
| Device mode | full-tunnel IPv4: `AllowedIPs = 0.0.0.0/0` |

## Test from your device

1. Disable Wi-Fi on the device.
2. Enable 4G/5G.
3. Enable the WireGuard tunnel.
4. Open a website such as `https://ifconfig.me`.
5. The displayed IP should be your home Internet public IP.

## Troubleshooting

See [`docs/TROUBLESHOOTING.en.md`](docs/TROUBLESHOOTING.en.md).


## Security warning

This project configures a VPN server and may expose a UDP port to the Internet. You are responsible for your network configuration.

Before public or long-term use:

- keep Windows and WireGuard up to date;
- never share generated `.conf` files;
- immediately remove lost or compromised devices;
- verify your port-forwarding configuration;
- understand CG-NAT limitations;
- test uninstall before depending on the server.

## Security

- Never share generated `.conf` files: they contain private keys.
- Prefer a dynamic DNS name instead of copying an IP address everywhere.
- Keep Windows and WireGuard up to date.
- Immediately remove a peer if a device is lost.

## Known limitations

- If your ISP uses CG-NAT, port-forwarding will not work. Solutions: ask for a public/full-stack IPv4, use IPv6, or use a relay/VPS.
- The script configures IPv4. IPv6 is not enabled by default.
- Some third-party antivirus/firewall products may block UDP traffic.
