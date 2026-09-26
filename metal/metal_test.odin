package metal

import "core:os"
import "core:testing"
import ui "ui_framework:core"
import coretext "ui_framework:coretext"
import draw "ui_framework:draw"

// test.sh compiles shaders/ui.metal into the working directory before testing.
TEST_METALLIB_PATH :: "ui.metallib"

test_renderer_init :: proc(t: ^testing.T, renderer: ^Renderer, device: Object) -> bool {
	metallib, read_error := os.read_entire_file(TEST_METALLIB_PATH, context.allocator)
	if !testing.expectf(t, read_error == nil, "read %s: %v", TEST_METALLIB_PATH, read_error) {return false}
	defer delete(metallib)
	if !renderer_init(renderer, device, metallib_data = metallib) {return false}
	return testing.expect(t, !renderer.runtime_compiled)
}

@(test)
renderer_requires_precompiled_library_unless_fallback_is_requested_test :: proc(t: ^testing.T) {
	if !load_objc() {testing.expect(t, false); return}
	device := MTLCreateSystemDefaultDevice()
	if device == nil {testing.expect(t, false); return}
	defer release(device)

	renderer: Renderer
	testing.expect(t, !renderer_init(&renderer, device))
	testing.expect(t, renderer.pipeline == nil)
	invalid := []u8{0, 1, 2, 3}
	testing.expect(t, !renderer_init(&renderer, device, metallib_data = invalid))
	testing.expect(t, renderer.pipeline == nil)

	testing.expect(t, test_renderer_init(t, &renderer, device))
	testing.expect(t, renderer.pipeline != nil)
	testing.expect(t, renderer.path_pipeline != nil)
	renderer_destroy(&renderer)
}

@(test)
batch_uniforms_match_metal_constant_layout_test :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(Batch_Uniforms), 48)
	testing.expect_value(t, size_of(GPU_Path_Vertex), 16)
	testing.expect_value(t, size_of(Path_Uniforms), 80)
}

@(test)
gpu_quad_instance_keeps_layout_corner_shape_and_effect_offset_test :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(GPU_Quad_Instance), 144)
	instance := gpu_instance(draw.Quad_Instance{
		corner_shape = .Squircle,
		effect_offset = {-1.25, 1.25},
	})
	testing.expect_value(t, instance.corner_shape, u32(draw.Corner_Shape.Squircle))
	testing.expect_value(t, instance.effect_offset, [2]f32{-1.25, 1.25})
}

foreign import metal_framework "system:Metal.framework"
foreign metal_framework {
	MTLCreateSystemDefaultDevice :: proc "c" () -> Object ---
}

@(test)
offscreen_vector_paths_render_convex_compound_and_stroked_geometry_test :: proc(t: ^testing.T) {
	if !load_objc() {testing.expect(t, false); return}
	device := MTLCreateSystemDefaultDevice()
	if device == nil {testing.expect(t, false); return}
	renderer: Renderer
	testing.expect(t, test_renderer_init(t, &renderer, device))
	defer renderer_destroy(&renderer)

	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		80,
		96,
		64,
		false,
	)
	target := msg_id_id(device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	testing.expect(t, target != nil)
	defer release(target)
	queue := msg_id(device, sel_registerName("newCommandQueue"))
	testing.expect(t, queue != nil)
	defer release(queue)
	command_buffer := msg_id(queue, sel_registerName("commandBuffer"))

	list: draw.List
	draw.list_init(&list, pixel_ratio = 2)
	defer draw.list_destroy(&list)
	draw.path_begin(&list)
	draw.path_circle(&list, 16, 32, 10)
	draw.path_fill(&list, {1, 0, 0, 1})
	draw.path_begin(&list)
	draw.path_circle(&list, 48, 32, 13)
	draw.path_circle(&list, 48, 32, 6)
	draw.path_solidity(&list, .Hole)
	draw.path_fill(&list, {0, 1, 0, 1}, .Even_Odd)
	draw.path_begin(&list)
	draw.path_move_to(&list, 70, 20)
	draw.path_line_to(&list, 90, 44)
	draw.path_stroke(&list, {0, 0, 1, 1}, 6, cap = .Round)

	testing.expect(t, encode_to_drawable(
		&renderer,
		command_buffer,
		target,
		&list,
		{96, 64},
		1,
		{0, 0, 0, 1},
	))
	msg_void(command_buffer, sel_registerName("commit"))
	msg_void(command_buffer, sel_registerName("waitUntilCompleted"))

	pixels := make([]u8, 96*64*4, context.temp_allocator)
	defer delete(pixels, context.temp_allocator)
	msg_void_get_bytes(
		target,
		sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
		raw_data(pixels),
		96*4,
		{size = {96, 64, 1}},
		0,
	)
	circle := (32*96+16)*4
	donut_ring := (32*96+58)*4
	donut_hole := (32*96+48)*4
	stroke := (32*96+80)*4
	testing.expect(t, pixels[circle+2] >= 250 && pixels[circle+1] <= 2)
	testing.expect(t, pixels[donut_ring+1] >= 250 && pixels[donut_ring+2] <= 2)
	testing.expect(t, pixels[donut_hole] <= 2 && pixels[donut_hole+1] <= 2 && pixels[donut_hole+2] <= 2)
	testing.expect(t, pixels[stroke] >= 250 && pixels[stroke+1] <= 2)
}

