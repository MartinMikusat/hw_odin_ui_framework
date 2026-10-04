// Clay rendered through hw_odin_ui_framework: layout via clay, drawing via the
// framework's draw list and Metal encoder, text via CoreText.
//
// This build renders offscreen so it can be verified without a window:
//
//   ./run.sh -out frame.ppm [-frames 2] [-width 720] [-height 420] [-scale 2]
//            [-mouse 100,100] [-click 100,100] [-scroll -6] [-debug]
//
// run.sh converts the PPM to PNG when ImageMagick is available. The app exits
// non zero if clay reported any layout error.
//
// A windowed host would use the same per-frame sequence (metal.begin_texture_frame,
// coretext.begin_frame, clay frame, coretext.flush, metal.encode_to_drawable)
// with the layer's drawable texture instead of the offscreen texture.

package main

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:os"
import "core:strconv"
import "core:strings"
import hw_clay "hw_clay:."
import draw "ui_framework:draw"
import coretext "ui_framework:coretext"
import ui "ui_framework:core"
import metal "ui_framework:metal"
import hw_clay_ui "ui_framework:clay"

FONT_UI :: ui.Font_Handle(1)
FONT_MONO :: ui.Font_Handle(2)

COLOR_BACKDROP :: hw_clay.Color{238, 240, 244, 255}
COLOR_SURFACE :: hw_clay.Color{255, 255, 255, 255}
COLOR_INK :: hw_clay.Color{28, 32, 40, 255}
COLOR_MUTED :: hw_clay.Color{104, 112, 128, 255}
COLOR_ACCENT :: hw_clay.Color{225, 138, 50, 255}
COLOR_ACCENT_SOFT :: hw_clay.Color{250, 236, 220, 255}
COLOR_HOVER :: hw_clay.Color{244, 246, 250, 255}
COLOR_HAIRLINE :: hw_clay.Color{210, 214, 222, 255}

App :: struct {
	selected: int,
	clicks:   int,
	wheel:    f32,
}

app: App

FRAME_TIME :: 1.0 / 60.0

element :: proc(ctx: ^hw_clay.Context, config: hw_clay.Element_Declaration, id: hw_clay.Element_Id = {}) -> bool {
	hw_clay.push_element(ctx, config, id)
	return true
}

nav_items := [4]string{"Overview", "Layout", "Rendering", "Transitions"}

nav_item :: proc(ctx: ^hw_clay.Context, index: int) {
	selected := app.selected == index
	hw_clay.open_element(ctx, hw_clay.id_indexed("nav", u32(index)))
	hw_clay.configure_element(ctx, {
		layout = {
			sizing = {width = hw_clay.grow(), height = hw_clay.fixed(34)},
			padding = {left = 10, right = 10},
			child_alignment = {y = .Center},
		},
		corner_radius = hw_clay.corner_radius_all(6),
		background_color = selected ? COLOR_ACCENT_SOFT : (hw_clay.hovered(ctx) ? COLOR_HOVER : hw_clay.Color{}),
	})
	hw_clay.on_hover(ctx, nav_item_interaction, rawptr(uintptr(index)))
	hw_clay.push_text(ctx, nav_items[index], {font_id = u16(FONT_UI), font_size = 13, color = selected ? COLOR_ACCENT : COLOR_INK})
	hw_clay.pop_element(ctx)
}

nav_item_interaction :: proc(element_id: hw_clay.Element_Id, pointer_info: hw_clay.Pointer_Data, user_data: rawptr) {
	if pointer_info.state == .Pressed_This_Frame {
		app.selected = int(uintptr(user_data))
	}
}

