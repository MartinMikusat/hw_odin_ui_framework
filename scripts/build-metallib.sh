#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT=${1:?usage: build-metallib.sh OUTPUT.metallib}
TEMP="${OUTPUT}.air"

if ! xcrun metal -help >/dev/null 2>&1; then
  echo "[hw_odin_ui_framework] Metal shader compiler is unavailable" >&2
  echo "[hw_odin_ui_framework] install it with: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

mkdir -p "$(dirname -- "$OUTPUT")"
xcrun metal -c "$ROOT/shaders/ui.metal" -o "$TEMP"
xcrun metallib "$TEMP" -o "$OUTPUT"
rm -f "$TEMP"
