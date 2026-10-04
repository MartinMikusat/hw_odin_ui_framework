# hw_clay on hw_odin_ui_framework (Metal)

Renders hw_clay layout through the `hw_odin_ui_framework` draw list, Metal
encoder, and CoreText text backend, so a native macOS app can use Clay without
a third party renderer. The renderer itself is the importable package
`clay/renderer_darwin.odin` (`import hw_clay_ui "ui_framework:clay"`); this
example is its offscreen harness plus a windowed host.

```sh
./run.sh -out frame.ppm -frames 3
./run.sh -out hover.ppm   -frames 3 -mouse 100,131
./run.sh -out click.ppm   -frames 4 -click 100,183
./run.sh -out scroll.ppm  -frames 5 -scroll -6 -mouse 260,300
./run.sh -out debug.ppm   -frames 5 -debug

./run.sh -window                 # interactive window, D toggles the debug view
./run.sh -window -frames 90      # render 90 frames, then exit
```

`run.sh` writes a PPM; use `magick frame.ppm frame.png` to view it. It builds
with `-collection:hw_clay=<hw_clay>` and
`-collection:ui_framework=<hw_odin_ui_framework>` (override the hw_clay path
with `HW_CLAY_ROOT`).

The renderer is `renderer_darwin.odin`:

- Rectangles become `draw.solid_corners` with each corner radius applied.
- Uniform borders become a rounded stroke (`border_thickness`); borders with
  different side widths become plain rectangles per side. Clay's
  between-children border rectangles arrive as ordinary rectangle commands.
- Text is shaped once per line through `coretext.shape` and emitted with
  `coretext.emit_shaped_run`; `measure_text` uses the same shaping, so layout
  and drawing agree.
- Clipping maps to `draw.push_clip` / `pop_clip`, and colour overlays are
  folded into emitted colours with the reference renderer's mix.
- Clay's debug view works: its text uses font id 0, which
  `font_for` resolves to the app's default font.
- Images would pass an app owned handle bundle as `image_data`; the demo does
  not exercise that path yet.

`window_macos.odin` is the interactive host: an NSApplication and NSWindow
backed by a CAMetalLayer, a display link, and mouse, scroll, and key handlers
feeding hw_clay. Note that `macos.display_link_start` leaves the link paused and
it only ticks while the view is on screen, so the host unpauses it after start
and `-hidden` windows may receive no callbacks at all.

`main.odin` is an offscreen harness, which is how the frames above are
produced and checked: it creates a Metal texture and command queue, renders the
requested number of frames through the same sequence a windowed host uses
(`metal.begin_texture_frame`, `coretext.begin_frame`, clay frame,
`coretext.flush`, `metal.encode_to_drawable`), reads the texture back, and
writes a PPM. It exits non-zero if clay reports any layout error.

## Limitations

- Per-side borders with different widths are drawn as square rectangles;
  rounded strokes are used for uniform borders.

## Requirements

- macOS with Metal, the Odin toolchain, and the sibling `hw_clay`
  repository. `optional: ImageMagick` for PPM to PNG conversion (verification
  aid, not required to run).
