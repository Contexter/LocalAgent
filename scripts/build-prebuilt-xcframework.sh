#!/usr/bin/env bash
set -euo pipefail

# Produce a local binary .xcframework for the C shim + llama.cpp, so SwiftPM can
# consume it via .binaryTarget(path: "Vendor/LlamaCppCBinary.xcframework").

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
WORK_DIR="$ROOT_DIR/.build-llama"
LLAMA_DIR="$WORK_DIR/llama.cpp"
HEADERS_DIR="$WORK_DIR/headers"
LIB_DIR="$WORK_DIR/lib"
OUT_DIR="$ROOT_DIR/Vendor/LlamaCppCBinary.xcframework"

PINNED_COMMIT="master" # Adjust to a known-good commit for reproducibility

mkdir -p "$WORK_DIR" "$HEADERS_DIR" "$LIB_DIR" "$ROOT_DIR/Vendor"

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

echo "==> Building wrapper static archive"
clang -c -O3 -fPIC "$ROOT_DIR/AgentService/Sources/LlamaCppC/wrap.c" -I"$HEADERS_DIR" -o "$WORK_DIR/wrap.o"
libtool -static -o "$LIB_DIR/libLlamaCppC.a" "$LIB_DIR/libllama.a" "$WORK_DIR/wrap.o"
cp -v "$ROOT_DIR/AgentService/Sources/LlamaCppC/shim.h" "$HEADERS_DIR/"

echo "==> Creating xcframework"
rm -rf "$OUT_DIR"
xcodebuild -create-xcframework \
  -library "$LIB_DIR/libLlamaCppC.a" \
  -headers "$HEADERS_DIR" \
  -output "$OUT_DIR"

echo "Built $OUT_DIR"
