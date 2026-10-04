// Draws clay render commands into a hw_odin_ui_framework draw list.
//
// Import with:
//
//	-collection:hw_clay=<hw_clay>
//	-collection:ui_framework=<hw_odin_ui_framework>
//
//	import hw_clay "hw_clay:."
//	import "ui_framework:clay"
//
// Coordinate systems: clay uses top-left origin with y down; the draw list and
// CoreText use bottom-left origin with y up. Every clay rectangle is converted,
// while text baselines are computed from the converted line box. Colour
// overlays are folded into each emitted colour with the same mix the reference
// renderers apply in a shader.

package hw_clay_ui

import "core:math"
import hw_clay "hw_clay:."
import draw "ui_framework:draw"
import coretext "ui_framework:coretext"
import ui "ui_framework:core"

MAX_FONT_HANDLES :: 16

// Image_Bundle is the payload an application stores in
// Element_Declaration.image.image_data so the renderer can find the draw list
// texture registered for the image.
Image_Bundle :: struct {
	handle: draw.Texture_Handle,
	width:  int,
	height: int,
}

Renderer :: struct {
	list:            ^draw.List,
	text:            ^coretext.Context,
	viewport_height: f32,
	fonts:           [MAX_FONT_HANDLES]ui.Font_Handle,
	// Used for font ids the app did not register, including clay's debug
	// view, which passes font id 0 for its internal text.
	default_font:    ui.Font_Handle,
	// Active overlay colours, blended into every colour while set.
	overlays:        [8]draw.Color,
	overlay_count:   int,
	// Overlays beyond the stack depth, whose end commands must not pop.
	overlay_overflow: int,
}

renderer_register_font :: proc(renderer: ^Renderer, handle: ui.Font_Handle, postscript_name: string) {
	assert(int(handle) < MAX_FONT_HANDLES)
	coretext.register_font(renderer.text, handle, postscript_name)
	renderer.fonts[handle] = handle
	if renderer.default_font == 0 {
		renderer.default_font = handle
	}
}

// font_for resolves a clay font id, falling back to the default font so that
// unregistered ids (notably clay's debug view) still produce text.
font_for :: proc(renderer: ^Renderer, id: u16) -> ui.Font_Handle {
	if int(id) >= MAX_FONT_HANDLES {
		return renderer.default_font
	}
	handle := renderer.fonts[id]
	if handle == 0 {
		return renderer.default_font
	}
	return handle
}

// rect_to_draw converts a clay bounding box to draw list space.
rect_to_draw :: proc(renderer: ^Renderer, box: hw_clay.Bounding_Box) -> draw.Rect {
	return {box.x, renderer.viewport_height - box.y - box.height, box.width, box.height}
}

color_to_draw :: proc(color: hw_clay.Color) -> draw.Color {
	return {color.r / 255.0, color.g / 255.0, color.b / 255.0, color.a / 255.0}
}

// apply_overlays folds active overlays into a colour, matching the reference
// shader's mix(elementColor, overlayColor.rgb, overlayColor.a).
apply_overlays :: proc(renderer: ^Renderer, color: draw.Color) -> draw.Color {
	result := color
	for i in 0 ..< renderer.overlay_count {
		overlay := renderer.overlays[i]
		result.r = result.r + (overlay.r - result.r) * overlay.a
		result.g = result.g + (overlay.g - result.g) * overlay.a
		result.b = result.b + (overlay.b - result.b) * overlay.a
	}
	return result
}

push_overlay :: proc(renderer: ^Renderer, color: draw.Color) {
	if renderer.overlay_count == len(renderer.overlays) {
		renderer.overlay_overflow += 1
		return
	}
	renderer.overlays[renderer.overlay_count] = color
	renderer.overlay_count += 1
}

pop_overlay :: proc(renderer: ^Renderer) {
	if renderer.overlay_overflow > 0 {
		renderer.overlay_overflow -= 1
	} else if renderer.overlay_count > 0 {
		renderer.overlay_count -= 1
	}
}

// corners_to_draw reorders clay's corner radii for the y-up draw list: bottom
// left, top left, bottom right, top right.
corners_to_draw :: proc(radius: hw_clay.Corner_Radius) -> [4]f32 {
	return {radius.bottom_left, radius.top_left, radius.bottom_right, radius.top_right}
}

render_rectangle :: proc(renderer: ^Renderer, command: hw_clay.Render_Command, data: hw_clay.Rectangle_Render_Data) {
	color := apply_overlays(renderer, color_to_draw(data.background_color))
	if color.a <= 0 {
		return
	}
	draw.solid_corners(renderer.list, rect_to_draw(renderer, command.bounding_box), color, corners_to_draw(data.corner_radius))
}

