# LUODA Remote Desktop

A self-hosted remote desktop application built with Rust, providing secure and efficient remote access solution.

## Version

Current release: **v3.0.1**

Highlights in 3.0.1:

- Refreshed desktop UI (Flutter) with brand-aligned LUODA remote assistance title and centered profile avatar
- Direct IP access hardening across platforms (Windows / macOS / Linux)
- UPnP mapping state typed explicitly to keep long-running sessions stable
- Flutter 3.24 Web compatibility restored for portable builds
- Build pipeline artifacts renamed to `LUODA-3.0.1-*` and aligned with release asset names (MSI / EXE / APK / DEB / RPM / DMG / Web / Sciter)

Build product names:

| Platform | Artifact |
|----------|----------|
| Windows MSI | `LUODA-3.0.1-Setup.msi` |
| Windows Portable x64 | `LUODA-3.0.1-portable-x64.exe` |
| Windows Client x64 | `LUODA-3.0.1-Client-x64.exe` |
| Windows Sciter x86 | `LUODA-3.0.1-portable-x86-sciter.exe` |
| Android Universal | `LUODA-3.0.1-universal.apk` |
| Linux DEB / RPM | `LUODA-3.0.1.deb` / `LUODA-3.0.1.rpm` |
| macOS DMG | `LUODA-3.0.1.dmg` |
| Web | `LUODA-3.0.1-web.tar.gz` |

See [CHANGELOG.md](CHANGELOG.md) for the per-release change history
and [docs/RELEASE.md](docs/RELEASE.md) for the full release process.

## Features

- Self-hosted server for complete data control
- Cross-platform support (Windows, macOS, Linux, Android, iOS)
- High performance with low latency
- End-to-end encryption
- File transfer and clipboard sharing
- Multi-monitor support

## Website

https://dicad.cn

## License

AGPL-3.0
