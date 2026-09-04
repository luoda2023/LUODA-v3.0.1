$ErrorActionPreference = "Stop"
$projectRoot = "J:\codex-work\LUODA-v3.0.1"
$env:ANDROID_SDK_ROOT = "J:\codex-work\.toolchains\android-sdk"
$env:ANDROID_HOME = "J:\codex-work\.toolchains\android-sdk"
$env:ANDROID_NDK_HOME = "J:\codex-work\.toolchains\android-sdk\ndk\26.3.11579264"
$env:ANDROID_NDK_ROOT = "J:\codex-work\.toolchains\android-sdk\ndk\26.3.11579264"
$env:JAVA_HOME = "J:\codex-work\.toolchains\jdk\jdk-17.0.20+8"
$env:VCPKG_ROOT = "J:\codex-work\.toolchains\vcpkg"
$env:PATH = "G:\dev\.cargo\bin;J:\codex-work\.toolchains\android-sdk\platform-tools;$env:PATH"
$prebuilt = "J:\codex-work\.toolchains\android-sdk\ndk\26.3.11579264\toolchains\llvm\prebuilt\windows-x86_64"
$bindgenSysroot = "$prebuilt\sysroot".Replace('\','/')
$bindgenResourceDir = "$prebuilt\lib\clang\17\include".Replace('\','/')
$jniLibs = "$projectRoot\flutter\android\app\src\main\jniLibs"
Push-Location $projectRoot
foreach ($abi in @("arm64-v8a","x86_64")) {
    if ($abi -eq "arm64-v8a") { $rust="aarch64-linux-android"; $bindgen="aarch64-linux-android"; $triplet="arm64-android"; }
    else { $rust="x86_64-linux-android"; $bindgen="x86_64-linux-android"; $triplet="x64-android"; }
    $env:SODIUM_LIB_DIR = "J:\codex-work\.toolchains\vcpkg\installed\$triplet\lib"
    $env:VCPKG_INSTALLED_ROOT = "J:\codex-work\.toolchains\vcpkg\installed\$triplet"
    $env:BINDGEN_EXTRA_CLANG_ARGS = "--sysroot=$bindgenSysroot --target=$bindgen -resource-dir=$bindgenResourceDir -D__ANDROID_API__=23"
    Write-Output "=== cargo ndk $abi ==="
    cargo ndk --platform 23 --target $rust --output-dir $jniLibs build --lib --release --features flutter,use_dasp,mediacodec 2>&1 | Select-Object -Last 8
    Write-Output "CARGO_$abi=$LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) { exit 1 }
}
Pop-Location
Write-Output "ALL_CARGO_DONE"
