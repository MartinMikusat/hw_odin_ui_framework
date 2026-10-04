# hw_odin_ui_framework

Run `./test.sh` for verification. Current integration and ownership contracts are in
[README.md](README.md).

- core/, draw/, widgets/ and renderdata/: UI state, draw streams and interaction.
- coretext/ and glyphatlas/: native text shaping and glyph storage.
- metal/ and macos/: native rendering, windows and frame scheduling.
- directwrite/, d3d11/: Windows text, rendering and host adapters.
- hal_wayland/: shared palette, typography and application chrome.
- diagnostics/: bounded frame and renderer diagnostics.
- clay/: hw_clay renderer onto the draw list (needs the hw_clay collection); examples/clay_metal drives it.
