#!/usr/bin/env bash
set -euo pipefail

# Build static libllama.a, wrap it with our C shim, and link AgentService statically to libllama.

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
WORK_DIR="$ROOT_DIR/.build-llama"
LLAMA_DIR="$WORK_DIR/llama.cpp"
HEADERS_DIR="$WORK_DIR/headers"
LIB_DIR="$WORK_DIR/lib"

PINNED_COMMIT="master" # Adjust to a known good commit for stability

mkdir -p "$WORK_DIR" "$HEADERS_DIR" "$LIB_DIR"

echo "==> Cloning llama.cpp ($PINNED_COMMIT)"
if [ ! -d "$LLAMA_DIR" ]; then
  git clone https://github.com/ggerganov/llama.cpp "$LLAMA_DIR"
fi
pushd "$LLAMA_DIR" >/dev/null
git fetch --all
git checkout "$PINNED_COMMIT"

echo "==> Building libllama.a (Metal enabled)"
make clean || true
LLAMA_METAL=1 make -j
cp -v libllama.a "$LIB_DIR/"
cp -v llama.h "$HEADERS_DIR/"
popd >/dev/null

echo "==> Building shim wrapper archive"
clang -c -O3 -fPIC "$ROOT_DIR/Sources/LlamaCppC/wrap.c" -I"$HEADERS_DIR" -o "$WORK_DIR/wrap.o"
libtool -static -o "$LIB_DIR/libLlamaCppC.a" "$LIB_DIR/libllama.a" "$WORK_DIR/wrap.o"
cp -v "$ROOT_DIR/Sources/LlamaCppC/shim.h" "$HEADERS_DIR/"

echo "==> Linking AgentService with static libLlamaCppC.a"
swift build -c release --package-path "$ROOT_DIR"/AgentService \
  -Xcc -I"$HEADERS_DIR" \
  -Xlinker -L"$LIB_DIR" \
  -Xlinker -lLlamaCppC \
  -Xlinker -dead_strip

BIN_DIR=$(swift build -c release --package-path "$ROOT_DIR"/AgentService --show-bin-path)
echo "Built AgentService at $BIN_DIR/AgentService"

