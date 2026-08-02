#!/usr/bin/env bash

set -euo pipefail

MODE=${MODE:-release}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
JNI_LIBS_DIR="$SCRIPT_DIR/android/app/src/main/jniLibs"

case "$MODE" in
  release)
    CARGO_PROFILE_ARGS=(--release)
    FLUTTER_PROFILE_ARGS=(--obfuscate --split-debug-info ./split-debug-info)
    ;;
  debug)
    CARGO_PROFILE_ARGS=()
    FLUTTER_PROFILE_ARGS=()
    ;;
  *)
    echo "MODE must be either release or debug." >&2
    exit 1
    ;;
esac

if [[ -z "${ANDROID_NDK_HOME:-}" || ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "ANDROID_NDK_HOME must point to an installed Android NDK." >&2
  exit 1
fi

PREBUILT_DIR=$(find "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" -mindepth 1 -maxdepth 1 -type d -print -quit)
if [[ -z "$PREBUILT_DIR" ]]; then
  echo "Android NDK LLVM toolchain was not found." >&2
  exit 1
fi

cd "$PROJECT_ROOT"
cargo ndk --platform 23 --target aarch64-linux-android --bindgen \
  --output-dir "$JNI_LIBS_DIR" build "${CARGO_PROFILE_ARGS[@]}" --features flutter,hwcodec
cargo ndk --platform 23 --target armv7-linux-androideabi --bindgen \
  --output-dir "$JNI_LIBS_DIR" build "${CARGO_PROFILE_ARGS[@]}" --features flutter,hwcodec

cp "$PREBUILT_DIR/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" \
  "$JNI_LIBS_DIR/arm64-v8a/libc++_shared.so"
cp "$PREBUILT_DIR/sysroot/usr/lib/arm-linux-androideabi/libc++_shared.so" \
  "$JNI_LIBS_DIR/armeabi-v7a/libc++_shared.so"

if [[ "$MODE" == "release" ]]; then
  "$PREBUILT_DIR/bin/llvm-strip" "$JNI_LIBS_DIR/arm64-v8a/libluoda.so"
  "$PREBUILT_DIR/bin/llvm-strip" "$JNI_LIBS_DIR/arm64-v8a/libc++_shared.so"
  "$PREBUILT_DIR/bin/llvm-strip" "$JNI_LIBS_DIR/armeabi-v7a/libluoda.so"
  "$PREBUILT_DIR/bin/llvm-strip" "$JNI_LIBS_DIR/armeabi-v7a/libc++_shared.so"
fi

cd "$SCRIPT_DIR"
flutter build apk --target-platform android-arm64,android-arm --"$MODE" \
  "${FLUTTER_PROFILE_ARGS[@]}"
flutter build apk --split-per-abi --target-platform android-arm64,android-arm --"$MODE" \
  "${FLUTTER_PROFILE_ARGS[@]}"
flutter build appbundle --target-platform android-arm64,android-arm --"$MODE" \
  "${FLUTTER_PROFILE_ARGS[@]}"
