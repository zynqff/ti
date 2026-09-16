#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA_DIR="$ROOT/.build/llama.cpp"
REPO="https://github.com/chaxu01/llama.cpp.git"
COMMIT="92c448af6"

rm -rf "$LLAMA_DIR"
mkdir -p "$ROOT/.build"
git clone --filter=blob:none "$REPO" "$LLAMA_DIR"
cd "$LLAMA_DIR"
git checkout --detach "$COMMIT"

"$ROOT/Scripts/patch_q2_0c_metal.sh"
