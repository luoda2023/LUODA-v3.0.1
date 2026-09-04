$env:GRADLE_USER_HOME = "G:\dev\.gradle"
$env:ANDROID_SDK_ROOT = "J:\codex-work\.toolchains\android-sdk"
$env:ANDROID_NDK_HOME = "J:\codex-work\.toolchains\android-sdk\ndk\26.3.11579264"
$env:JAVA_HOME = "J:\codex-work\.toolchains\jdk\jdk-17.0.20+8"
$env:VCPKG_ROOT = "J:\codex-work\.toolchains\vcpkg"
$env:VCPKG_INSTALLED_ROOT = "J:\codex-work\.toolchains\vcpkg\installed"
$env:Path = "J:\codex-work\flutter-sdk\flutter\bin;J:\codex-work\.toolchains\android-sdk\platform-tools;J:\codex-work\.toolchains\jdk\jdk-17.0.20+8\bin;$env:Path"
# 跳过 cargo ndk（已完成），直接 flutter build apk
cd android
flutter build apk --release --target-platform android-arm64,android-arm 2>&1 | Tee-Object -FilePath "J:\codex-work\LUODA-v3.0.1\_android_gradle.log" | Select-Object -Last 20
Write-Output "ANDROID_EXIT=$LASTEXITCODE"