msg_void_get_bytes :: proc(receiver: Object, selector: Selector, bytes: rawptr, bytes_per_row: uint, region: MTL_Region, level: uint) {
	p := cast(proc "c" (_: Object, _: Selector, _: rawptr, _: uint, _: MTL_Region, _: uint))send_address
	p(receiver, selector, bytes, bytes_per_row, region, level)
}

@(test)
offscreen_composition_preserves_submission_order_test :: proc(t: ^testing.T) {
	if !load_objc() {testing.expect(t, false); return}
	device := MTLCreateSystemDefaultDevice()
	if device == nil {testing.expect(t, false); return}
	renderer: Renderer
	testing.expect(t, test_renderer_init(t, &renderer, device))
	defer renderer_destroy(&renderer)

	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		80,
		64,
		64,
		false,
	)
	target := msg_id_id(device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	testing.expect(t, target != nil)
	defer release(target)
	queue := msg_id(device, sel_registerName("newCommandQueue"))
	testing.expect(t, queue != nil)
	defer release(queue)
	command_buffer := msg_id(queue, sel_registerName("commandBuffer"))
	pass := msg_id(objc_getClass("MTLRenderPassDescriptor"), sel_registerName("renderPassDescriptor"))
	attachments := msg_id(pass, sel_registerName("colorAttachments"))
	attachment := msg_id_u(attachments, sel_registerName("objectAtIndexedSubscript:"), 0)
	msg_void_id(attachment, sel_registerName("setTexture:"), target)
	msg_void_u(attachment, sel_registerName("setLoadAction:"), 2)
	msg_void_u(attachment, sel_registerName("setStoreAction:"), 1)
	msg_void_clear_color(attachment, sel_registerName("setClearColor:"), {0, 0, 0, 1})
	encoder := msg_id_id(command_buffer, sel_registerName("renderCommandEncoderWithDescriptor:"), pass)
	testing.expect(t, encoder != nil)

	list: draw.List
	draw.list_init(&list)
	defer draw.list_destroy(&list)
	draw.solid(&list, {0, 0, 64, 64}, {1, 0, 0, 1}, label = "background text")
	draw.solid(&list, {0, 0, 64, 64}, {0, 0, 0, 0.5}, label = "backdrop")
	draw.solid(&list, {16, 16, 32, 32}, {0, 1, 0, 1}, label = "modal surface")
	testing.expect(t, encode(&renderer, command_buffer, encoder, &list, {64, 64}))
	msg_void(encoder, sel_registerName("endEncoding"))
	msg_void(command_buffer, sel_registerName("commit"))
	msg_void(command_buffer, sel_registerName("waitUntilCompleted"))

	pixels := make([]u8, 64*64*4, context.temp_allocator)
	defer delete(pixels, context.temp_allocator)
	msg_void_get_bytes(
		target,
		sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
		raw_data(pixels),
		64*4,
		{size = {64, 64, 1}},
		0,
	)
	outside := (8*64+8)*4
	inside := (32*64+32)*4
	testing.expect(t, pixels[outside+2] >= 120 && pixels[outside+2] <= 136)
	testing.expect(t, pixels[outside+1] <= 2)
	testing.expect(t, pixels[inside+1] >= 250)
	testing.expect(t, pixels[inside+2] <= 2)
}