// render_border draws a uniform border as a rounded stroke, and side specific
// borders as plain rectangles, which drop corner rounding (the draw list has no
// per-side rounded stroke).
render_border :: proc(renderer: ^Renderer, command: hw_clay.Render_Command, data: hw_clay.Border_Render_Data) {
	color := apply_overlays(renderer, color_to_draw(data.color))
	if color.a <= 0 {
		return
	}
	box := command.bounding_box
	widths := data.width
	uniform := widths.left == widths.right && widths.left == widths.top && widths.left == widths.bottom && widths.left > 0
	if uniform {
		draw.solid_corners(
			renderer.list,
			rect_to_draw(renderer, box),
			color,
			corners_to_draw(data.corner_radius),
			border_thickness = f32(widths.left),
		)
		return
	}
	if widths.left > 0 {
		draw.solid(renderer.list, rect_to_draw(renderer, {x = box.x, y = box.y, width = f32(widths.left), height = box.height}), color)
	}
	if widths.right > 0 {
		draw.solid(renderer.list, rect_to_draw(renderer, {x = box.x + box.width - f32(widths.right), y = box.y, width = f32(widths.right), height = box.height}), color)
	}
	if widths.top > 0 {
		draw.solid(renderer.list, rect_to_draw(renderer, {x = box.x, y = box.y, width = box.width, height = f32(widths.top)}), color)
	}
	if widths.bottom > 0 {
		draw.solid(renderer.list, rect_to_draw(renderer, {x = box.x, y = box.y + box.height - f32(widths.bottom), width = box.width, height = f32(widths.bottom)}), color)
	}
}

render_text :: proc(renderer: ^Renderer, command: hw_clay.Render_Command, data: hw_clay.Text_Render_Data) {
	color := apply_overlays(renderer, color_to_draw(data.text_color))
	if color.a <= 0 || len(data.string_contents) == 0 {
		return
	}
	handle := font_for(renderer, data.font_id)
	// Clay has already wrapped and positioned each line, so shaping with no
	// width limit returns the same line.
	run := coretext.shape(renderer.text, handle, data.string_contents, f32(data.font_size), f32(data.letter_spacing), 0, false)
	if run == nil {
		return
	}
	box := rect_to_draw(renderer, command.bounding_box)
	// Clay already centers the natural font height within the requested line
	// height. Anchor to its adjusted top, not the possibly shorter line bottom.
	origin := ui.Vec2{box.x, box.y + box.h - run.metrics.ascent}
	coretext.emit_shaped_run(renderer.text, renderer.list, run, origin, color, "")
}

render_image :: proc(renderer: ^Renderer, command: hw_clay.Render_Command, data: hw_clay.Image_Render_Data) {
	if data.image_data == nil {
		return
	}
	// Images carry an app owned bundle so the renderer can find the registered
	// draw texture handle and source dimensions.
	bundle := (^Image_Bundle)(data.image_data)
	color := color_to_draw(data.background_color)
	if color.r == 0 && color.g == 0 && color.b == 0 && color.a == 0 {
		color = {1, 1, 1, 1}
	}
	draw.image(
		renderer.list,
		bundle.handle,
		rect_to_draw(renderer, command.bounding_box),
		// Draw UVs are normalized; uploaded image rows begin at the top.
		{0, 1, 1, -1},
		apply_overlays(renderer, color),
		corner_radii = corners_to_draw(data.corner_radius),
	)
}

// render_commands emits every command in order. Commands are already sorted by
// clay and clip regions arrive as balanced scissor start and end pairs.
render_commands :: proc(renderer: ^Renderer, commands: []hw_clay.Render_Command) {
	for command in commands {
		switch data in command.render_data {
		case hw_clay.Rectangle_Render_Data:
			render_rectangle(renderer, command, data)
		case hw_clay.Border_Render_Data:
			render_border(renderer, command, data)
		case hw_clay.Text_Render_Data:
			render_text(renderer, command, data)
		case hw_clay.Image_Render_Data:
			render_image(renderer, command, data)
		case hw_clay.Clip_Render_Data:
			#partial switch command.command_type {
			case .Scissor_Start:
				draw.push_clip(renderer.list, rect_to_draw(renderer, command.bounding_box))
			case .Scissor_End:
				draw.pop_clip(renderer.list)
			case:
			}
		case hw_clay.Overlay_Color_Render_Data:
			#partial switch command.command_type {
			case .Overlay_Color_Start:
				push_overlay(renderer, color_to_draw(data.color))
			case .Overlay_Color_End:
				pop_overlay(renderer)
			case:
			}
		case hw_clay.Custom_Render_Data:
			// Applications draw custom elements themselves.
		}
	}
}

// measure_text measures a run of text for clay using the same CoreText
// shaping the renderer draws with.
measure_text :: proc(text: string, config: ^hw_clay.Text_Config, user_data: rawptr) -> hw_clay.Dimensions {
	renderer := (^Renderer)(user_data)
	if renderer == nil || renderer.text == nil || len(text) == 0 {
		return {width = f32(config.font_size) * 0.5 * f32(math.max(len(text), 1)), height = f32(config.font_size)}
	}
	run := coretext.shape(renderer.text, font_for(renderer, config.font_id), text, f32(config.font_size), f32(config.letter_spacing), 0, false)
	if run == nil {
		return {height = f32(config.font_size)}
	}
	return {width = run.metrics.width, height = run.metrics.ascent + run.metrics.descent}
}
