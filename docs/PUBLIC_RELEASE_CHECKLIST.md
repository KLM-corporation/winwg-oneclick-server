# Public release checklist

Use this checklist before making the repository public or publishing a release.

## Required

- [ ] Revoke any GitHub token that was shared during development.
- [ ] Confirm the repository contains no generated `.conf`, `.key`, `.psk`, `.env`, or private logs.
- [ ] Test installation on a clean Windows 10 or Windows 11 machine.
- [ ] Test `SERVER-CONSOLE.bat` as administrator.
- [ ] Test adding a device from the console.
- [ ] Test removing a device from the console.
- [ ] Test service stop/start/restart from the console.
- [ ] Test one-click uninstall.
- [ ] Confirm README.md and README.en.md are aligned.
- [ ] Confirm docs/SECURITY.md and docs/CONTRIBUTING.md are present.
- [ ] Create a beta release tag, for example `v0.1.0-beta`.

## Recommended

- [ ] Add screenshots of the unified console.
- [ ] Add a short demo GIF or video.
- [ ] Test on PowerShell 5.1 and PowerShell 7.
- [ ] Test with UPnP enabled and disabled.
- [ ] Test behind a router with manual UDP forwarding.
- [ ] Document known antivirus/firewall conflicts if discovered.

## GitHub settings before public

- [ ] Keep the repository private until the checklist is done.
- [ ] Delete stale test branches if they are no longer useful.
- [ ] Set repository description:

```text
One script, one click: turn a Windows PC into a WireGuard remote access server.
```

- [ ] Add topics, for example:

```text
wireguard windows vpn powershell remote-access oneclick home-server
```
