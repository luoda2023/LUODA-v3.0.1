$env:ANDROID_SDK_ROOT = "J:\codex-work\.toolchains\android-sdk"
$env:ANDROID_NDK_HOME = "J:\codex-work\.toolchains\android-sdk\ndk\26.3.11579264"
$env:JAVA_HOME = "J:\codex-work\.toolchains\jdk\jdk-17.0.20+8"
$env:VCPKG_ROOT = "J:\codex-work\.toolchains\vcpkg"
$env:VCPKG_INSTALLED_ROOT = "J:\codex-work\.toolchains\vcpkg\installed"
$env:Path = "J:\codex-work\flutter-sdk\flutter\bin;J:\codex-work\.toolchains\android-sdk\platform-tools;J:\codex-work\.toolchains\jdk\jdk-17.0.20+8\bin;$env:Path"
& .\build_android.ps1 -Mode release -Abi @("arm64-v8a", "armeabi-v7a") 2>&1 | Tee-Object -FilePath "J:\codex-work\LUODA-v3.0.1\_android_build.log" | Select-Object -Last 20
Write-Output "ANDROID_EXIT=$LASTEXITCODE"
