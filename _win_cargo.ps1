$env:VCPKG_ROOT = "J:\codex-work\.toolchains\vcpkg"
$env:VCPKG_INSTALLED_ROOT = "J:\codex-work\.toolchains\vcpkg\installed\x64-windows-static"
cargo build --release --features flutter 2>&1 | Tee-Object -FilePath "J:\codex-work\LUODA-v3.0.1\_win_cargo2.log" | Select-Object -Last 8
Write-Output "CARGO_EXIT=$LASTEXITCODE"
