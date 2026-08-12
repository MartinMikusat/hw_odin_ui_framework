# Odin UI Framework

A reusable immediate-mode interface framework for Odin applications. It builds
a keyed box tree, publishes one control registry, and emits one ordered draw
stream for a Metal backend.

## AI-assisted development disclosure

Models used:

- **gpt-5.6-sol**
- **Cursor Grok 4.5**
- **Cursor Grok 4.6**

The framework keeps application actions and durable product state in the
application. It owns frame layout, transient interaction state, drawing order,
text shaping caches, Metal batching, and macOS interface adapters.

The implementation uses ideas observed in RADDBG's keyed immediate-mode UI and
ordered draw buckets. It does not copy RADDBG source code.

## Packages

- `core` builds and lays out keyed boxes. It publishes actions and controls.
- `widgets` composes shared labels, buttons, panes, scroll areas, and virtual lists.
- `hal_wayland` defines the canonical Hal Wayland light/dark palette, semantic
  accents, typography, application chrome geometry, responsive action-bar
  layout, and square control styles.
- `draw` records ordered rectangles, glyphs, images, and external textures.
- `diagnostics` captures stable control snapshots, ordered render traces, and
  fixed-capacity CPU/GPU performance histories without allocating per frame.
- `coretext` shapes text and supplies glyphs to the draw stream.
- `metal` encodes the draw stream into Metal. `encode` writes into a caller-owned
  encoder. `encode_to_drawable` owns the pass list so `Combine.Max` batches can
  max-blend offscreen and then over-composite onto the canvas.
- `macos` adapts AppKit pointer and Accessibility events to published controls.

`macos.Display_Link` wraps the macOS 14 `NSView` display-link API. It follows
the view between displays, runs in normal and event-tracking run-loop modes,
starts paused, and accepts a best-effort 30–120 Hz frame-rate range with 120 Hz
preferred. The older `macos.Frame_Timer` remains available for existing hosts;
no application is migrated implicitly. The application owns either callback
target and must stop the clock before it releases that target.

Applications add this repository as an Odin collection:

```sh
-collection:ui_framework=/path/to/hw_odin_ui_framework
```

```odin
import ui "ui_framework:core"
import draw "ui_framework:draw"
```

## Frame contract

1. Queue input or mutate application state, then call `request_frame` with the
   corresponding input, state, animation, surface, or diagnostic reason.
2. The host wake callback resumes its platform display link.
3. The host calls `take_frame_requests`, builds each visible box and control,
   completes layout, and publishes the frame output.
4. The host dispatches activations and encodes the ordered draw stream.
5. Active animations request their successor frame. When no requests remain,
   the host pauses its display link.

Requests coalesce in a `bit_set`, so several mutations wake a sleeping host
once while preserving their reasons. Idle means the application receives no
frame callback and performs no UI build, shaping, Metal encoding, or present;
the operating-system event loop and compositor continue independently.

The core retains only state keyed by stable control identity. Each frame owns
its box tree, events, signals, controls, and draw commands. `###` separates a
stable identity suffix from display text, so localization and changing labels
do not reset interaction state.

`animate` provides rate-based interpolation for continuous interaction state.
`timeline` provides reversible, keyed tracks with an explicit delay and
duration. `spring` provides reversible, keyed damped motion with retained
velocity, explicit delay, frequency, and damping ratio. All track types share
context lifetime, stale-track removal, and animation-state reporting.

Pointer, scroll, keyboard, text, and file-drop events enter one ordered queue.
Controls consume matching events and emit signals. The context retains hot,
active, focus, disabled, scroll, and animation values for the next frame. Key
and text payloads remain owned through frame publication.

Render emission intersects every box with the viewport and ancestor clips.
Boxes with an empty resolved clip publish no paint or control. A non-clipping
parent still traverses its children because a positioned child can re-enter
the viewport.

Layout runs standalone and upward-dependent size passes on each axis. The
downward arrangement pass resolves percentages and remaining space, then
partitions constraint violations by size strictness. Scroll areas retain target
offsets, clamp them to measured content bounds, and animate the visible offset.
Helpers scroll by a delta or reveal a prior-frame item rectangle. Virtual lists
emit visible rows plus spacers that preserve the complete scroll extent.

Scoped declarations provide layout, style, flag, and layer defaults. A next-box
declaration applies once. Widgets and application boxes use the same keyed tree.

Base, popup, tooltip, modal, and debug layers render in a fixed order. An input
root restricts control and associated action publication to one subtree, so
pointer, numbered, accessibility, flash, command-menu, and CLI adapters resolve
the same active surface. Command-only actions remain published. Explicit
pass-through controls can keep window operations available while a modal owns
application input.

The draw stream preserves submission order. The renderer combines adjacent
compatible instances only. It does not sort rectangles, text, or textures.
Nested buckets splice complete draw streams into their parent without changing
relative order. Parent transforms, clips, and opacity compose into each nested
bucket before Metal encodes its instances. Clip rectangles are projected into
render-target coordinates before the renderer converts them to Metal scissors.
Boxes can also provide a rectangle-dependent custom transform. Core applies it
to the complete box subtree and projects published control bounds through the
same transform, so drawing and hit testing stay aligned during motion.

Ordinary applications rebuild draw lists every requested frame, matching the
RADDBG immediate-UI model. Media hot loops may retain chrome `draw.Bucket`
values across ticks when panels and labels are unchanged. Those buckets may
outlive `begin_texture_frame` only if the application snapshots Metal texture
natives with `snapshot_texture_natives` after the chrome rebuild and calls
`rebind_texture_natives` before compose or encode on a warm tick. This is a
Hal Wayland hot-loop extension, not RADDBG draw-list retention. Workspace
contracts live in
[`notes/native-render-lifetime-contracts.md`](../notes/native-render-lifetime-contracts.md).

CoreText returns an opaque prepared-run handle. The box stores that handle and
uses its metrics for alignment. Glyph emission consumes the same handle, so the
measurement and draw paths cannot shape different text. Prepared runs persist
across frames behind an exact text/font/size/tracking/width/truncation/scale/font-
generation key. The cache preserves stable slot handles, exposes hit/miss/
eviction counters, removes entries unused for 240 rendered frames, and holds at
most 4096 live runs.

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
