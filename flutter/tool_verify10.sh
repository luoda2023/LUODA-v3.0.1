#!/usr/bin/env bash
# 10-round verification: analyze + full test suite.
# Usage: bash tool_verify10.sh [round_count] [start_round]
set -u
cd "$(dirname "$0")"
FLUTTER=/j/codex-work/flutter-sdk/flutter/bin/flutter
ROUNDS=${1:-10}
START=${2:-1}
FAIL=0

for ((r = START; r < START + ROUNDS; r++)); do
  echo "========== ROUND $r =========="
  # 1) analyze: project errors must be 0 (settings_ui is a third-party package)
  ERR="$($FLUTTER analyze 2>&1 | grep -c 'error -' || true)"
  SELF_ERR="$($FLUTTER analyze 2>&1 | grep 'error -' | grep -vc 'settings_ui' || true)"
  echo "round $r analyze: total errors=$ERR  project errors=$SELF_ERR"
  if [ "$SELF_ERR" != "0" ]; then
    echo "!!! round $r FAILED analyze (project errors: $SELF_ERR)"
    FAIL=1
  fi
  # 2) full test suite
  RES="$($FLUTTER test 2>&1 | tail -1)"
  echo "round $r test: $RES"
  case "$RES" in
    *"All tests passed"*) ;;
    *) echo "!!! round $r FAILED tests"; FAIL=1 ;;
  esac
done

echo "======================================"
if [ "$FAIL" = "0" ]; then
  echo "ALL $ROUNDS ROUNDS PASSED"
else
  echo "!!! SOME ROUNDS FAILED"
  exit 1
fi
