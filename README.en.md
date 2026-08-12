# WinWG OneClick Server

![Status](https://img.shields.io/badge/status-beta-orange) ![Platform](https://img.shields.io/badge/platform-Windows-blue) ![License](https://img.shields.io/badge/license-MIT-green)

**One script. One click. Your Windows PC becomes a WireGuard VPN server.**


> 💙 **Support the project**: WinWG OneClick Server is free and open source. Donations are optional.  
> BTC: `bc1qp3lzycrpngpk00tecj85pfkhrqqr49gmslzmsg` — see [`DONATE.md`](DONATE.md).

WinWG OneClick Server is a simple Windows project that turns a Windows 10/11 PC into a **WireGuard remote access server** with a **single script / single double-click** installation. It also generates the configuration file to import on your phone, tablet, or laptop.

> ⚠️ Important: to connect from outside your local network, the Windows PC must be reachable from the Internet. In most home setups, this means:
> 1. forwarding a UDP port on your router/Internet box to the Windows PC;
> 2. using your public IP address or a dynamic DNS hostname;
> 3. avoiding CG-NAT, or asking your ISP for a public/full-stack IPv4 address.


## Project status

WinWG OneClick Server is currently in **beta**. It is usable, but it still needs testing on multiple Windows machines before being considered stable.

Use it first for personal, home-lab, or test environments. Avoid installing it directly on a critical machine without validation.

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

> Compatibility note: some internal paths keep the historical name `WireGuardPhoneServer`, for example `C:\ProgramData\WireGuardPhoneServer`. This is intentional to avoid breaking existing installations.

## Recommended one-click installation

On the Windows PC that should become the VPN server:

1. Download/copy this repository to the PC.
2. Double-click:

```text
INSTALLER-ONE-CLICK.bat
```

The installer asks for Windows administrator rights, installs WireGuard if needed, generates the server + phone configuration, configures firewall, routing and NAT, then opens the folder containing the `.conf` file to import into the WireGuard mobile app.

It also tries to create the router port-forwarding automatically via UPnP. If your router refuses it or UPnP is disabled, the installer shows the PC local IP address and you must manually forward the port:

```text
UDP 51820 -> Windows PC local IP -> UDP 51820
```

Ideally, this local IP should be reserved through a **static DHCP lease** in the router/Internet box.

> Note: no local installer can bypass your ISP CG-NAT. If you are behind CG-NAT, ask your ISP for a public/full-stack IPv4 address or use a relay/VPS.

## Requirements

- Windows 10/11.
- PowerShell running as **administrator**.
- Router/Internet box admin access for port-forwarding if UPnP fails.
- WireGuard mobile app installed on your phone:
  - Android: Google Play / F-Droid.
  - iPhone: App Store.



## Optional donations

WinWG OneClick Server is free and open source.

Donations are fully optional and are never required to use, modify, redistribute, or contribute to the project.

Bitcoin BTC address:

```text
bc1qp3lzycrpngpk00tecj85pfkhrqqr49gmslzmsg
```

More information: [`DONATE.md`](DONATE.md).

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

## Server vs phone configuration

On Windows, there is no official separate “server-only” package. The WireGuard for Windows application also provides the components needed for server mode: `wg.exe`, `wireguard.exe`, the driver, and the tunnel service.

This project does **not** turn your Windows PC into a VPN client. It uses WireGuard to create a **server tunnel** on the PC.

When the script mentions `client` files or the `clients` folder, it means:

```text
configuration to import on your phone/remote device
```

The phone is the VPN client. The Windows PC remains the server.

## Quick manual install

Open PowerShell **as administrator**, then:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd .\winwg-oneclick-server
.\scripts\Install-WireGuardServer.ps1 -Endpoint "MY_PUBLIC_IP_OR_DNS" -ClientName "phone"
```

Example with dynamic DNS:

```powershell
.\scripts\Install-WireGuardServer.ps1 -Endpoint "home-vpn.duckdns.org" -ClientName "iphone"
```

At the end, the script shows the phone configuration path, for example:

```text
C:\ProgramData\WireGuardPhoneServer\clients\iphone.conf
```

Copy this file to your phone and import it into the WireGuard app.


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

## One-click uninstall

To cleanly remove everything configured by this project from the Windows PC, double-click:

```text
UNINSTALLER-ONE-CLICK.bat
```

The uninstaller removes:

- the WireGuard tunnel/service `wg-phone-server`;
- the UDP `51820` firewall rule;
- the Windows NAT `WireGuardPhoneServerNAT`;
- the UDP `51820` UPnP mapping if it was automatically created;
- configurations and keys in `C:\ProgramData\WireGuardPhoneServer`;
- generated QR codes in `qrcodes`;
- optional QRCoder QR dependency in `tools`;
- feature flags in `features`;
- optionally the WireGuard application itself.

If you manually created port-forwarding on your router, you must also remove it in the router admin UI.

> Safety note: the uninstaller no longer disables global Windows IPv4 routing, to avoid breaking Hyper-V, WSL, Internet Connection Sharing, or other networking tools.

Advanced silent mode:

```powershell
.\Uninstall-WireGuard-Server.ps1 -Quiet -RemoveWireGuardApp
```


## Unified server console

WireGuard for Windows runs as a background service. WinWG now combines monitoring and service control in a single console:

```text
SERVER-CONSOLE.bat
```

The console lets you:

- view the WireGuard service status;
- view connected phones/devices, their handshakes and their RX/TX speed;
- check firewall, NAT and UDP port status;
- enable/start the VPN server;
- disable/stop the VPN server without deleting configurations;
- restart the VPN server;
- add a phone, tablet, or laptop;
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
C:\ProgramData\WireGuardPhoneServer\logs
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
- open server, clients and QR code folders;
- export a redacted diagnostic file;
- edit advanced configuration: WireGuard port, client DNS and `AllowedIPs`;
- precisely edit `AllowedIPs` in a client configuration;
- open the server `wg-phone-server.conf` file in Notepad.

Warning: the server configuration file contains the WireGuard private key. Never share this file, its content, or an unredacted screenshot.



### Customizable advanced configuration

Advanced mode also contains:

```text
6 - Edit advanced configuration (port, DNS, AllowedIPs)
```

Available options:

- change the WireGuard UDP port;
- change DNS for all clients;
- change client `AllowedIPs` mode for all clients;
- edit `AllowedIPs` for a single client;
- display a warning for structural options: tunnel name, VPN network, VPN server IP.

Structural options are not automatically changed yet, because they require reconfiguring the Windows service, NAT, peers, client IPs, `.conf` files and QR codes. They should be handled later through a proper advanced reinstall/migration mode.

### Advanced example: edit AllowedIPs

By default, client configurations use:

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
C:\ProgramData\WireGuardPhoneServer\qrcodes
```

Important: a WireGuard QR code contains the device private key, exactly like the `.conf` file. Never share it publicly.

To generate QR codes locally without sending configurations to a third-party service, WinWG downloads the open source .NET **QRCoder** library from NuGet if needed and uses it locally.

## Device management from the console

From `SERVER-CONSOLE.bat`, you can now manage devices without manual PowerShell commands:

```text
N - Add a new device
X - Remove a device
```

Adding a device:

- asks for the device name;
- suggests the already-used public/DNS endpoint when possible;
- automatically selects the next available VPN IP;
- generates the `.conf` file to import;
- opens the folder containing the generated configuration.

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

### Add a second phone/device

```powershell
.\scripts\Add-WireGuardPeer.ps1 -ClientName "android" -Endpoint "home-vpn.duckdns.org"
```

### Remove a device

```powershell
.\scripts\Remove-WireGuardPeer.ps1 -ClientName "android"
```

### List generated device configurations

```powershell
Get-ChildItem "C:\ProgramData\WireGuardPhoneServer\clients"
```

### Restart the tunnel manually

```powershell
& "$env:ProgramFiles\WireGuard\wireguard.exe" /uninstalltunnelservice "wg-phone-server"
& "$env:ProgramFiles\WireGuard\wireguard.exe" /installtunnelservice "C:\ProgramData\WireGuardPhoneServer\server\wg-phone-server.conf"
```

## Default configuration

| Option | Value |
|---|---|
| Tunnel name | `wg-phone-server` |
| WireGuard port | `51820/UDP` |
| VPN network | `10.66.66.0/24` |
| VPN server IP | `10.66.66.1` |
| Client DNS | `1.1.1.1, 8.8.8.8` |
| Client mode | full-tunnel IPv4: `AllowedIPs = 0.0.0.0/0` |

## Test from your phone

1. Disable Wi-Fi on the phone.
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
- Immediately remove a peer if a phone/device is lost.

## Known limitations

- If your ISP uses CG-NAT, port-forwarding will not work. Solutions: ask for a public/full-stack IPv4, use IPv6, or use a relay/VPS.
- The script configures IPv4. IPv6 is not enabled by default.
- Some third-party antivirus/firewall products may block UDP traffic.
