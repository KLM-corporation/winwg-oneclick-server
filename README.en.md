# WinWG OneClick Server

**One script. One click. Your Windows PC becomes a WireGuard VPN server.**

WinWG OneClick Server is a simple Windows project that turns a Windows 10/11 PC into a **WireGuard remote access server** with a **single script / single double-click** installation. It also generates the configuration file to import on your phone, tablet, or laptop.

> ⚠️ Important: to connect from outside your local network, the Windows PC must be reachable from the Internet. In most home setups, this means:
> 1. forwarding a UDP port on your router/Internet box to the Windows PC;
> 2. using your public IP address or a dynamic DNS hostname;
> 3. avoiding CG-NAT, or asking your ISP for a public/full-stack IPv4 address.

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

> Note: no local installer can bypass your ISP CG-NAT. If you are behind CG-NAT, ask your ISP for a public/full-stack IPv4 address or use a relay/VPS.

## Requirements

- Windows 10/11.
- PowerShell running as **administrator**.
- Router/Internet box admin access for port-forwarding if UPnP fails.
- WireGuard mobile app installed on your phone:
  - Android: Google Play / F-Droid.
  - iPhone: App Store.

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
- view connected phones/devices and their handshakes;
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
S     - Refresh status
Q     - Quit the console
```

The console does not auto-refresh every 5 seconds anymore: it waits for your keyboard choice, which avoids input issues and constantly moving output.

In this version, `R` means `Remove a device`. To restart the VPN server, use number `3`, to avoid confusion between restart and remove.

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

Tip: assign a static local IP to the Windows PC in your router, otherwise port-forwarding may break if the local IP changes.



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

## Security

- Never share generated `.conf` files: they contain private keys.
- Prefer a dynamic DNS name instead of copying an IP address everywhere.
- Keep Windows and WireGuard up to date.
- Immediately remove a peer if a phone/device is lost.

## Known limitations

- If your ISP uses CG-NAT, port-forwarding will not work. Solutions: ask for a public/full-stack IPv4, use IPv6, or use a relay/VPS.
- The script configures IPv4. IPv6 is not enabled by default.
- Some third-party antivirus/firewall products may block UDP traffic.
