param(
    [ValidateSet("debug", "release")]
    [string]$Mode = "release",
    [ValidateSet("arm64-v8a", "armeabi-v7a", "x86_64")]
    [string[]]$Abi = @("arm64-v8a", "armeabi-v7a", "x86_64")
)

$ErrorActionPreference = "Stop"

$flutterDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $flutterDir
$jniLibsDir = Join-Path $flutterDir "android\app\src\main\jniLibs"

function Resolve-AndroidSdk {
    $candidates = @(
        @(
            $env:ANDROID_SDK_ROOT,
            $env:ANDROID_HOME,
            (Join-Path (Split-Path -Parent $projectRoot) ".toolchains\android-sdk"),
            (Join-Path $env:LOCALAPPDATA "Android\Sdk")
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
    )
    if ($candidates.Count -eq 0) {
        throw "Android SDK not found. Set ANDROID_SDK_ROOT to a valid Android SDK directory."
    }
    return (Resolve-Path -LiteralPath $candidates[0]).Path
}

function Resolve-AndroidNdk([string]$androidSdk) {
    $candidates = @(
        @($env:ANDROID_NDK_HOME, $env:ANDROID_NDK_ROOT) |
            Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
    )
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

function Resolve-JavaHome {
    $workspaceJdkRoot = Join-Path (Split-Path -Parent $projectRoot) ".toolchains\jdk"
    $workspaceCandidates = @()
    if (Test-Path -LiteralPath $workspaceJdkRoot -PathType Container) {
        $workspaceCandidates = @(
            Get-ChildItem -LiteralPath $workspaceJdkRoot -Directory |
            Where-Object {
                Test-Path -LiteralPath (Join-Path $_.FullName "bin\java.exe") -PathType Leaf
            } |
            Sort-Object Name -Descending
        )
    }
    $candidates = @(
        @($workspaceCandidates + @($env:JAVA_HOME)) |
            Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate "bin\java.exe") -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Java JDK not found. Set JAVA_HOME to a valid JDK 17 directory."
}

function Resolve-VcpkgRoot {
    $vcpkgCandidates = @(
        @(
            $env:VCPKG_ROOT,
            (Join-Path (Split-Path -Parent $projectRoot) ".toolchains\vcpkg")
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
    )
    foreach ($candidate in $vcpkgCandidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate "vcpkg.exe") -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "vcpkg not found. Set VCPKG_ROOT to a bootstrapped vcpkg directory."
}

function Resolve-AndroidSodiumLibDir([string]$androidAbi, [string]$mode) {
    $triplets = @{
        "arm64-v8a" = "arm64-android"
        "armeabi-v7a" = "arm-neon-android"
        "x86_64" = "x64-android"
    }
    $triplet = $triplets[$androidAbi]
    $configuration = if ($mode -eq "debug") { "debug\lib" } else { "lib" }
    $roots = @()
    if ($env:VCPKG_INSTALLED_ROOT) {
        $roots += $env:VCPKG_INSTALLED_ROOT
    }
    if ($env:VCPKG_ROOT) {
        $roots += Join-Path $env:VCPKG_ROOT "installed"
    }
    $roots += Join-Path (Split-Path -Parent $projectRoot) ".toolchains\vcpkg-installed"
    $roots += Join-Path $projectRoot "vcpkg_installed"

    foreach ($root in $roots) {
        $libDir = Join-Path $root "$triplet\$configuration"
        $sourceLibrary = Join-Path $libDir "libsodium.a"
        if (Test-Path -LiteralPath $sourceLibrary -PathType Leaf) {
            $stagingDir = Join-Path $projectRoot "target\cargo-ndk\libsodium\$triplet\$mode"
            New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
            Copy-Item -LiteralPath $sourceLibrary `
                -Destination (Join-Path $stagingDir "liblibsodium.a") -Force
            return (Resolve-Path -LiteralPath $stagingDir).Path
        }
    }

    throw "Android libsodium not found for $androidAbi ($mode). Install the $triplet vcpkg triplet or set VCPKG_INSTALLED_ROOT."
}

$androidSdk = Resolve-AndroidSdk
$androidNdk = Resolve-AndroidNdk $androidSdk
$flutterCommand = Resolve-FlutterCommand
$env:JAVA_HOME = Resolve-JavaHome
$env:PATH = "$(Join-Path $env:JAVA_HOME 'bin');$env:PATH"
$workspaceToolchains = Join-Path (Split-Path -Parent $projectRoot) ".toolchains"
$workspaceCargoHome = Join-Path $workspaceToolchains "cargo"
$workspaceRustupHome = Join-Path $workspaceToolchains "rustup"
if (Test-Path -LiteralPath $workspaceCargoHome -PathType Container) {
    $env:CARGO_HOME = $workspaceCargoHome
    $env:PATH = "$(Join-Path $workspaceCargoHome 'bin');$env:PATH"
}
if (Test-Path -LiteralPath $workspaceRustupHome -PathType Container) {
    $env:RUSTUP_HOME = $workspaceRustupHome
}
$env:VCPKG_ROOT = Resolve-VcpkgRoot
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
        Bindgen = "aarch64-linux-android"
        Triplet = "arm64-android"
        Features = "flutter,use_dasp,mediacodec"
    }
    "armeabi-v7a" = @{
        Rust = "armv7-linux-androideabi"
        Flutter = "android-arm"
        Ndk = "arm-linux-androideabi"
        Bindgen = "armv7a-linux-androideabi"
        Triplet = "arm-neon-android"
        Features = "flutter,use_dasp,mediacodec"
    }
    "x86_64" = @{
        Rust = "x86_64-linux-android"
        Flutter = "android-x64"
        Ndk = "x86_64-linux-android"
        Bindgen = "x86_64-linux-android"
        Triplet = "x64-android"
        Features = "flutter,use_dasp,mediacodec"
    }
}

$installedTargets = & $rustup.Source target list --installed
$missingTargets = $Abi | Where-Object { $installedTargets -notcontains $targets[$_].Rust }
if ($missingTargets.Count -gt 0) {
    $targetNames = ($missingTargets | ForEach-Object { $targets[$_].Rust }) -join " "
    throw "Missing Rust Android targets: $targetNames. Install them with: rustup target add $targetNames"
}

$env:ANDROID_SDK_ROOT = $androidSdk
$env:ANDROID_HOME = $androidSdk
$env:ANDROID_NDK_HOME = $androidNdk
$env:ANDROID_NDK_ROOT = $androidNdk

$prebuiltRoot = Join-Path $androidNdk "toolchains\llvm\prebuilt"
$prebuilt = Get-ChildItem -LiteralPath $prebuiltRoot -Directory | Select-Object -First 1
if (-not $prebuilt) {
    throw "Invalid Android NDK: LLVM prebuilt toolchain is missing under $prebuiltRoot"
}
$bindgenSysroot = (Join-Path $prebuilt.FullName "sysroot").Replace('\', '/')
$bindgenResourceDir = Get-ChildItem -LiteralPath (Join-Path $prebuilt.FullName "lib\clang") -Directory |
    Sort-Object Name -Descending |
    Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName "include\stddef.h") -PathType Leaf
    } |
    Select-Object -First 1
if (-not $bindgenResourceDir) {
    throw "Invalid Android NDK: Clang resource headers are missing."
}
$bindgenResourceDir = $bindgenResourceDir.FullName.Replace('\', '/')

Push-Location $projectRoot
try {
    foreach ($androidAbi in $Abi) {
        $target = $targets[$androidAbi]
        $env:SODIUM_LIB_DIR = Resolve-AndroidSodiumLibDir $androidAbi $Mode
        $toolchainInstalled = Join-Path $env:VCPKG_ROOT "installed\$($target.Triplet)"
$repoInstalled = Join-Path $projectRoot "vcpkg_installed\$($target.Triplet)"
if (Test-Path -LiteralPath $toolchainInstalled) {
    $env:VCPKG_INSTALLED_ROOT = $toolchainInstalled
} elseif (Test-Path -LiteralPath $repoInstalled) {
    $env:VCPKG_INSTALLED_ROOT = $repoInstalled
} else {
    $env:VCPKG_INSTALLED_ROOT = $toolchainInstalled
}
        $env:BINDGEN_EXTRA_CLANG_ARGS = "--sysroot=$bindgenSysroot --target=$($target.Bindgen)23 -resource-dir=$bindgenResourceDir -D__ANDROID_API__=23"
        $cargoArgs = @(
            "ndk", "--platform", "23", "--target", $target.Rust,
            "--output-dir", $jniLibsDir,
            "build", "--lib", "--features", $target.Features
        )
        if ($Mode -eq "release") { $cargoArgs += "--release" }
        $eap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & $cargo.Source @cargoArgs 2>&1 | ForEach-Object { Write-Host $_ }
        $ErrorActionPreference = $eap
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

$env:LUODA_ANDROID_ABIS = $Abi -join ","
$flutterTargets = ($Abi | ForEach-Object { $targets[$_].Flutter }) -join ","
$flutterArgs = @("build", "apk", "--no-pub", "--target-platform", $flutterTargets, "--$Mode")
if ($Mode -eq "release") {
    $flutterArgs += @("--obfuscate", "--split-debug-info", (Join-Path $flutterDir "split-debug-info"))
}

$flutterAppData = Join-Path $projectRoot ".runtime\flutter-appdata"
New-Item -ItemType Directory -Path $flutterAppData -Force | Out-Null
$env:APPDATA = $flutterAppData
$gradleUserHome = Join-Path $projectRoot ".runtime\gradle-home"
New-Item -ItemType Directory -Path $gradleUserHome -Force | Out-Null
$env:GRADLE_USER_HOME = $gradleUserHome

Push-Location $flutterDir
try {
    $eap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $flutterCommand @flutterArgs 2>&1 | ForEach-Object { Write-Host $_ }
    $ErrorActionPreference = $eap
    if ($LASTEXITCODE -ne 0) { throw "Flutter Android packaging failed." }
} finally {
    Pop-Location
}
