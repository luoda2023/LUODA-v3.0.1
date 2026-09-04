$ErrorActionPreference = "Continue"
$projectRoot = "J:\codex-work\LUODA-v3.0.1"
$jniLibsDir = Join-Path $projectRoot "flutter\android\app\src\main\jniLibs"
$toolchains = "J:\codex-work\.toolchains"
$androidNdk = Join-Path $toolchains "android-sdk\ndk\26.3.11579264"
$vcpkgRoot = Join-Path $toolchains "vcpkg"
$env:CARGO_HOME = Join-Path $toolchains "cargo"
$env:RUSTUP_HOME = Join-Path $toolchains "rustup"
$env:PATH = "$(Join-Path $env:CARGO_HOME 'bin');$env:PATH"
$env:VCPKG_ROOT = $vcpkgRoot
$env:ANDROID_SDK_ROOT = Join-Path $toolchains "android-sdk"
$env:ANDROID_HOME = Join-Path $toolchains "android-sdk"
$env:ANDROID_NDK_HOME = $androidNdk
$env:ANDROID_NDK_ROOT = $androidNdk
$prebuilt = Get-ChildItem (Join-Path $androidNdk "toolchains\llvm\prebuilt") -Directory | Select-Object -First 1
$bindgenSysroot = (Join-Path $prebuilt.FullName "sysroot").Replace('\','/')
$bindgenResourceDir = (Get-ChildItem (Join-Path $prebuilt.FullName "lib\clang") -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName.Replace('\','/')
$triplet = "x64-android"
$env:VCPKG_INSTALLED_ROOT = Join-Path $vcpkgRoot "installed\$triplet"
$stageDir = Join-Path $projectRoot "target\cargo-ndk\libsodium\$triplet\release"
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
$src = Join-Path $env:VCPKG_INSTALLED_ROOT "lib\libsodium.a"
if (Test-Path -LiteralPath (Join-Path $stageDir "liblibsodium.a")) { Remove-Item -LiteralPath (Join-Path $stageDir "liblibsodium.a") -Force }
Copy-Item -LiteralPath $src -Destination (Join-Path $stageDir "liblibsodium.a") -Force
$env:SODIUM_LIB_DIR = $stageDir
$env:BINDGEN_EXTRA_CLANG_ARGS = "--sysroot=$bindgenSysroot --target=x86_64-linux-android23 -resource-dir=$bindgenResourceDir -D__ANDROID_API__=23"
$cargoExe = (Get-Command cargo).Source
Write-Output "using cargo: $cargoExe"
$args = @("ndk","--platform","23","--target","x86_64-linux-android","--output-dir",$jniLibsDir,"build","--lib","--features","flutter,use_dasp,mediacodec","--release")
& $cargoExe @args 2>&1 | Select-Object -Last 6
Write-Output "CARGO_X64=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) { exit 1 }
$cpp = Join-Path $prebuilt.FullName "sysroot\usr\lib\x86_64-linux-android\libc++_shared.so"
Copy-Item -LiteralPath $cpp -Destination (Join-Path $jniLibsDir "x86_64") -Force
Write-Output "OK x86_64 libc++ copied"