@(test)
offscreen_squircle_contour_and_border_are_distinct_from_round_test :: proc(t: ^testing.T) {
	if !load_objc() {testing.expect(t, false); return}
	device := MTLCreateSystemDefaultDevice()
	if device == nil {testing.expect(t, false); return}
	renderer: Renderer
	testing.expect(t, test_renderer_init(t, &renderer, device))
	defer renderer_destroy(&renderer)

	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		80,
		96,
		32,
		false,
	)
	target := msg_id_id(device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	testing.expect(t, target != nil)
	defer release(target)
	queue := msg_id(device, sel_registerName("newCommandQueue"))
	testing.expect(t, queue != nil)
	defer release(queue)
	command_buffer := msg_id(queue, sel_registerName("commandBuffer"))
	pass := msg_id(objc_getClass("MTLRenderPassDescriptor"), sel_registerName("renderPassDescriptor"))
	attachments := msg_id(pass, sel_registerName("colorAttachments"))
	attachment := msg_id_u(attachments, sel_registerName("objectAtIndexedSubscript:"), 0)
	msg_void_id(attachment, sel_registerName("setTexture:"), target)
	msg_void_u(attachment, sel_registerName("setLoadAction:"), 2)
	msg_void_u(attachment, sel_registerName("setStoreAction:"), 1)
	msg_void_clear_color(attachment, sel_registerName("setClearColor:"), {0, 0, 0, 1})
	encoder := msg_id_id(command_buffer, sel_registerName("renderCommandEncoderWithDescriptor:"), pass)
	testing.expect(t, encoder != nil)

	list: draw.List
	draw.list_init(&list)
	defer draw.list_destroy(&list)
	draw.solid(&list, {0, 0, 24, 24}, {1, 1, 1, 1}, 12, edge_softness = 0.5)
	draw.solid(
		&list,
		{32, 0, 24, 24},
		{1, 1, 1, 1},
		12,
		edge_softness = 0.5,
		corner_shape = .Squircle,
	)
	draw.solid(
		&list,
		{64, 0, 24, 24},
		{1, 1, 1, 1},
		12,
		2,
		0.5,
		corner_shape = .Squircle,
	)
	testing.expect(t, encode(&renderer, command_buffer, encoder, &list, {96, 32}))
	msg_void(encoder, sel_registerName("endEncoding"))
	msg_void(command_buffer, sel_registerName("commit"))
	msg_void(command_buffer, sel_registerName("waitUntilCompleted"))

	pixels := make([]u8, 96*32*4, context.temp_allocator)
	defer delete(pixels, context.temp_allocator)
	msg_void_get_bytes(
		target,
		sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
		raw_data(pixels),
		96*4,
		{size = {96, 32, 1}},
		0,
	)
	// UI Y is up. Texture row = viewport_h - ui_y.
	round_corner := ((32 - 4) * 96 + 1) * 4
	squircle_corner := ((32 - 4) * 96 + 33) * 4
	border_corner := ((32 - 4) * 96 + 65) * 4
	border_center := ((32 - 12) * 96 + 76) * 4
	testing.expect(t, pixels[round_corner] < 32)
	testing.expect(t, pixels[squircle_corner] > 224)
	testing.expect(t, pixels[border_corner] > 192)
	testing.expect(t, pixels[border_center] < 8)
}

