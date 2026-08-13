# Security Policy

## Supported status

WinWG OneClick Server is currently in **beta**. It is intended for personal/home-lab use and should be tested carefully before being used on an important machine or network.

## Reporting a vulnerability

If you find a security issue, please do **not** publish exploit details publicly before giving time to fix it.

For now, report issues through GitHub Issues with a clear title such as:

```text
[Security] Short description
```

If the issue contains sensitive details, keep the public issue minimal and ask for a private contact method.

## Security notes

This project configures a VPN server on Windows and may expose a UDP port to the Internet. Users are responsible for:

- keeping Windows and WireGuard up to date;
- protecting generated `.conf` files and private keys;
- removing lost or compromised devices from the peer list;
- understanding router port-forwarding and CG-NAT limitations;
- reviewing generated configurations before sharing or deploying them.

Never commit generated files from:

```text
C:\ProgramData\WireGuardPhoneServer
```

They may contain private keys.
