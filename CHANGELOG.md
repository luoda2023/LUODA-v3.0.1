# Changelog

All notable changes to **LUODA Remote Desktop** are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.1] - 2026-07-14

### Highlights

The 3.0.1 release refreshes the desktop UI, hardens direct-IP access across
platforms, restores Flutter 3.24 web compatibility, and aligns the entire
build pipeline with the `LUODA-3.0.1-*` artifact naming scheme.

### Added

- Refreshed Flutter desktop UI with brand-aligned "LUODA 远程协助" title and centered profile avatar.
- Login and download buttons now stack icon above text for a cleaner visual hierarchy.
- CHANGELOG.md to track release history going forward.
- Copyright banner updated to `2025-2026 LUODA` in README, LICENSE headers, `res/luoda-setup.iss`, `flutter/windows/runner/Runner.rc`, and `src/version.rs`.

### Changed

- Version bump `2.0.1 -> 3.0.1` applied across:
  - `Cargo.toml`, `Cargo.lock`, `src/version.rs`
  - `libs/portable/Cargo.toml`, `build.rs`
  - `flutter/pubspec.yaml`, `flutter/pubspec.lock`, `flutter/local.properties`
  - `flutter/windows/runner/Runner.rc`, `flutter/macos/Runner/Configs/AppInfo.xcconfig`
  - `res/luoda-setup.iss`, `res/msi/Package/Package.wixproj`
- Repository URL alignment: `luoda2023/LUODA-RemoteDesktop` -> `luoda2023/LUODA-v3.0.1` in:
  - `ci_auto_heal.py`, `push-changes.sh`
  - `GITHUB_ACTIONS_GUIDE.md`, `res/msi/preprocess.py`
  - `libs/hbb_common/Cargo.toml` comment, `flutter/android/app/build.gradle.kts` comment
- CI workflow artifacts renamed to `LUODA-3.0.1-*` across all 8 `build-*.yml` workflows (MSI / EXE / Client EXE / Sciter / APK / DEB / DMG / Web). The Sciter workflow stays `workflow_dispatch`-only and does NOT upload to the public v3.0.1 release.
- `.gitignore` now excludes `artifacts/` and `_archive/` with BOM-consistent entries.

### Fixed

- Hardened direct IP access on Windows, macOS, and Linux (VPS without display, speed optimizations).
- UPnP mapping state now typed explicitly to keep long-running sessions stable.
- Restored Flutter 3.24 web compatibility for portable builds.
- `flutter_test` enabled in `dev_dependencies` so the UI regression contract test compiles.
- `flutter pub get` now runs before the UI regression test in the Windows EXE workflow; `--no-pub` flag removed to avoid stale dependency state.

### Infrastructure

- 8 GitHub Actions workflows (`build-apk.yml`, `build-client-exe.yml`, `build-deb.yml`, `build-dmg.yml`, `build-exe.yml`, `build-msi.yml`, `build-sciter.yml`, `build-web.yml`) all trigger on `push` to `v3.0.1` and on `workflow_dispatch`, with release asset upload gated on `push || workflow_dispatch` on the `v3.0.1` branch (`matrix.arch == 'x64'` additionally gates the multi-arch `build-exe.yml` and `build-client-exe.yml` to avoid duplicate uploads from x86 matrix variants).
- UTF-8 BOM preserved on `CHANGELOG.md`, `README.md`, and `docs/RELEASE.md` to match the existing v3.0.1 documentation set.
- Documentation realignment: `docs/RELEASE.md` and `CI_GUIDE.md` now describe the actual GitHub Actions trigger/release-upload gates (`push` and `workflow_dispatch` both upload; multi-arch workflows gated on `matrix.arch == 'x64'`) and the dynamic MSI version injection path via `res/msi/preprocess.py` (the previously listed `<ProductVersion>` in `Package.wixproj` does not exist).

### Release Artifacts

| Platform | Artifact |
|----------|----------|
| Windows MSI | `LUODA-3.0.1-Setup.msi` |
| Windows Portable x64 | `LUODA-3.0.1-portable-x64.exe` |
| Windows Client x64 | `LUODA-3.0.1-Client-x64.exe` |
| Android arm64-v8a | `LUODA-3.0.1-arm64-v8a.apk` |
| Android armeabi-v7a | `LUODA-3.0.1-armeabi-v7a-release.apk` |
| Android x86_64 | `LUODA-3.0.1-x86_64.apk` |
| Android Universal | `LUODA-3.0.1-universal.apk` |
| Linux DEB | `LUODA-3.0.1.deb` |
| Linux RPM | `LUODA-3.0.1.rpm` |
| macOS DMG | `LUODA-3.0.1.dmg` |
| Web | `LUODA-3.0.1-web.tar.gz` |

## Pre-3.0.1 History

Versions before 3.0.1 were tracked in the legacy `luoda2023/LUODA-RemoteDesktop`
repository (`v2.0.1` and earlier). The `v3.0.1` line moves development to
`luoda2023/LUODA-v3.0.1` and supersedes the previous release channel.
