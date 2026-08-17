#!/usr/bin/env bash
# 多轮回归验证：模拟 CI 全流程
# 用法: bash tool_verify.sh <轮次号>
set -u
ROUND="${1:-1}"
cd "$(dirname "$0")" || exit 1
FL=/j/codex-work/flutter-sdk/flutter/bin/flutter
ADB=/j/codex-work/.toolchains/android-sdk/platform-tools/adb
echo "========== ROUND $ROUND =========="
echo "--- [1/6] flutter analyze (lib 错误数，期望 0) ---"
"$FL" analyze --no-pub 2>&1 | grep -E " error " | grep -v "packages" > /tmp/an_err.txt || true
LIB_ERR=$(wc -l < /tmp/an_err.txt)
echo "lib errors: $LIB_ERR"
[ "$LIB_ERR" -eq 0 ] || { echo "FAIL: analyze errors"; cat /tmp/an_err.txt; exit 1; }

echo "--- [2/6] flutter test 全量 (期望全部通过) ---"
TEST_OUT=$("$FL" test 2>&1 | tail -1)
echo "$TEST_OUT"
echo "$TEST_OUT" | grep -q "All tests passed" || { echo "FAIL: tests"; exit 1; }

echo "--- [3/6] Windows 增量构建 ---"
taskkill //F //IM LDesk.exe 2>/dev/null
BUILD_OUT=$("$FL" build windows --release 2>&1 | tail -1)
echo "$BUILD_OUT"
echo "$BUILD_OUT" | grep -q "Built" || { echo "FAIL: windows build"; exit 1; }

echo "--- [4/6] Android 增量构建 ---"
BUILD_OUT=$("$FL" build apk --release 2>&1 | tail -1)
echo "$BUILD_OUT"
echo "$BUILD_OUT" | grep -q "Built" || { echo "FAIL: apk build"; exit 1; }

echo "--- [5/6] PC 启动冒烟 ---"
(cd build/windows/x64/runner/Release && ./LDesk.exe >/dev/null 2>&1 &) 
sleep 12
PC_CNT=$(powershell -NoProfile -Command "Get-Process LDesk -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count")
echo "PC processes: $PC_CNT"
[ "${PC_CNT:-0}" -ge 1 ] || { echo "FAIL: pc launch"; exit 1; }

echo "--- [6/6] Android 安装启动 ---"
export MSYS_NO_PATHCONV=1
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk 2>&1 | tail -1 | grep -q Success || { echo "FAIL: apk install"; exit 1; }
"$ADB" shell am start -n com.luoda.remote/.MainActivity >/dev/null 2>&1
sleep 8
PID=$("$ADB" shell pidof com.luoda.remote)
echo "Android pid: ${PID:-none}"
[ -n "$PID" ] || { echo "FAIL: android launch"; exit 1; }
FATAL=$("$ADB" logcat -d 2>/dev/null | grep -cE "FATAL EXCEPTION")
echo "fatal exceptions: $FATAL"
[ "$FATAL" -eq 0 ] || { echo "FAIL: fatal"; exit 1; }

echo "========== ROUND $ROUND PASSED =========="
