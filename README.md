# Odin UI Framework

A reusable immediate-mode interface framework for Odin applications. It builds
a keyed box tree, publishes one control registry, and emits one ordered draw
stream for a Metal backend.

The framework keeps application actions and durable product state in the
application. It owns frame layout, transient interaction state, drawing order,
text shaping caches, Metal batching, and macOS interface adapters.

The implementation uses ideas observed in RADDBG's keyed immediate-mode UI and
ordered draw buckets. It does not copy RADDBG source code.

## Native ownership

`metal.encode` receives a caller-owned encoder and its command buffer.
`encode_to_drawable` owns the passes needed for max-blend offscreen composition.
Draw data uses shared upload slots; a slot is reused only after its command buffer
completes. Commit every encoded command buffer, or discard it without committing
it later. `upload_stats` reports allocations, waits and reclaims.

`macos.Display_Link` wraps the macOS 14 `NSView` display-link API. It follows
the view between displays, runs in normal and event-tracking run-loop modes,
starts paused, and accepts a best-effort 30–120 Hz frame-rate range with 120 Hz
preferred. `macos.Frame_Timer` supplies timer-driven scheduling. The application owns either callback
target and must stop the clock before it releases that target.

Applications add this repository as an Odin collection:

```sh
-collection:ui_framework=/path/to/hw_odin_ui_framework
```

```odin
import ui "ui_framework:core"
import draw "ui_framework:draw"
```

`clay/` draws `hw_clay` render commands into a draw list (`import "ui_framework:clay"`);
importing it also needs `-collection:hw_clay=/path/to/hw_clay`. `examples/clay_metal` is
its offscreen and windowed Metal harness.

## Shader library

Shaders are always precompiled; the renderer has no source-compilation path.
Build `ui.metallib` with `scripts/build-metallib.sh OUTPUT.metallib` as part of the
application build, embed it (`#load`), and pass it to `metal.renderer_init` as
`metallib_data`, or pass a bundled file as `metallib_path`. A missing or invalid
library fails initialization. Changing `shaders/ui.metal` requires rebuilding the
library. Windows builds compile `ui.hlsl` with `scripts/build-hlsl.ps1 OUTPUT`
into four Shader Model 5 `.cso` files. Both backends use `shaders/ui_common.h`
for vertex placement, analytic shapes, color sampling and path coverage.

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

Each box emits its fill, then any `Drop_Shadow` children, then its face and
non-shadow descendants. Ancestor backgrounds therefore cannot cover a child's
drop shadow.

Each logical UI surface owns base, popup, tooltip, and modal strata. The
framework renders the base surface first, then each modal surface in stack
order, and emits the debug stratum once above the complete stack. A modal root
starts a surface, records its parent surface, and attaches its layout root to
the viewport root. Nested modal geometry therefore does not inherit the parent
panel's transform or clip.

Only the top surface publishes ordinary controls and actions. An input root can
restrict publication further within that surface. Explicit pass-through
controls keep window operations available without exposing the covered
application surface. Pointer, keyboard, text, numbered, accessibility, flash,
command-menu, and CLI adapters all consume the same published registry.

Opening a surface captures the previous surface's focus and focuses its first
enabled focusable control. Closing it restores the captured focus. Focus-next,
focus-previous, activate-focused, and dismiss-request events operate on the top
surface only. A surface dismiss control converts Escape or a backdrop click
into a signal for that surface; nested dismissal leaves every parent surface
mounted and inactive until it becomes topmost again.

The draw stream preserves submission order. The renderer combines adjacent
compatible instances only. It does not sort rectangles, text, or textures.
Nested buckets splice complete draw streams into their parent without changing
relative order. Parent transforms, clips, and opacity compose into each nested
bucket before Metal encodes its instances. Clip rectangles are projected into
render-target coordinates before the renderer converts them to Metal scissors.
Boxes can also provide a rectangle-dependent custom transform. Core applies it
to the complete box subtree and projects published control bounds through the
same transform, so drawing and hit testing stay aligned during motion.

Vector paths use the same ordered stream, clip, transform, and opacity records
as quad batches. `path_begin` starts a list-bound path; move, line, quadratic,
cubic, arc, close, rectangle, rounded-rectangle, circle, and ellipse commands
append contours. Solid-color fills support non-zero and even-odd rules, while
strokes support butt, round, and square caps plus miter, round, and bevel joins.
Non-finite input invalidates the pending path and its fill or stroke emits no
batch. Gradients, image paints, and dashed strokes are outside this API.

NanoVG flattens paths at `List.pixel_ratio` and the draw list copies the
resulting triangles into owned path batches immediately. Convex fills encode
directly. Compound fills use a transient `Stencil8` attachment for winding or
parity, and strokes use the same attachment to prevent self-overdraw at joins.
Each stencil sequence clears its written footprint before the next ordered
batch. Caller-owned encoders must pass `stencil_available = true` only when
their render pass has a matching `Stencil8` attachment; otherwise `encode`
rejects a list that requires stencil. `encode_to_drawable` allocates and reuses
the attachment automatically.

`draw.Corner_Shape` selects `.Round` or `.Squircle` for a solid quad. `.Round`
is the zero value and preserves the circular rounded-box contour. `.Squircle`
uses the exponent-four superellipse defined by CSS `superellipse(2)`. The shape
flows through `ui.Style.corner_shape` to fills, borders, and shadows without
changing batching; applications must opt in explicitly.

Independently changing pieces of an interface are cached surfaces
(`metal/surface.odin`). A `metal.Surface` owns a GPU-private render target. Paint
it with `surface_paint` only when `surface_is_current` reports that its size,
scale, or application `content_revision` changed; every other frame draws it with
`surface_composite`, one textured quad. Modals and dense views are separate
surfaces; pointer feedback is drawn as an overlay after compositing, so hover never
repaints a surface.

Textures that live across frames use persistent handles
(`register_persistent_texture`), which stay valid through `begin_texture_frame`.
Surfaces and glyph atlas pages register this way, so a warm frame performs no
texture registration. `register_texture` remains for textures used within one
frame. `snapshot_texture_natives` and `rebind_texture_natives` are needed for retained buckets holding frame handles.

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