@(test)
offscreen_y_band_keeps_top_half_ring_and_clears_the_mid :: proc(t: ^testing.T) {
	if !load_objc() {testing.expect(t, false); return}
	device := MTLCreateSystemDefaultDevice()
	if device == nil {testing.expect(t, false); return}
	renderer: Renderer
	testing.expect(t, test_renderer_init(t, &renderer, device))
	defer renderer_destroy(&renderer)

	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		80,
		96,
		64,
		false,
	)
	target := msg_id_id(device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	testing.expect(t, target != nil)
	defer release(target)
	queue := msg_id(device, sel_registerName("newCommandQueue"))
	testing.expect(t, queue != nil)
	defer release(queue)
	command_buffer := msg_id(queue, sel_registerName("commandBuffer"))

	list: draw.List
	draw.list_init(&list)
	defer draw.list_destroy(&list)
	draw.y_band(
		&list,
		{16, 8, 64, 48},
		{1, 1, 1, 1},
		24,
		4,
		0.5,
		1,
		0.05,
	)
	testing.expect(t, encode_to_drawable(
		&renderer,
		command_buffer,
		target,
		&list,
		{96, 64},
		1,
		{0, 0, 0, 1},
	))
	msg_void(command_buffer, sel_registerName("commit"))
	msg_void(command_buffer, sel_registerName("waitUntilCompleted"))

	pixels := make([]u8, 96*64*4, context.temp_allocator)
	defer delete(pixels, context.temp_allocator)
	msg_void_get_bytes(
		target,
		sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
		raw_data(pixels),
		96*4,
		{size = {96, 64, 1}},
		0,
	)
	// UI Y is up. Texture row = viewport_h - ui_y.
	top := ((64 - 55) * 96 + 48) * 4
	mid := ((64 - 32) * 96 + 18) * 4
	bottom := ((64 - 9) * 96 + 48) * 4
	testing.expect(t, pixels[top] > 192)
	testing.expect(t, pixels[mid] < 32)
	testing.expect(t, pixels[bottom] < 32)
}

@(test)
offscreen_y_ramp_ring_fades_from_top_highlight_to_bottom_glow_test :: proc(t: ^testing.T) {
	if !load_objc() {testing.expect(t, false); return}
	device := MTLCreateSystemDefaultDevice()
	if device == nil {testing.expect(t, false); return}
	renderer: Renderer
	testing.expect(t, test_renderer_init(t, &renderer, device))
	defer renderer_destroy(&renderer)

	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		80,
		96,
		64,
		false,
	)
	target := msg_id_id(device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	testing.expect(t, target != nil)
	defer release(target)
	queue := msg_id(device, sel_registerName("newCommandQueue"))
	testing.expect(t, queue != nil)
	defer release(queue)
	command_buffer := msg_id(queue, sel_registerName("commandBuffer"))

	list: draw.List
	draw.list_init(&list)
	defer draw.list_destroy(&list)
	draw.y_ramp(
		&list,
		{16, 8, 64, 48},
		{1, 0, 0, 1},
		{0, 0, 0, 1},
		{1, 1, 1, 1},
		24,
		6,
		0.33,
		0.5,
	)
	testing.expect(t, encode_to_drawable(
		&renderer,
		command_buffer,
		target,
		&list,
		{96, 64},
		1,
		{0, 0, 1, 1},
	))
	msg_void(command_buffer, sel_registerName("commit"))
	msg_void(command_buffer, sel_registerName("waitUntilCompleted"))

	pixels := make([]u8, 96*64*4, context.temp_allocator)
	defer delete(pixels, context.temp_allocator)
	msg_void_get_bytes(
		target,
		sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
		raw_data(pixels),
		96*4,
		{size = {96, 64, 1}},
		0,
	)
	top := ((64 - 53) * 96 + 48) * 4
	mid := ((64 - 32) * 96 + 18) * 4
	bottom := ((64 - 12) * 96 + 48) * 4
	testing.expect(t, pixels[top] > 192)
	testing.expect(t, pixels[top + 1] > 192)
	testing.expect(t, pixels[mid] < 48)
	testing.expect(t, pixels[mid + 1] < 48)
	testing.expect(t, pixels[bottom + 2] > 192)
	testing.expect(t, pixels[bottom + 1] < 48)
}

