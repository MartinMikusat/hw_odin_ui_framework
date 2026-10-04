#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMP="$ROOT/build/test"
mkdir -p "$TEMP"
cd "$TEMP"
hw-odin check "$ROOT/tests/directwrite_layout" -target:windows_amd64 -collection:ui_framework="$ROOT" -thread-count:1 -warnings-as-errors -vet -strict-style
hw-odin check "$ROOT/tools/compile_hlsl" -target:windows_amd64 -thread-count:1 -warnings-as-errors -vet -strict-style
hw-odin check "$ROOT/tests/d3d11_resources" -target:windows_amd64 -collection:ui_framework="$ROOT" -thread-count:1 -warnings-as-errors -vet -strict-style -define:UI_FRAMEWORK_TEST_MODE=true
hw-odin check "$ROOT/d3d11" -no-entry-point -target:windows_amd64 -collection:ui_framework="$ROOT" -thread-count:1 -warnings-as-errors -vet -strict-style
"$ROOT/scripts/build-metallib.sh" "$TEMP/ui.metallib"

hw-odin test "$ROOT/renderdata" -collection:ui_framework="$ROOT" -thread-count:1 -warnings-as-errors -vet -strict-style -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -define:ODIN_TEST_THREADS=1
hw-odin test "$ROOT/draw" -collection:ui_framework="$ROOT" -vet -strict-style -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -no-threaded-checker
hw-odin test "$ROOT/glyphatlas" -collection:ui_framework="$ROOT" -vet -strict-style -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -no-threaded-checker
hw-odin test "$ROOT/core" -collection:ui_framework="$ROOT" -vet -strict-style -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -no-threaded-checker
hw-odin test "$ROOT/widgets" -collection:ui_framework="$ROOT" -vet -strict-style -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -no-threaded-checker
hw-odin test "$ROOT/hal_wayland" -collection:ui_framework="$ROOT" -vet -strict-style -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -no-threaded-checker
hw-odin test "$ROOT/diagnostics" -collection:ui_framework="$ROOT" -vet -strict-style -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -no-threaded-checker
hw-odin test "$ROOT/coretext" -collection:ui_framework="$ROOT" -vet -strict-style -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true \
  -no-threaded-checker \
  -extra-linker-flags:"-framework CoreFoundation -framework CoreText -framework CoreGraphics"
hw-odin test "$ROOT/metal" -collection:ui_framework="$ROOT" -vet -strict-style -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true \
  -no-threaded-checker \
  -extra-linker-flags:"-framework Foundation -framework Metal -framework CoreFoundation -framework CoreText -framework CoreGraphics"
hw-odin test "$ROOT/macos" -collection:ui_framework="$ROOT" -vet -strict-style -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true \
  -no-threaded-checker \
  -extra-linker-flags:"-framework AppKit -framework Foundation"
hw-odin run "$ROOT/tests/frame_timer" -collection:ui_framework="$ROOT" -vet -strict-style \
  -extra-linker-flags:"-framework AppKit -framework Foundation"

HW_CLAY=${HW_CLAY_ROOT:-$(CDPATH= cd -- "$ROOT/../hw_clay" && pwd)}
hw-odin check "$ROOT/clay" -no-entry-point -target:windows_amd64 -thread-count:1 -warnings-as-errors \
  -collection:hw_clay="$HW_CLAY" -collection:ui_framework="$ROOT" -collection:text_backend="$ROOT/directwrite"
hw-odin test "$ROOT/clay" -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -collection:hw_clay="$HW_CLAY" -collection:ui_framework="$ROOT"
mkdir -p "$ROOT/examples/clay_metal/build"
"$ROOT/scripts/build-metallib.sh" "$ROOT/examples/clay_metal/build/ui.metallib"
hw-odin build "$ROOT/examples/clay_metal" -collection:hw_clay="$HW_CLAY" -collection:ui_framework="$ROOT" \
  -extra-linker-flags:"-framework AppKit -framework Foundation -framework Metal -framework QuartzCore -framework CoreText -framework CoreGraphics -framework CoreFoundation" \
  -out:"$TEMP/clay_metal" -o:speed
