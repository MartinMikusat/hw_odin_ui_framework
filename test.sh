#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMP="$ROOT/build/test"
mkdir -p "$TEMP"
cd "$TEMP"

hw-odin test "$ROOT/draw" -collection:ui_framework="$ROOT" -no-threaded-checker
hw-odin test "$ROOT/core" -collection:ui_framework="$ROOT" -no-threaded-checker
hw-odin test "$ROOT/widgets" -collection:ui_framework="$ROOT" -no-threaded-checker
hw-odin test "$ROOT/hal_wayland" -collection:ui_framework="$ROOT" -no-threaded-checker
hw-odin test "$ROOT/diagnostics" -collection:ui_framework="$ROOT" -no-threaded-checker
hw-odin test "$ROOT/coretext" -collection:ui_framework="$ROOT" \
  -no-threaded-checker \
  -extra-linker-flags:"-framework CoreFoundation -framework CoreText -framework CoreGraphics"
hw-odin test "$ROOT/metal" -collection:ui_framework="$ROOT" \
  -no-threaded-checker \
  -extra-linker-flags:"-framework Foundation -framework Metal -framework CoreFoundation -framework CoreText -framework CoreGraphics"
hw-odin test "$ROOT/macos" -collection:ui_framework="$ROOT" \
  -no-threaded-checker \
  -extra-linker-flags:"-framework AppKit -framework Foundation"
hw-odin run "$ROOT/tests/frame_timer" -collection:ui_framework="$ROOT" \
  -extra-linker-flags:"-framework AppKit -framework Foundation"
