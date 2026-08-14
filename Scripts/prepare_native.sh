#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_DIR="$ROOT/VibeTalkAudioLab/Resources/Models"
mkdir -p "$MODEL_DIR"

echo "=== VibeTalk Audio Lab native preparation ==="
test -f "$MODEL_DIR/dtln2.onnx" || { echo "ERROR: dtln2.onnx is missing"; exit 1; }
test -f "$MODEL_DIR/dtln1.onnx" || {
  echo "ERROR: dtln1.onnx is missing."
  echo "Add your matching DTLN stage-1 ONNX file to VibeTalkAudioLab/Resources/Models/ and rerun the build."
  exit 1
}

echo "DTLN stage 1: $MODEL_DIR/dtln1.onnx"
echo "DTLN stage 2: $MODEL_DIR/dtln2.onnx"
ls -lh "$MODEL_DIR/dtln1.onnx" "$MODEL_DIR/dtln2.onnx"

# RNNoise model data is still generated automatically if the source tree does
# not already contain it. This is the only model download allowed by the build.
if [ ! -f "$ROOT/VibeTalkAudioLab/DSP/RNNoise/rnnoise_data.c" ] || [ ! -f "$ROOT/VibeTalkAudioLab/DSP/RNNoise/rnnoise_data.h" ]; then
  TMP_RN="$(mktemp -d)"
  trap 'rm -rf "$TMP_RN"' EXIT
  git clone --depth 1 https://github.com/xiph/rnnoise.git "$TMP_RN/rnnoise"
  cd "$TMP_RN/rnnoise"
  ./download_model.sh
  cp src/rnnoise_data.c src/rnnoise_data.h "$ROOT/VibeTalkAudioLab/DSP/RNNoise/"
fi

# Build the existing DeepFilterNet3 native bridge.
if [ -f "$ROOT/DeepFilterBridges/Cargo.toml" ]; then
  if ! command -v rustup >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    source "$HOME/.cargo/env"
  fi
  export PATH="$HOME/.cargo/bin:$PATH"
  rustup target add aarch64-apple-ios
  cd "$ROOT/DeepFilterBridges"
  export CARGO_NET_GIT_FETCH_WITH_CLI=true
  cargo build --release --target aarch64-apple-ios
  cd "$ROOT"
  mkdir -p Vendor/DeepFilter
  cp DeepFilterBridges/target/aarch64-apple-ios/release/libvibetalk_df_bridge.a Vendor/DeepFilter/
fi

echo "Native preparation complete."
