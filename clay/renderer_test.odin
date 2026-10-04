#+build darwin
package hw_clay_ui

import "core:testing"
import hw_clay "hw_clay:."
import coretext "ui_framework:coretext"
import draw "ui_framework:draw"

// Exercise real shaping and glyph placement without a window or GPU.
@(test)
explicit_line_height_preserves_centered_baseline :: proc(t: ^testing.T) {
	text: coretext.Context
	coretext.context_init(&text)
	defer coretext.context_destroy(&text)
	coretext.begin_frame(&text, 2, {
		create = proc(_: rawptr, _: coretext.Atlas_Format, _: int, _: int) -> u64 {return 1},
		bind = proc(_: rawptr, _: u64) -> draw.Texture_Handle {return draw.Texture_Handle(1)},
	})
	list: draw.List
	draw.list_init(&list)
	defer draw.list_destroy(&list)
	renderer := Renderer{list = &list, text = &text, viewport_height = 200}
	renderer_register_font(&renderer, 1, "Menlo-Regular")
	run := coretext.shape(&text, 1, "Agyp", 13, 0, 0, false)
	natural_height := run.metrics.ascent + run.metrics.descent
	memory := make([]u8, hw_clay.min_memory_size())
	defer delete(memory)
	ctx: hw_clay.Context
	testing.expect(t, hw_clay.initialize(&ctx, memory, {200, 200}))
	hw_clay.set_measure_text_function(&ctx, measure_text, &renderer)
	for height in ([3]u16{12, 16, 32}) {
		draw.list_reset(&list)
		hw_clay.begin_layout(&ctx)
		hw_clay.push_text(&ctx, "Agyp", {font_id = 1, font_size = 13, line_height = height, color = {255, 255, 255, 255}})
		commands := hw_clay.end_layout(&ctx, 0)
		render_commands(&renderer, commands)
		testing.expect(t, len(list.trace) > 0)
		actual_y := list.trace[0].rect.y
		draw.list_reset(&list)
		baseline := 200 - (f32(height) + natural_height) / 2 + run.metrics.descent
		coretext.emit_shaped_run(&text, &list, run, {0, baseline}, {1, 1, 1, 1}, "")
		testing.expect(t, actual_y == list.trace[0].rect.y, "custom line height must center the glyph baseline")
	}
}

@(test)
images_sample_entire_texture_upright :: proc(t: ^testing.T) {
	list: draw.List
	draw.list_init(&list)
	defer draw.list_destroy(&list)
	renderer := Renderer{list=&list, viewport_height=400}
	for dimensions in ([3][2]int{{2,2},{640,480},{300,900}}) {
		draw.list_reset(&list)
		bundle := Image_Bundle{handle=1,width=dimensions[0],height=dimensions[1]}
		render_image(&renderer,{bounding_box={x=10,y=20,width=100,height=200}},{image_data=&bundle})
		testing.expect_value(t,len(list.batches),1)
		if len(list.batches)!=1 {continue}
		testing.expect_value(t,list.batches[0].instances[0].src,draw.Rect{0,1,1,-1})
		testing.expect_value(t,list.batches[0].instances[0].dst,draw.Rect{10,180,100,200})
	}
}

@(test)
overlay_overflow_and_large_font_ids_are_balanced :: proc(t: ^testing.T) {
	renderer := Renderer{default_font = 3}
	testing.expect_value(t, font_for(&renderer, 500), 3)
	for _ in 0 ..< len(renderer.overlays) + 2 {
		push_overlay(&renderer, {1, 0, 0, 1})
	}
	pop_overlay(&renderer)
	pop_overlay(&renderer)
	testing.expect_value(t, renderer.overlay_count, len(renderer.overlays))
	pop_overlay(&renderer)
	testing.expect_value(t, renderer.overlay_count, len(renderer.overlays) - 1)
}

@(test)
corner_radii_reach_the_draw_list_in_y_up_order :: proc(t: ^testing.T) {
	list: draw.List
	draw.list_init(&list)
	defer draw.list_destroy(&list)
	renderer := Renderer{list = &list, viewport_height = 100}
	radius := hw_clay.Corner_Radius{top_left = 1, top_right = 2, bottom_left = 3, bottom_right = 4}
	render_rectangle(&renderer, {bounding_box = {0, 0, 20, 20}}, {background_color = {255, 255, 255, 255}, corner_radius = radius})
	bundle := Image_Bundle{handle = 1, width = 2, height = 2}
	render_image(&renderer, {bounding_box = {0, 0, 20, 20}}, {image_data = &bundle, corner_radius = radius})
	for batch in list.batches {
		testing.expect_value(t, batch.instances[0].corner_radii, [4]f32{3, 1, 4, 2})
	}
	testing.expect_value(t, len(list.batches), 2)
}