card :: proc(ctx: ^hw_clay.Context, title, body: string, mono: bool) {
	if element(ctx, {
		layout = {
			layout_direction = .Top_To_Bottom,
			sizing = {hw_clay.grow(), hw_clay.fit()},
			padding = hw_clay.padding_all(12),
			child_gap = 6,
		},
		background_color = COLOR_SURFACE,
		corner_radius = hw_clay.corner_radius_all(10),
		border = {color = COLOR_HAIRLINE, width = hw_clay.border_all(1)},
	}) {
		defer hw_clay.pop_element(ctx)
		hw_clay.push_text(ctx, title, {font_id = u16(FONT_UI), font_size = 15, color = COLOR_INK})
		if mono {
			hw_clay.push_text(ctx, body, {font_id = u16(FONT_MONO), font_size = 12, color = COLOR_MUTED})
		} else {
			hw_clay.push_text(ctx, body, {font_id = u16(FONT_UI), font_size = 12, color = COLOR_MUTED})
		}
	}
}

create_layout :: proc(ctx: ^hw_clay.Context, delta_time: f32) -> []hw_clay.Render_Command {
	hw_clay.begin_layout(ctx)
	if element(ctx, {
		layout = {
			layout_direction = .Top_To_Bottom,
			sizing = {hw_clay.grow(), hw_clay.grow()},
			padding = hw_clay.padding_all(16),
			child_gap = 12,
		},
		background_color = COLOR_BACKDROP,
	}, hw_clay.id("Root")) {
		defer hw_clay.pop_element(ctx)
		// Header.
		if element(ctx, {
			layout = {
				sizing = {hw_clay.grow(), hw_clay.fixed(52)},
				padding = {left = 16, right = 16},
				child_gap = 12,
				child_alignment = {y = .Center},
			},
			background_color = COLOR_SURFACE,
			corner_radius = hw_clay.corner_radius_all(10),
			border = {color = COLOR_HAIRLINE, width = hw_clay.border_all(1)},
		}, hw_clay.id("Header")) {
			defer hw_clay.pop_element(ctx)
			hw_clay.push_text(ctx, "hw_clay on Metal", {font_id = u16(FONT_UI), font_size = 20, color = COLOR_INK})
			hw_clay.push_text(ctx, "a hw_odin_ui_framework renderer", {font_id = u16(FONT_UI), font_size = 12, color = COLOR_MUTED})
			if element(ctx, {layout = {sizing = {width = hw_clay.grow()}}}) {
				defer hw_clay.pop_element(ctx)
			}
			// Hover and click state driven button.
			hw_clay.open_element(ctx, hw_clay.id("Button"))
			hw_clay.configure_element(ctx, {
				layout = {
					sizing = {height = hw_clay.fixed(32)},
					padding = {left = 14, right = 14},
					child_alignment = {y = .Center},
				},
				background_color = hw_clay.hovered(ctx) ? COLOR_ACCENT : COLOR_ACCENT_SOFT,
				corner_radius = hw_clay.corner_radius_all(8),
				overlay_color = hw_clay.hovered(ctx) ? hw_clay.Color{140, 140, 140, 40} : hw_clay.Color{255, 255, 255, 0},
			})
			hw_clay.on_hover(ctx, button_interaction, nil)
			hw_clay.push_text(ctx, app.clicks > 0 ? "Clicked!" : "Hover me", {
				font_id = u16(FONT_UI),
				font_size = 13,
				color = hw_clay.hovered(ctx) ? COLOR_SURFACE : COLOR_ACCENT,
			})
			hw_clay.pop_element(ctx)
		}
		// Body.
		if element(ctx, {
			layout = {sizing = {hw_clay.grow(), hw_clay.grow()}, child_gap = 12},
		}, hw_clay.id("Body")) {
			defer hw_clay.pop_element(ctx)
			// Sidebar.
			if element(ctx, {
				layout = {
					sizing = {width = hw_clay.fixed(170), height = hw_clay.grow()},
					layout_direction = .Top_To_Bottom,
					padding = hw_clay.padding_all(8),
					child_gap = 4,
				},
				background_color = COLOR_SURFACE,
				corner_radius = hw_clay.corner_radius_all(10),
				border = {color = COLOR_HAIRLINE, width = hw_clay.border_all(1)},
			}, hw_clay.id("Sidebar")) {
				defer hw_clay.pop_element(ctx)
				for _, index in nav_items {
					nav_item(ctx, index)
				}
			}
			// Scrolling content column.
			hw_clay.open_element(ctx, hw_clay.id("Content"))
			hw_clay.configure_element(ctx, {
				layout = {
					sizing = {hw_clay.grow(), hw_clay.grow()},
					layout_direction = .Top_To_Bottom,
					child_gap = 10,
					padding = {right = 4},
				},
				clip = {vertical = true, child_offset = hw_clay.get_scroll_offset(ctx)},
			})
			card(ctx, "Flexbox style layout",
				"Grow, fit, percent and fixed sizing with padding, child gaps, alignment, floating elements, clipping and scrolling. This frame was laid out by the native Odin port of Clay.",
				false)
			card(ctx, "Renderer agnostic output",
				"Clay emits a sorted list of primitive render commands. Here they are mapped onto hw_odin_ui_framework draw list calls and encoded into a Metal texture; the raylib examples use the same command stream.",
				false)
			card(ctx, "Text through CoreText", "Every line arrives pre-wrapped with a font id and size; shaping, glyph rasterisation and atlas upload all happen through the framework's CoreText backend.", false)
			card(ctx, "Mono", "#include clay.h\nhw_hw_clay.begin_layout(&ctx)", true)
			card(ctx, "Interaction", "Hover states read hw_clay.hovered() during declaration, clicks arrive through hw_clay.on_hover handlers, and the content column scrolls with the mouse wheel.", false)
			card(ctx, "Transitions", "Enter and exit transitions are available too; the raylib transitions example captures them mid-animation against the C reference.", false)
			hw_clay.pop_element(ctx)
		}
		// Footer.
		if element(ctx, {layout = {sizing = {hw_clay.grow(), hw_clay.fixed(20)}, child_alignment = {y = .Center}}}) {
			defer hw_clay.pop_element(ctx)
			hw_clay.push_text(ctx, "Frames rendered offscreen through Metal; no window needed for the screenshot check.", {
				font_id = u16(FONT_UI),
				font_size = 11,
				color = COLOR_MUTED,
			})
		}
	}
	return hw_clay.end_layout(ctx, delta_time)
}