@(test)
offscreen_inset_shadow_stays_clipped_and_favors_its_offset_edge_test :: proc(t: ^testing.T) {
	if !load_objc() {testing.expect(t, false); return}
	device := MTLCreateSystemDefaultDevice()
	if device == nil {testing.expect(t, false); return}
	renderer: Renderer
	testing.expect(t, test_renderer_init(t, &renderer, device))
	defer renderer_destroy(&renderer)

	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		80,
		96,
		64,
		false,
	)
	target := msg_id_id(device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	testing.expect(t, target != nil)
	defer release(target)
	queue := msg_id(device, sel_registerName("newCommandQueue"))
	testing.expect(t, queue != nil)
	defer release(queue)
	command_buffer := msg_id(queue, sel_registerName("commandBuffer"))

	list: draw.List
	draw.list_init(&list)
	defer draw.list_destroy(&list)
	draw.solid(&list, {16, 16, 64, 32}, {0.75, 0.75, 0.75, 1}, 16)
	draw.inset_shadow(
		&list,
		{16, 16, 64, 32},
		{0, 0, 0, 0.5},
		16,
		{-2, 0},
		1.5,
	)
	testing.expect(t, encode_to_drawable(
		&renderer,
		command_buffer,
		target,
		&list,
		{96, 64},
		1,
		{1, 1, 1, 1},
	))
	msg_void(command_buffer, sel_registerName("commit"))
	msg_void(command_buffer, sel_registerName("waitUntilCompleted"))

	pixels := make([]u8, 96*64*4, context.temp_allocator)
	defer delete(pixels, context.temp_allocator)
	msg_void_get_bytes(
		target,
		sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
		raw_data(pixels),
		96*4,
		{size = {96, 64, 1}},
		0,
	)
	left := (32*96+17)*4
	right := (32*96+78)*4
	outside := (32*96+14)*4
	testing.expect(t, pixels[left] < pixels[right])
	testing.expect(t, pixels[outside] >= 250)
}

