param(
    [ValidateSet("debug", "release")]
    [string]$Mode = "release",
    [ValidateSet("arm64-v8a", "armeabi-v7a")]
    [string[]]$Abi = @("arm64-v8a", "armeabi-v7a")
)

$ErrorActionPreference = "Stop"

$flutterDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $flutterDir
$jniLibsDir = Join-Path $flutterDir "android\app\src\main\jniLibs"

function Resolve-AndroidSdk {
    $candidates = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        (Join-Path $env:LOCALAPPDATA "Android\Sdk")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
    if ($candidates.Count -eq 0) {
        throw "Android SDK not found. Set ANDROID_SDK_ROOT to a valid Android SDK directory."
    }
    return (Resolve-Path -LiteralPath $candidates[0]).Path
}

function Resolve-AndroidNdk([string]$androidSdk) {
    $candidates = @($env:ANDROID_NDK_HOME, $env:ANDROID_NDK_ROOT) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
    if ($candidates.Count -gt 0) {
        return (Resolve-Path -LiteralPath $candidates[0]).Path
    }

    $ndkRoot = Join-Path $androidSdk "ndk"
    if (Test-Path -LiteralPath $ndkRoot -PathType Container) {
        $installed = Get-ChildItem -LiteralPath $ndkRoot -Directory |
            Sort-Object Name -Descending
        if ($installed.Count -gt 0) {
            return $installed[0].FullName
        }
    }
    throw "Android NDK not found. Install NDK 25 or newer, or set ANDROID_NDK_HOME."
}

function Resolve-FlutterCommand {
    $command = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    if ($env:FLUTTER_ROOT) {
        $fromEnvironment = Join-Path $env:FLUTTER_ROOT "bin\flutter.bat"
        if (Test-Path -LiteralPath $fromEnvironment -PathType Leaf) {
            return $fromEnvironment
        }
    }

    $workspaceFlutter = Join-Path (Split-Path -Parent $projectRoot) "flutter-sdk\flutter\bin\flutter.bat"
    if (Test-Path -LiteralPath $workspaceFlutter -PathType Leaf) {
        return $workspaceFlutter
    }
    throw "Flutter SDK not found. Put flutter.bat on PATH or set FLUTTER_ROOT."
}

$androidSdk = Resolve-AndroidSdk
$androidNdk = Resolve-AndroidNdk $androidSdk
$flutterCommand = Resolve-FlutterCommand
$cargo = Get-Command cargo -ErrorAction Stop
$rustup = Get-Command rustup -ErrorAction Stop

& $cargo.Source ndk --version | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "cargo-ndk is required. Install it with: cargo install cargo-ndk"
}

$targets = @{
    "arm64-v8a" = @{
        Rust = "aarch64-linux-android"
        Flutter = "android-arm64"
        Ndk = "aarch64-linux-android"
        Features = "flutter,hwcodec"
    }
    "armeabi-v7a" = @{
        Rust = "armv7-linux-androideabi"
        Flutter = "android-arm"
        Ndk = "arm-linux-androideabi"
        Features = "flutter,hwcodec"
    }
}

$installedTargets = & $rustup.Source target list --installed
$missingTargets = $Abi | Where-Object { $installedTargets -notcontains $targets[$_].Rust }
if ($missingTargets.Count -gt 0) {
    $targetNames = ($missingTargets | ForEach-Object { $targets[$_].Rust }) -join " "
    throw "Missing Rust Android targets: $targetNames. Install them with: rustup target add $targetNames"
}

$env:ANDROID_SDK_ROOT = $androidSdk
$env:ANDROID_NDK_HOME = $androidNdk
$env:ANDROID_NDK_ROOT = $androidNdk

$prebuiltRoot = Join-Path $androidNdk "toolchains\llvm\prebuilt"
$prebuilt = Get-ChildItem -LiteralPath $prebuiltRoot -Directory | Select-Object -First 1
if (-not $prebuilt) {
    throw "Invalid Android NDK: LLVM prebuilt toolchain is missing under $prebuiltRoot"
}

Push-Location $projectRoot
try {
    foreach ($androidAbi in $Abi) {
        $target = $targets[$androidAbi]
        $cargoArgs = @(
            "ndk", "--platform", "23", "--target", $target.Rust,
            "--bindgen", "--output-dir", $jniLibsDir,
            "build", "--features", $target.Features
        )
        if ($Mode -eq "release") { $cargoArgs += "--release" }
        & $cargo.Source @cargoArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Rust Android build failed for $androidAbi."
        }

        $abiOutput = Join-Path $jniLibsDir $androidAbi
        $luodaLibrary = Join-Path $abiOutput "libluoda.so"
        if (-not (Test-Path -LiteralPath $luodaLibrary -PathType Leaf)) {
            throw "Native build completed without producing $luodaLibrary"
        }

        $cppRuntime = Join-Path $prebuilt.FullName "sysroot\usr\lib\$($target.Ndk)\libc++_shared.so"
        if (-not (Test-Path -LiteralPath $cppRuntime -PathType Leaf)) {
            throw "Android C++ runtime not found: $cppRuntime"
        }
        Copy-Item -LiteralPath $cppRuntime -Destination $abiOutput -Force
    }
} finally {
    Pop-Location
}

$flutterTargets = ($Abi | ForEach-Object { $targets[$_].Flutter }) -join ","
$flutterArgs = @("build", "apk", "--target-platform", $flutterTargets, "--$Mode")
if ($Mode -eq "release") {
    $flutterArgs += @("--obfuscate", "--split-debug-info", (Join-Path $flutterDir "split-debug-info"))
}

Push-Location $flutterDir
try {
    & $flutterCommand @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw "Flutter Android packaging failed." }
} finally {
    Pop-Location
}