button_interaction :: proc(element_id: hw_clay.Element_Id, pointer_info: hw_clay.Pointer_Data, user_data: rawptr) {
	if pointer_info.state == .Pressed_This_Frame {
		app.clicks += 1
	}
}

// Offscreen harness ------------------------------------------------------------

Config :: struct {
	out:    string,
	frames: int,
	width:  i32,
	height: i32,
	scale:  f32,
	mouse:  [2]f32,
	click:  [2]f32,
	scroll: f32,
	debug:  bool,
	has_mouse: bool,
	has_click: bool,
	window: bool,
	hidden: bool,
	deadline: f64,
}

clay_context: hw_clay.Context
error_count: int

clay_error_handler :: proc(data: hw_clay.Error_Data) {
	error_count += 1
	fmt.eprintf("hw_clay error: %v: %s\n", data.error_type, data.error_text)
}

foreign import objc_runtime "system:libobjc.A.dylib"
foreign objc_runtime {
	objc_getClass    :: proc "c" (name: cstring) -> metal.Object ---
	sel_registerName :: proc "c" (name: cstring) -> metal.Selector ---
}

foreign import metal_framework "system:Metal.framework"
foreign metal_framework {
	MTLCreateSystemDefaultDevice :: proc "c" () -> metal.Object ---
}