@(test)
coretext_glyph_atlas_composes_background_and_modal_text_in_one_stream_test :: proc(t: ^testing.T) {
	if !load_objc() {testing.expect(t, false); return}
	device := MTLCreateSystemDefaultDevice()
	if device == nil {testing.expect(t, false); return}
	renderer: Renderer
	testing.expect(t, test_renderer_init(t, &renderer, device))
	defer renderer_destroy(&renderer)
	begin_texture_frame(&renderer)

	text: coretext.Context
	coretext.context_init(&text)
	defer coretext.context_destroy(&text)
	coretext.register_font(&text, ui.Font_Handle(1), "Menlo-Regular")
	coretext.begin_frame(&text, 2, atlas_io(&renderer))
	ui_context: ui.Context
	ui.context_init(&ui_context)
	defer ui.context_destroy(&ui_context)
	frame := ui.begin_frame(
		&ui_context,
		{viewport = {0, 0, 256, 128}, backing_scale = 2},
		coretext.backend(&text),
	)
	defer ui.frame_destroy(&frame)
	_ = ui.box_add(&frame, ui.Box{
		key = ui.key_from_string("background label"),
		debug_label = "background surface",
		text = "BACKGROUND",
		layout = {position = .Absolute, absolute = {0, 0, 256, 128}},
		style = {
			background = {0.1, 0.1, 0.1, 1},
			text = {1, 1, 1, 1},
			opacity = 1,
			text_style = {font = 1, size = 20, horizontal = .Center, vertical = .Center},
		},
		flags = {.Draw_Background, .Draw_Text},
	})
	_ = ui.box_begin(&frame, ui.Box{
		key = ui.key_from_string("modal backdrop"),
		debug_label = "backdrop",
		layout = {position = .Absolute, absolute = {0, 0, 256, 128}, flow = .Overlay},
		style = {background = {0, 0, 0, 0.75}, opacity = 1},
		flags = {.Draw_Background, .Modal_Root},
	})
	_ = ui.box_add(&frame, ui.Box{
		key = ui.key_from_string("modal label"),
		debug_label = "modal surface",
		text = "SETTINGS",
		layout = {position = .Absolute, absolute = {64, 32, 128, 64}},
		style = {
			background = {0.05, 0.05, 0.05, 1},
			text = {1, 1, 1, 1},
			opacity = 1,
			text_style = {font = 1, size = 20, horizontal = .Center, vertical = .Center},
		},
		flags = {.Draw_Background, .Draw_Text},
	})
	ui.box_end(&frame)
	output := ui.end_frame(&frame)
	coretext.flush(&text)

	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		80,
		512,
		256,
		false,
	)
	target := msg_id_id(device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	defer release(target)
	queue := msg_id(device, sel_registerName("newCommandQueue"))
	defer release(queue)
	command_buffer := msg_id(queue, sel_registerName("commandBuffer"))
	pass := msg_id(objc_getClass("MTLRenderPassDescriptor"), sel_registerName("renderPassDescriptor"))
	attachments := msg_id(pass, sel_registerName("colorAttachments"))
	attachment := msg_id_u(attachments, sel_registerName("objectAtIndexedSubscript:"), 0)
	msg_void_id(attachment, sel_registerName("setTexture:"), target)
	msg_void_u(attachment, sel_registerName("setLoadAction:"), 2)
	msg_void_u(attachment, sel_registerName("setStoreAction:"), 1)
	msg_void_clear_color(attachment, sel_registerName("setClearColor:"), {0, 0, 0, 1})
	encoder := msg_id_id(command_buffer, sel_registerName("renderCommandEncoderWithDescriptor:"), pass)
	testing.expect(t, encode(&renderer, command_buffer, encoder, output.draw_list, {256, 128}, 2))
	msg_void(encoder, sel_registerName("endEncoding"))
	msg_void(command_buffer, sel_registerName("commit"))
	msg_void(command_buffer, sel_registerName("waitUntilCompleted"))

	background_glyphs, modal_glyphs := 0, 0
	backdrop_index, modal_surface_index := -1, -1
	for entry, index in output.draw_list.trace {
		if entry.kind == .Glyph && entry.label == "BACKGROUND" {background_glyphs += 1}
		if entry.kind == .Glyph && entry.label == "SETTINGS" {
			modal_glyphs += 1
		}
		if entry.label == "backdrop" {backdrop_index = index}
		if entry.label == "modal surface" {modal_surface_index = index}
	}
	testing.expect(t, background_glyphs > 0 && modal_glyphs > 0)
	testing.expect(t, backdrop_index > background_glyphs)
	testing.expect(t, modal_surface_index > backdrop_index)

	pixels := make([]u8, 512*256*4, context.temp_allocator)
	defer delete(pixels, context.temp_allocator)
	msg_void_get_bytes(
		target,
		sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
		raw_data(pixels),
		512*4,
		{size = {512, 256, 1}},
		0,
	)
	modal_max := u8(0)
	atlas_readback := make([]u8, text.pages[0].width*text.pages[0].height, context.temp_allocator)
	defer delete(atlas_readback, context.temp_allocator)
	msg_void_get_bytes(
		Object(rawptr(uintptr(text.pages[0].native))),
		sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
		raw_data(atlas_readback),
		uint(text.pages[0].width),
		{size = {uint(text.pages[0].width), uint(text.pages[0].height), 1}},
		0,
	)
	atlas_gpu_max := u8(0)
	for pixel in atlas_readback {atlas_gpu_max = max(atlas_gpu_max, pixel)}
	for y in 64 ..< 192 {
		for x in 128 ..< 384 {
			modal_max = max(modal_max, pixels[(y*512+x)*4+1])
		}
	}
	testing.expect(t, atlas_gpu_max > 0)
	testing.expect(t, modal_max > 200)
}

