# Odin UI Framework

A reusable immediate-mode interface framework for Odin applications. It builds
a keyed box tree, publishes one control registry, and emits one ordered draw
stream for a Metal backend.

## AI-assisted development disclosure

Models used:

- **gpt-5.6-sol**
- **Cursor Grok 4.5**

The framework keeps application actions and durable product state in the
application. It owns frame layout, transient interaction state, drawing order,
text shaping caches, Metal batching, and macOS interface adapters.

The implementation uses ideas observed in RADDBG's keyed immediate-mode UI and
ordered draw buckets. It does not copy RADDBG source code.

## Packages

- `core` builds and lays out keyed boxes. It publishes actions and controls.
- `widgets` composes shared labels, buttons, panes, scroll areas, and virtual lists.
- `draw` records ordered rectangles, glyphs, images, and external textures.
- `diagnostics` captures stable control snapshots, ordered render traces, and
  fixed-capacity CPU/GPU performance histories without allocating per frame.
- `coretext` shapes text and supplies glyphs to the draw stream.
- `metal` encodes the draw stream into a caller-owned Metal command buffer.
- `macos` adapts AppKit pointer and Accessibility events to published controls.

`macos.Frame_Timer` owns the main-run-loop frame clock. It registers one timer
in `NSDefaultRunLoopMode` and `NSEventTrackingRunLoopMode`, so rendering
continues during live window resizing. The application owns the callback and
must stop the timer before it releases the callback target.

Applications add this repository as an Odin collection:

```sh
-collection:ui_framework=/path/to/hw_odin_ui_framework
```

```odin
import ui "ui_framework:core"
import draw "ui_framework:draw"
```

## Frame contract

1. Queue input from the platform callbacks.
2. Build each visible box and control once.
3. Complete layout and publish the frame output.
4. Dispatch each activation through the application's typed action router.
5. Encode the ordered draw stream into the application's render target.

The core retains only state keyed by stable control identity. Each frame owns
its box tree, events, signals, controls, and draw commands. `###` separates a
stable identity suffix from display text, so localization and changing labels
do not reset interaction state.

Pointer, scroll, keyboard, text, and file-drop events enter one ordered queue.
Controls consume matching events and emit signals. The context retains hot,
active, focus, disabled, scroll, and animation values for the next frame. Key
and text payloads remain owned through frame publication.

Layout runs standalone and upward-dependent size passes on each axis. The
downward arrangement pass resolves percentages and remaining space, then
partitions constraint violations by size strictness. Scroll areas retain target
offsets, clamp them to measured content bounds, and animate the visible offset.
Helpers scroll by a delta or reveal a prior-frame item rectangle. Virtual lists
emit visible rows plus spacers that preserve the complete scroll extent.

Scoped declarations provide layout, style, flag, and layer defaults. A next-box
declaration applies once. Widgets and application boxes use the same keyed tree.

Base, popup, tooltip, modal, and debug layers render in a fixed order. An input
root restricts pointer publication to one subtree. Explicit pass-through controls
can keep window operations available while a modal owns application input.

The draw stream preserves submission order. The renderer combines adjacent
compatible instances only. It does not sort rectangles, text, or textures.
Nested buckets splice complete draw streams into their parent without changing
relative order. Parent transforms, clips, and opacity compose into each nested
bucket before Metal encodes its instances. Clip rectangles are projected into
render-target coordinates before the renderer converts them to Metal scissors.

CoreText returns an opaque prepared-run handle. The box stores that handle and
uses its metrics for alignment. Glyph emission consumes the same handle, so the
measurement and draw paths cannot shape different text.

`Registry_View` exposes borrowed frame records without cloning. A persistent
`Registry_Builder` supports callbacks that outlive a frame arena. Both forms use
the same validation, hit testing, activation, Accessibility, Flash, CLI, and
numbered-input adapters.

## Verification

```sh
./test.sh
```

## License

This repository uses the MIT license. See [LICENSE](LICENSE).
