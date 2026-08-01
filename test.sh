#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMP="$ROOT/build/test"
mkdir -p "$TEMP"
cd "$TEMP"

odin test "$ROOT/draw" -collection:ui_framework="$ROOT" -no-threaded-checker
odin test "$ROOT/core" -collection:ui_framework="$ROOT" -no-threaded-checker
odin test "$ROOT/diagnostics" -collection:ui_framework="$ROOT" -no-threaded-checker
odin test "$ROOT/coretext" -collection:ui_framework="$ROOT" \
  -no-threaded-checker \
  -extra-linker-flags:"-framework CoreFoundation -framework CoreText -framework CoreGraphics"
odin test "$ROOT/metal" -collection:ui_framework="$ROOT" \
  -no-threaded-checker \
  -extra-linker-flags:"-framework Foundation -framework Metal -framework CoreFoundation -framework CoreText -framework CoreGraphics"
odin test "$ROOT/macos" -collection:ui_framework="$ROOT" -no-threaded-checker
