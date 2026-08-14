#!/usr/bin/env bash
# Android Rust 库构建脚本（修复版）
# 关键修复点：
# 1. 路径必须用 Windows 格式（cargo spawn clang 不做 MSYS 路径转换）
# 2. bindgen 0.59 用 shlex 解析参数，反斜杠会被当转义 → 用正斜杠
# 3. libc++ 头 (c++/v1) 必须排在 C 头文件前面
# 4. 用 CI 的 features (flutter,use_dasp,mediacodec)，不用 hwcodec（Windows host 误编 win.cpp）

set -euo pipefail

export ANDROID_NDK_HOME=/j/codex-work/.toolchains/android-sdk/ndk/26.3.11579264
export PATH="/c/Users/Administrator/.cargo/bin:$PATH"

TRIPLET="$1"   # arm64-android 或 arm-neon-android
RUST_TARGET="$2"  # aarch64-linux-android 或 armv7-linux-androideabi
OUT_ABI="$3"   # arm64-v8a 或 armeabi-v7a

# vcpkg 库根目录按 triplet 区分（各自的 lib/ 里必须含 liblibsodium.a，
# 因为 libsodium-sys 0.2.7 的 build.rs 用 host cfg 判定库名，Windows host
# 下输出 link-lib=libsodium → rustc 找 liblibsodium.a）：
#   arm64    -> .toolchains/vcpkg/installed/arm64-android（完整安装）
#   armv7    -> 项目内 vcpkg_installed/arm-neon-android
case "$TRIPLET" in
  arm64-android|x64-android) VCPKG=/j/codex-work/.toolchains/vcpkg/installed ;;
  arm-neon-android) VCPKG=/j/codex-work/LUODA-v3.0.1/vcpkg_installed ;;
  *) echo "未知 triplet: $TRIPLET" >&2; exit 1 ;;
esac

NDK_PRE_W=$(cygpath -m "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/windows-x86_64")
NDK_SYSROOT_W="$NDK_PRE_W/sysroot"
CLANG_INC_W="$NDK_PRE_W/lib/clang/17/include"
CPPV1_INC_W="$NDK_SYSROOT_W/usr/include/c++/v1"
VCPKG_INC_W=$(cygpath -m "$VCPKG/$TRIPLET/include")
VCPKG_LIB_W=$(cygpath -m "$VCPKG/$TRIPLET/lib")

C_ARGS="--target=${RUST_TARGET}28 --sysroot=$NDK_SYSROOT_W -isystem $CPPV1_INC_W -isystem $NDK_SYSROOT_W/usr/include -isystem $CLANG_INC_W -isystem $VCPKG_INC_W"
CXX_ARGS="$C_ARGS -include cstdint"

FLAG_SUFFIX=$(echo "$RUST_TARGET" | tr -- - _)
export BINDGEN_EXTRA_CLANG_ARGS="$C_ARGS"
export CFLAGS_$FLAG_SUFFIX="$C_ARGS"
export CXXFLAGS_$FLAG_SUFFIX="$CXX_ARGS"
export RUSTFLAGS="-C link-args=-L$VCPKG_LIB_W"
export SODIUM_LIB_DIR="$VCPKG_LIB_W"

echo "=== 构建 $RUST_TARGET ($TRIPLET) -> $OUT_ABI ==="
cd /j/codex-work/LUODA-v3.0.1
cargo ndk --platform 28 --target "$RUST_TARGET" --output-dir "flutter/android/app/src/main/jniLibs/$OUT_ABI" \
  build --release --features flutter,use_dasp,mediacodec 2>&1 | tee "/tmp/cargo_ndk_$OUT_ABI.log"
echo "=== $RUST_TARGET 构建完成: $? ==="
