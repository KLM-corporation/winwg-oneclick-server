# Changelog

## v0.3.0-beta - 2026-08-15

Beta release focused on diagnostics, IPv6 direct endpoint fallback, and safer public packaging.

### Added

- Health check from the server console.
- Port-forwarding status tracking in `settings/port-forwarding.json`.
- UPnP / PCP / NAT-PMP diagnostic helper with `DEBUG-UPNP.bat`.
- IPv6 direct endpoint fallback when automatic IPv4 port forwarding fails.
- Console option to switch device endpoints between IPv4/DNS and direct IPv6.
- Warnings that direct IPv6 may still require an IPv6 firewall rule on the router/box.
- Preference for stable IPv6 addresses instead of temporary privacy IPv6 addresses when possible.

### Fixed

- QR payload line endings for better WireGuard mobile import compatibility.
- French language string quoting that could break scripts using `WinWG-Language.ps1`.

### Notes

The experimental graphical interface is not included in this release. It remains outside `main`.

## v0.2.0-beta

Public beta with renamed project identity, unified console, device terminology, QR improvements, temporary devices, public docs, and release ZIP packaging.

## v0.1.0-beta

Initial public beta preparation.

### Added

- One-click Windows installer.
- Clean one-click uninstaller.
- Unified server console.
- Service start/stop/restart from the console.
- Add/remove device from the console.
- Ultra verbose diagnostic mode and log file.
- French and English documentation.
- Troubleshooting guides.
- Security and contribution documentation.

### Notes

This is a beta release. Test carefully before using it on an important machine or network.
