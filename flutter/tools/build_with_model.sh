#!/usr/bin/env bash
# ============================================================================
# 构建脚本：支持含模型/不含模型两个版本
#
# 用法:
#   ./tools/build_with_model.sh with-model [flutter build args...]
#   ./tools/build_with_model.sh without-model [flutter build args...]
#
# 示例:
#   ./tools/build_with_model.sh with-model apk --release
#   ./tools/build_with_model.sh without-model windows --release
#
# 首次构建含模型版本前，请先将模型文件放入 assets/tts_models/vits-zh-ll/
# （参见 assets/tts_models/README.md）
# ============================================================================

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
MODEL_ASSET_DIR="$PROJECT_DIR/assets/tts_models/vits-zh-ll"
PUBSPEC="$PROJECT_DIR/pubspec.yaml"

# 备份原始 pubspec.yaml
backup_pubspec() {
  cp "$PUBSPEC" "$PUBSPEC.bak"
}

# 恢复原始 pubspec.yaml
restore_pubspec() {
  if [[ -f "$PUBSPEC.bak" ]]; then
    mv "$PUBSPEC.bak" "$PUBSPEC"
  fi
}

# 确保退出时恢复 pubspec.yaml
trap restore_pubspec EXIT

# 检查模型文件是否存在
check_model_files() {
  local missing=0
  for f in model.onnx tokens.txt lexicon.txt date.fst number.fst phone.fst new_heteronym.fst; do
    if [[ ! -f "$MODEL_ASSET_DIR/$f" ]]; then
      echo "❌ 缺少模型文件: $f" >&2
      missing=1
    fi
  done
  for f in jieba.dict.utf8 hmm_model.utf8 idf.utf8 stop_words.utf8 user.dict.utf8; do
    if [[ ! -f "$MODEL_ASSET_DIR/dict/$f" ]]; then
      echo "❌ 缺少字典文件: dict/$f" >&2
      missing=1
    fi
  done
  return $missing
}

# 解析参数
VARIANT="${1:-without-model}"
shift || true

cd "$PROJECT_DIR"

case "$VARIANT" in
  with-model)
    echo "📦 构建含模型版本..."
    if ! check_model_files; then
      echo "" >&2
      echo "请先将模型文件放入: $MODEL_ASSET_DIR/" >&2
      echo "参见: assets/tts_models/README.md" >&2
      exit 1
    fi
    echo "✅ 模型文件检查通过"
    echo "🔧 启用 BUNDLE_TTS_MODEL=true"
    exec flutter build "$@" --dart-define=BUNDLE_TTS_MODEL=true
    ;;
  without-model)
    echo "📦 构建不含模型版本（用户需自行下载模型）"
    echo "🔧 BUNDLE_TTS_MODEL 默认为 false"
    exec flutter build "$@"
    ;;
  *)
    echo "用法: $0 [with-model|without-model] [flutter build args...]" >&2
    exit 1
    ;;
esac
