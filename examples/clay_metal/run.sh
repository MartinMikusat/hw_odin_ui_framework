#!/bin/sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
UI_FRAMEWORK=$(CDPATH= cd -- "$HERE/../.." && pwd)
HW_CLAY=${HW_CLAY_ROOT:-$(CDPATH= cd -- "$UI_FRAMEWORK/../hw_clay" && pwd)}
TEMP="$HERE/build"
mkdir -p "$TEMP"
# The example embeds this precompiled shader library (shaders.odin).
sh "$UI_FRAMEWORK/scripts/build-metallib.sh" "$TEMP/ui.metallib"

OUT=""
prev=""
for arg in "$@"; do
	if [ "$prev" = "-out" ]; then OUT=$arg; fi
	prev=$arg
done

hw-odin build "$HERE" \
	-collection:hw_clay="$HW_CLAY" \
	-collection:ui_framework="$UI_FRAMEWORK" \
	-extra-linker-flags:"-framework AppKit -framework Foundation -framework Metal -framework QuartzCore -framework CoreText -framework CoreGraphics -framework CoreFoundation" \
	-out:"$TEMP/hw_clay_metal" -o:speed

cd "$TEMP"
exec "$TEMP/hw_clay_metal" "$@"
