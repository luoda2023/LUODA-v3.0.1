#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
cd "$PROJECT_ROOT"
cargo ndk --platform 23 --target aarch64-linux-android --bindgen \
  --output-dir "$SCRIPT_DIR/android/app/src/main/jniLibs" \
  build --release --features flutter,hwcodec
