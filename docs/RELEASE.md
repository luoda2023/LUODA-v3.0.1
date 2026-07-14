# LUODA Release Process

This document describes the release workflow used to publish a tagged LUODA
Remote Desktop release (`v3.0.1` line and forward).

## 1. Version Bump

Apply the version bump consistently across these canonical sources:

| File | Field / Line |
|------|--------------|
| `Cargo.toml` | `version = "X.Y.Z"` |
| `src/version.rs` | `pub const VERSION: &str = "X.Y.Z";` |
| `flutter/pubspec.yaml` | `version: X.Y.Z+N` |
| `flutter/windows/runner/Runner.rc` | `VERSION_AS_STRING "X.Y.Z"` |
| `flutter/macos/Runner/Configs/AppInfo.xcconfig` | `CFBundleShortVersionString` |
| `res/luoda-setup.iss` | `#define MyAppVersion "X.Y.Z"` |
| `res/msi/Package/Package.wixproj` | `<ProductVersion>` |

CI workflows (`build-*.yml`) reference the version inside the_release artifact
names (`LUODA-X.Y.Z-*`). When bumping the version, also search for any hardcoded
`3.0.1` references inside `.github/workflows/` and update them in the same
commit.

## 2. Pre-Release Verification

Before tagging a release, verify:

- `cargo check --all` succeeds locally.
- `cargo clippy --all-targets -- -D warnings` is clean.
- `flutter pub get` and `flutter analyze` in `flutter/` are clean.
- The UI regression contract test in `build-exe.yml` compiles (`flutter_test`
  present in `dev_dependencies`).
- All 8 build workflows are still `active` in GitHub Actions.
- `README.md` highlights section and the artifact table match the new version.
- `CHANGELOG.md` has an entry for the new version.

## 3. Tagging

Tag the release commit with an annotated tag:

```bash
git tag -a vX.Y.Z -m "release(vX.Y.Z): summary"
git push origin-ssh vX.Y.Z
git push origin-ssh v<X.Y.Z-branch>
```

## 4. Build Pipelines

Each `build-*.yml` workflow triggers on:

- `push` to `v<X.Y.Z-branch>` (build only, no release upload)
- `workflow_dispatch` to `v<X.Y.Z-branch>` (build + release upload)

The release upload step is gated by:

```yaml
if: github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/v<X.Y.Z-branch>'
```

This keeps intermediate pushes from polluting the GitHub Release. To publish a
release, dispatch each workflow once the release commit is in place.

## 5. Release Asset Upload

Each workflow uses `softprops/action-gh-release@v2` with:

- `prerelease: false` (we publish as a stable release)
- `draft: true` (the release creator marks it as draft)
- `tag_name: vX.Y.Z` (matches the git tag)
- `files: <path-to-built-artifact>`

The first workflow to upload creates the draft release; subsequent workflows
append their assets to the same draft.

## 6. Publish the Release

After all 8 assets are uploaded:

1. Open GitHub Releases page for the repo.
2. Verify all expected assets are present (MSI / EXE / Client EXE / Sciter /
   APK / DEB / DMG / Web).
3. Verify the release notes reference `CHANGELOG.md` for the version.
4. Click **Publish** to take the release out of draft state.

## 7. Post-Release

- Update `README.md` "Current release" line if it changed.
- Update `CHANGELOG.md` with the release date if added retroactively.
- Confirm the release is visible in `https://github.com/luoda2023/LUODA-v3.0.1/releases/tag/vX.Y.Z`.

## Reference

- Artifacts table: see `README.md` and `CHANGELOG.md`.
- Build workflow audit: see `GITHUB_ACTIONS_GUIDE.md`.
