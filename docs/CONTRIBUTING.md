# Contributing

Thanks for your interest in WinWG OneClick Server.

## Project status

The project is currently in **beta**. Contributions should focus on reliability, safety, Windows compatibility, documentation, and simple user experience.

## Guidelines

- Keep the project simple: one-click install, one console, clean uninstall.
- Avoid adding external dependencies unless clearly necessary.
- Do not commit generated WireGuard configs, private keys, `.conf`, `.key`, `.psk`, `.env`, or logs containing secrets.
- Prefer Windows PowerShell 5.1 compatibility, because it is available by default on Windows 10/11.
- Keep French and English documentation aligned when changing user-facing behavior.
- Test changes as administrator on Windows when possible.

## Before opening a pull request

Please check:

```text
- install still works
- console opens
- add device works
- remove device works
- service start/stop/restart works
- uninstall still works
- README.md and README.en.md are updated if behavior changed
```

## Coding style

- Use clear PowerShell function names.
- Prefer explicit error messages.
- Avoid hiding important failures; use warnings when an operation partially succeeds.
- Keep user-facing messages understandable for non-experts.
