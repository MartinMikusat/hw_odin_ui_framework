# Odin UI Framework

A reusable immediate-mode interface framework for Odin applications. It builds
a keyed box tree, publishes one control registry, and emits one ordered draw
stream for a Metal backend.

## AI-assisted development disclosure

Models used:

- **gpt-5.6-sol**

The framework keeps application actions and durable product state in the
application. It owns frame layout, transient interaction state, drawing order,
text shaping caches, Metal batching, and macOS interface adapters.

The implementation uses ideas observed in RADDBG's keyed immediate-mode UI and
ordered draw buckets. It does not copy RADDBG source code.

## Packages

- `core` builds and lays out keyed boxes. It publishes actions and controls.
- `widgets` composes shared labels, buttons, panes, scroll areas, and virtual lists.
- `draw` records ordered rectangles, glyphs, images, and external textures.
- `diagnostics` captures stable control snapshots and ordered render traces.
- `coretext` shapes text and supplies glyphs to the draw stream.
- `metal` encodes the draw stream into a caller-owned Metal command buffer.
- `macos` adapts AppKit pointer and Accessibility events to published controls.

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
active, focus, scroll, and animation values for the next frame.

Layout runs standalone and upward-dependent size passes on each axis. The
downward arrangement pass resolves percentages and remaining space, then
partitions constraint violations by size strictness. Scroll areas retain target
offsets, clamp them to measured content bounds, and animate the visible offset.

Scoped declarations provide layout, style, flag, and layer defaults. A next-box
declaration applies once. Widgets and application boxes use the same keyed tree.

The draw stream preserves submission order. The renderer combines adjacent
compatible instances only. It does not sort rectangles, text, or textures.
Nested buckets splice complete draw streams into their parent without changing
relative order.

## Verification

```sh
./test.sh
```

## License

This repository uses the MIT license. See [LICENSE](LICENSE).