@(test)
overlapping_max_shadows_keep_peak_coverage_test :: proc(t: ^testing.T) {
	if !load_objc() {testing.expect(t, false); return}
	device := MTLCreateSystemDefaultDevice()
	if device == nil {testing.expect(t, false); return}
	renderer: Renderer
	testing.expect(t, test_renderer_init(t, &renderer, device))
	defer renderer_destroy(&renderer)

	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		80,
		64,
		64,
		false,
	)
	msg_void_u(descriptor, sel_registerName("setUsage:"), 5)
	target := msg_id_id(device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	testing.expect(t, target != nil)
	defer release(target)
	queue := msg_id(device, sel_registerName("newCommandQueue"))
	testing.expect(t, queue != nil)
	defer release(queue)
	command_buffer := msg_id(queue, sel_registerName("commandBuffer"))

	list: draw.List
	draw.list_init(&list)
	defer draw.list_destroy(&list)
	draw.solid(
		&list,
		{8, 8, 40, 40},
		{0, 0, 0, 0.06},
		0,
		0,
		0.5,
		"shadow a",
		.Max,
		.Shadow,
	)
	draw.solid(
		&list,
		{16, 16, 40, 40},
		{0, 0, 0, 0.06},
		0,
		0,
		0.5,
		"shadow b",
		.Max,
		.Shadow,
	)
	testing.expect(t, encode_to_drawable(
		&renderer,
		command_buffer,
		target,
		&list,
		{64, 64},
		1,
		{1, 1, 1, 1},
	))
	msg_void(command_buffer, sel_registerName("commit"))
	msg_void(command_buffer, sel_registerName("waitUntilCompleted"))

	pixels := make([]u8, 64*64*4, context.temp_allocator)
	defer delete(pixels, context.temp_allocator)
	msg_void_get_bytes(
		target,
		sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
		raw_data(pixels),
		64*4,
		{size = {64, 64, 1}},
		0,
	)
	overlap := (32*64+32)*4
	channel := pixels[overlap+1]
	testing.expect(t, channel >= 232 && channel <= 248)
}

@(test)
offscreen_drop_shadow_punches_caster_and_keeps_the_halo_test :: proc(t: ^testing.T) {
	if !load_objc() {testing.expect(t, false); return}
	device := MTLCreateSystemDefaultDevice()
	if device == nil {testing.expect(t, false); return}
	renderer: Renderer
	testing.expect(t, test_renderer_init(t, &renderer, device))
	defer renderer_destroy(&renderer)

	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		80,
		64,
		64,
		false,
	)
	msg_void_u(descriptor, sel_registerName("setUsage:"), 5)
	target := msg_id_id(device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	testing.expect(t, target != nil)
	defer release(target)
	queue := msg_id(device, sel_registerName("newCommandQueue"))
	testing.expect(t, queue != nil)
	defer release(queue)
	command_buffer := msg_id(queue, sel_registerName("commandBuffer"))

	list: draw.List
	draw.list_init(&list)
	defer draw.list_destroy(&list)
	draw.drop_shadow(
		&list,
		{8, 4, 48, 56},
		{0, 0, 0, 0.7},
		8,
		8,
		{8, 16, 32, 32},
		8,
	)
	testing.expect(t, encode_to_drawable(
		&renderer,
		command_buffer,
		target,
		&list,
		{64, 64},
		1,
		{1, 1, 1, 1},
	))
	msg_void(command_buffer, sel_registerName("commit"))
	msg_void(command_buffer, sel_registerName("waitUntilCompleted"))

	pixels := make([]u8, 64*64*4, context.temp_allocator)
	defer delete(pixels, context.temp_allocator)
	msg_void_get_bytes(
		target,
		sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
		raw_data(pixels),
		64*4,
		{size = {64, 64, 1}},
		0,
	)
	// UI Y is up. Caster center (32, 36) -> row 28. Halo below at (32, 12) -> row 52.
	inside := ((64 - 36) * 64 + 32) * 4
	halo := ((64 - 12) * 64 + 32) * 4
	testing.expect(t, pixels[inside+1] >= 240)
	testing.expect(t, pixels[halo+1] < 200)
}
