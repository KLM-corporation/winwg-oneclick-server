# WinWG OneClick Server — Troubleshooting

## 1. The phone does not connect at all

Check:

- The phone is on 4G/5G, not on the local Wi-Fi.
- UDP port-forwarding is configured on the router: `UDP 51820 -> Windows PC local IP`.
- The Windows PC local IP did not change.
- Windows Firewall contains an inbound UDP 51820 rule.
- The WireGuard tunnel is installed as a service.

Useful commands on Windows:

```powershell
Get-NetFirewallRule -DisplayName "WireGuard Server UDP 51820"
Get-NetNat
Get-Service | Where-Object Name -like "WireGuardTunnel*"
```

## 2. The phone connects but Internet does not work

Check Windows NAT:

```powershell
Get-NetNat -Name "WireGuardPhoneServerNAT"
```

If missing:

```powershell
New-NetNat -Name "WireGuardPhoneServerNAT" -InternalIPInterfaceAddressPrefix "10.66.66.0/24"
```

Check IPv4 routing:

```powershell
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name IPEnableRouter
Get-NetIPInterface -AddressFamily IPv4 | Select-Object InterfaceAlias,Forwarding
```

## 3. You may be behind CG-NAT

Symptoms:

- The WAN IP shown by your router is different from the IP shown by `https://ifconfig.me`.
- Port-forwarding looks correct but no packets reach your PC.

Solutions:

- Ask your ISP for a public/full-stack IPv4 address.
- Use IPv6 if available and if you know how to configure it safely.
- Use a VPS/relay WireGuard server.
- Use a mesh VPN solution such as Tailscale or ZeroTier if you accept not using a pure self-hosted WireGuard setup.

## 4. Port testing

WireGuard uses UDP. Many online “open port” testers only test TCP and are unreliable for UDP.

The best test is:

1. enable the tunnel from the phone while on 4G/5G;
2. open `SERVER-CONSOLE.bat` on the Windows PC;
3. check if a recent `latest handshake` appears.

## 5. Dynamic DNS recommended

If your public IP changes, configure a dynamic DNS provider:

- DuckDNS
- No-IP
- Dynu
- Cloudflare with an update script

Then use that hostname as the client endpoint, for example:

```ini
Endpoint = home-vpn.duckdns.org:51820
```

## 6. The monitoring console does not show my phone name

WireGuard itself identifies peers by public key. WinWG OneClick Server maps public keys to names by reading comments in the server config:

```ini
# iphone
[Peer]
PublicKey = ...
```

If the name is missing, check:

```text
C:\ProgramData\WireGuardPhoneServer\server\wg-phone-server.conf
```

## 7. The service is running but I want to stop the VPN temporarily

Use:

```text
WIREGUARD-SERVICE-TOGGLE.bat
```

Choose:

```text
2 - Disable / stop the VPN server
```

This does not delete keys or configurations. You can enable it again later from the same menu.
