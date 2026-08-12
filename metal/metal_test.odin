package metal

import "core:testing"
import ui "ui_framework:core"
import coretext "ui_framework:coretext"
import draw "ui_framework:draw"

@(test)
batch_uniforms_match_metal_constant_layout_test :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(Batch_Uniforms), 48)
}

@(test)
gpu_quad_instance_keeps_layout_and_corner_shape_test :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(GPU_Quad_Instance), 128)
	instance := gpu_instance(draw.Quad_Instance{corner_shape = .Squircle})
	testing.expect_value(t, instance.corner_shape, u32(draw.Corner_Shape.Squircle))
}

foreign import metal_framework "system:Metal.framework"
foreign metal_framework {
	MTLCreateSystemDefaultDevice :: proc "c" () -> Object ---
}

msg_void_get_bytes :: proc(receiver: Object, selector: Selector, bytes: rawptr, bytes_per_row: uint, region: MTL_Region, level: uint) {
	p := transmute(proc "c" (_: Object, _: Selector, _: rawptr, _: uint, _: MTL_Region, _: uint))send_address
	p(receiver, selector, bytes, bytes_per_row, region, level)
}

@(test)
offscreen_composition_preserves_submission_order_test :: proc(t: ^testing.T) {
	if !load_objc() {testing.expect(t, false); return}
	device := MTLCreateSystemDefaultDevice()
	if device == nil {testing.expect(t, false); return}
	renderer: Renderer
	testing.expect(t, renderer_init(&renderer, device, allow_runtime_fallback = true))
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
	testing.expect(t, encode(&renderer, encoder, &list, {64, 64}))
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
	testing.expect(t, renderer_init(&renderer, device, allow_runtime_fallback = true))
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
	testing.expect(t, encode(&renderer, encoder, &list, {96, 32}))
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
	round_corner := (4*96+1)*4
	squircle_corner := (4*96+33)*4
	border_corner := (4*96+65)*4
	border_center := (12*96+76)*4
	testing.expect(t, pixels[round_corner] < 32)
	testing.expect(t, pixels[squircle_corner] > 224)
	testing.expect(t, pixels[border_corner] > 192)
	testing.expect(t, pixels[border_center] < 8)
}

@(test)
coretext_glyph_atlas_composes_background_and_modal_text_in_one_stream_test :: proc(t: ^testing.T) {
	if !load_objc() {testing.expect(t, false); return}
	device := MTLCreateSystemDefaultDevice()
	if device == nil {testing.expect(t, false); return}
	renderer: Renderer
	testing.expect(t, renderer_init(&renderer, device, allow_runtime_fallback = true))
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
	testing.expect(t, encode(&renderer, encoder, output.draw_list, {256, 128}, 2))
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
	testing.expect(t, renderer_init(&renderer, device, allow_runtime_fallback = true))
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