// get_bytes reads a Metal texture back into CPU memory through
// getBytes:bytesPerRow:fromRegion:mipmapLevel:.
get_bytes :: proc(receiver: metal.Object, bytes: []u8, bytes_per_row: uint, width, height: uint) {
	send := cast(proc "c" (_: metal.Object, _: metal.Selector, _: rawptr, _: uint, _: metal.MTL_Region, _: uint))metal.objc_msgSend
	region := metal.MTL_Region {
		size = {width, height, 1},
	}
	send(receiver, sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:"), raw_data(bytes), bytes_per_row, region, 0)
}

parse_args :: proc() -> Config {
	config := Config {
		out      = "frame.ppm",
		deadline = 10,
		frames = 2,
		width  = 720,
		height = 420,
		scale  = 2,
	}
	args := os.args
	i := 1
	for i < len(args) {
		flag := args[i]
		value := ""
		// Boolean flags take no value.
		boolean := flag == "-debug" || flag == "-window" || flag == "-hidden"
		if !boolean && i + 1 < len(args) {
			value = args[i + 1]
			i += 2
		} else {
			i += 1
		}
		switch flag {
		case "-out":
			config.out = value
		case "-frames":
			value_int, _ := strconv.parse_int(value)
			config.frames = value_int
		case "-width":
			value_int, _ := strconv.parse_int(value)
			config.width = i32(value_int)
		case "-height":
			value_int, _ := strconv.parse_int(value)
			config.height = i32(value_int)
		case "-scale":
			config.scale, _ = strconv.parse_f32(value)
		case "-mouse":
			config.mouse, config.has_mouse = parse_point(value)
		case "-click":
			config.click, config.has_click = parse_point(value)
		case "-scroll":
			config.scroll, _ = strconv.parse_f32(value)
		case "-debug":
			config.debug = true
		case "-window":
			config.window = true
		case "-hidden":
			config.hidden = true
		case "-seconds":
			value_f32, _ := strconv.parse_f32(value)
			config.deadline = f64(value_f32)
		case:
		}
	}
	return config
}

parse_point :: proc(value: string) -> ([2]f32, bool) {
	parts := strings.split(value, ",")
	if len(parts) != 2 {
		return {}, false
	}
	x, x_ok := strconv.parse_f32(parts[0])
	y, y_ok := strconv.parse_f32(parts[1])
	return {x, y}, x_ok && y_ok
}

pointer_for_frame :: proc(config: Config, frame: int) -> (position: [2]f32, has_position: bool, pressed: bool) {
	if config.has_click {
		// Hold the press for two frames so the handler observes
		// Pressed_This_Frame, matching a real mouse.
		return config.click, true, frame == 2 || frame == 3
	}
	if config.has_mouse {
		return config.mouse, true, false
	}
	return {}, false, false
}

write_ppm :: proc(path: string, pixels: []u8, width, height: int) -> bool {
	file, err := os.create(path)
	if err != os.ERROR_NONE {
		return false
	}
	defer os.close(file)
	header := fmt.tprintf("P6\n%d %d\n255\n", width, height)
	os.write_string(file, header)
	row := make([]u8, width * 3, context.temp_allocator)
	for y in 0 ..< height {
		for x in 0 ..< width {
			pixel := (y * width + x) * 4
			row[x * 3 + 0] = pixels[pixel + 2]
			row[x * 3 + 1] = pixels[pixel + 1]
			row[x * 3 + 2] = pixels[pixel + 0]
		}
		if _, write_err := os.write(file, row); write_err != os.ERROR_NONE {
			return false
		}
	}
	return true
}

main :: proc() {
	config := parse_args()

	if config.window {
		if !window_host_init(&host, config.frames, config.deadline, config.hidden) {
			os.exit(1)
		}
		host.app->run()
		window_host_shutdown(&host)
		if error_count != 0 {
			fmt.eprintf("hw_clay_metal: %d layout error(s) reported\n", error_count)
			os.exit(1)
		}
		return
	}

	device := MTLCreateSystemDefaultDevice()
	if device == nil {
		fmt.eprintln("hw_clay_metal: no Metal device")
		os.exit(1)
	}
	queue := metal.msg_id(device, sel_registerName("newCommandQueue"))
	if queue == nil {
		fmt.eprintln("hw_clay_metal: no command queue")
		os.exit(1)
	}

	pixel_width := int(f32(config.width) * config.scale)
	pixel_height := int(f32(config.height) * config.scale)

	descriptor := metal.msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		80,
		uint(pixel_width),
		uint(pixel_height),
		false,
	)
	target := metal.msg_id_id(device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	if target == nil {
		fmt.eprintln("hw_clay_metal: failed to create the render target")
		os.exit(1)
	}

	renderer_metal: metal.Renderer
	if !metal.renderer_init(&renderer_metal, device, metallib_data = UI_METALLIB) {
		fmt.eprintln("hw_clay_metal: renderer_init failed")
		os.exit(1)
	}

	text_context: coretext.Context
	coretext.context_init(&text_context)

	renderer: hw_clay_ui.Renderer
	renderer.text = &text_context
	renderer.viewport_height = f32(config.height)
	hw_clay_ui.renderer_register_font(&renderer, FONT_UI, ".AppleSystemUIFont")
	hw_clay_ui.renderer_register_font(&renderer, FONT_MONO, "Menlo-Regular")

	list: draw.List
	draw.list_init(&list, pixel_ratio = config.scale)
	renderer.list = &list

	// Clay.
	memory := make([]u8, hw_clay.min_memory_size())
	ok := hw_clay.initialize(&clay_context, memory, {f32(config.width), f32(config.height)}, {handler = clay_error_handler})
	if !ok {
		fmt.eprintln("hw_clay_metal: clay initialize failed; out of memory")
		os.exit(1)
	}
	hw_clay.set_measure_text_function(&clay_context, hw_clay_ui.measure_text, &renderer)
	if config.debug {
		hw_clay.set_debug_mode_enabled(&clay_context, true)
	}

	commands: []hw_clay.Render_Command
	for frame in 0 ..< max(config.frames, 1) {
		metal.begin_texture_frame(&renderer_metal)
		coretext.begin_frame(&text_context, config.scale, metal.atlas_io(&renderer_metal))
		draw.list_reset(&list)

		if position, has_position, pressed := pointer_for_frame(config, frame); has_position {
			hw_clay.set_pointer_state(&clay_context, {position[0], position[1]}, pressed)
		}
		if config.scroll != 0 && frame >= 1 {
			hw_clay.update_scroll_containers(&clay_context, false, {0, config.scroll}, FRAME_TIME)
		}

		commands = create_layout(&clay_context, FRAME_TIME)
		hw_clay_ui.render_commands(&renderer, commands)
		coretext.flush(&text_context)

		command_buffer := metal.msg_id(queue, sel_registerName("commandBuffer"))
		if !metal.encode_to_drawable(
			&renderer_metal,
			command_buffer,
			target,
			&list,
			{f32(config.width), f32(config.height)},
			config.scale,
			{0.93, 0.94, 0.96, 1.0},
		) {
			fmt.eprintln("hw_clay_metal: encode failed")
			os.exit(1)
		}
		metal.msg_void(command_buffer, sel_registerName("commit"))
		metal.msg_void(command_buffer, sel_registerName("waitUntilCompleted"))
	}

	pixels := make([]u8, pixel_width * pixel_height * 4, context.temp_allocator)
	get_bytes(target, pixels, uint(pixel_width * 4), uint(pixel_width), uint(pixel_height))

	if !write_ppm(config.out, pixels, pixel_width, pixel_height) {
		fmt.eprintf("hw_clay_metal: failed to write %s\n", config.out)
		os.exit(1)
	}
	if error_count != 0 {
		fmt.eprintf("hw_clay_metal: %d layout error(s) reported\n", error_count)
		os.exit(1)
	}
	fmt.printf("wrote %s (%dx%d, scale %.1f, %d frames)\n", config.out, pixel_width, pixel_height, config.scale, config.frames)
}
