package metal

import "core:testing"
import draw "ui_framework:draw"

Surface_Test :: struct {
	renderer: Renderer,
	queue:    Object,
	target:   Object, // Shared 64x32-pixel readback target.
}

SURFACE_TEST_POINTS :: [2]f32{32, 16}
SURFACE_TEST_SCALE :: f32(2)

surface_test_init :: proc(t: ^testing.T, value: ^Surface_Test) -> bool {
	if !testing.expect(t, load_objc()) {return false}
	device := MTLCreateSystemDefaultDevice()
	if !testing.expect(t, device != nil, "Metal device required") {return false}
	if !test_renderer_init(t, &value.renderer, device) {return false}
	value.queue = msg_id(device, sel_registerName("newCommandQueue"))
	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		80,
		64,
		32,
		false,
	)
	msg_void_u(descriptor, sel_registerName("setUsage:"), MTL_TEXTURE_USAGE_RENDER_TARGET)
	value.target = msg_id_id(device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	return testing.expect(t, value.queue != nil && value.target != nil)
}

surface_test_destroy :: proc(value: ^Surface_Test) {
	release(value.target)
	release(value.queue)
	device := value.renderer.device
	renderer_destroy(&value.renderer)
	release(device)
}

surface_test_submit :: proc(command_buffer: Object) -> bool {
	msg_void(command_buffer, sel_registerName("commit"))
	msg_void(command_buffer, sel_registerName("waitUntilCompleted"))
	return upload_status(command_buffer) == MTL_COMMAND_BUFFER_STATUS_COMPLETED
}

// Composites the surface into the readback target and returns the BGRA pixel at
// (x, y), counting rows from the top.
surface_test_composite_pixel :: proc(t: ^testing.T, value: ^Surface_Test, surface: ^Surface, x, y: int) -> [4]u8 {
	list: draw.List
	draw.list_init(&list)
	defer draw.list_destroy(&list)
	surface_composite(&list, surface, {0, 0, SURFACE_TEST_POINTS[0], SURFACE_TEST_POINTS[1]})
	command_buffer := msg_id(value.queue, sel_registerName("commandBuffer"))
	testing.expect(t, encode_to_drawable(&value.renderer, command_buffer, value.target, &list, SURFACE_TEST_POINTS, SURFACE_TEST_SCALE))
	testing.expect(t, surface_test_submit(command_buffer))
	pixels: [64 * 32 * 4]u8
	msg_void_get_bytes(
		value.target,
		sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
		&pixels,
		64 * 4,
		{size = {64, 32, 1}},
		0,
	)
	offset := (y * 64 + x) * 4
	return {pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3]}
}

@(test)
persistent_texture_handles_survive_frames_and_recycle_test :: proc(t: ^testing.T) {
	value: Surface_Test
	if !surface_test_init(t, &value) {return}
	defer surface_test_destroy(&value)
	renderer := &value.renderer

	first := register_persistent_texture(renderer, value.target)
	second := register_persistent_texture(renderer, renderer.white_texture)
	testing.expect(t, first >= PERSISTENT_HANDLE_BASE)
	testing.expect(t, first != second)
	frame := register_texture(renderer, renderer.white_texture)
	testing.expect(t, frame < PERSISTENT_HANDLE_BASE)
	begin_texture_frame(renderer)
	// Frame handles expire with the frame; persistent ones do not.
	testing.expect(t, texture_for_handle(renderer, first) == value.target)
	testing.expect(t, texture_for_handle(renderer, second) == renderer.white_texture)

	unregister_persistent_texture(renderer, first)
	testing.expect(t, texture_for_handle(renderer, first) == renderer.white_texture)
	third := register_persistent_texture(renderer, value.target)
	testing.expect_value(t, third, first)
	unregister_persistent_texture(renderer, second)
	unregister_persistent_texture(renderer, third)
}

@(test)
surface_paints_once_and_composites_across_frames_test :: proc(t: ^testing.T) {
	value: Surface_Test
	if !surface_test_init(t, &value) {return}
	defer surface_test_destroy(&value)
	renderer := &value.renderer
	surface: Surface
	defer surface_destroy(renderer, &surface)

	content: draw.List
	draw.list_init(&content)
	defer draw.list_destroy(&content)
	// Red lower half, blue upper half in y-up points.
	draw.solid(&content, {0, 0, 32, 8}, {1, 0, 0, 1}, edge_softness = 0)
	draw.solid(&content, {0, 8, 32, 8}, {0, 0, 1, 1}, edge_softness = 0)

	testing.expect(t, !surface_is_current(&surface, SURFACE_TEST_POINTS, SURFACE_TEST_SCALE, 1))
	command_buffer := msg_id(value.queue, sel_registerName("commandBuffer"))
	testing.expect(t, surface_paint(renderer, &surface, command_buffer, &content, SURFACE_TEST_POINTS, SURFACE_TEST_SCALE, {0, 0, 0, 1}, 1))
	testing.expect(t, surface_test_submit(command_buffer))
	testing.expect(t, surface_is_current(&surface, SURFACE_TEST_POINTS, SURFACE_TEST_SCALE, 1))
	testing.expect_value(t, surface.paints, 1)
	testing.expect_value(t, surface.pixel_width, 64)
	testing.expect_value(t, surface.pixel_height, 32)

	for _ in 0 ..< 3 {
		begin_texture_frame(renderer)
		top := surface_test_composite_pixel(t, &value, &surface, 10, 4)
		bottom := surface_test_composite_pixel(t, &value, &surface, 10, 28)
		// BGRA readback: blue on top, red at the bottom, orientation preserved.
		testing.expect_value(t, top, [4]u8{255, 0, 0, 255})
		testing.expect_value(t, bottom, [4]u8{0, 0, 255, 255})
	}
	testing.expect_value(t, surface.paints, 1)

	testing.expect(t, !surface_is_current(&surface, SURFACE_TEST_POINTS, SURFACE_TEST_SCALE, 2))
	testing.expect(t, !surface_is_current(&surface, SURFACE_TEST_POINTS, 1, 1))
	testing.expect(t, !surface_is_current(&surface, {16, 32}, SURFACE_TEST_SCALE, 1))
}

@(test)
surface_resize_replaces_texture_and_recycles_its_handle_test :: proc(t: ^testing.T) {
	value: Surface_Test
	if !surface_test_init(t, &value) {return}
	defer surface_test_destroy(&value)
	renderer := &value.renderer
	surface: Surface
	content: draw.List
	draw.list_init(&content)
	defer draw.list_destroy(&content)
	draw.solid(&content, {0, 0, 8, 8}, {1, 1, 1, 1}, edge_softness = 0)

	for points in ([?][2]f32{{32, 16}, {16, 16}, {16, 16}}) {
		command_buffer := msg_id(value.queue, sel_registerName("commandBuffer"))
		if !surface_is_current(&surface, points, SURFACE_TEST_SCALE, 7) {
			testing.expect(t, surface_paint(renderer, &surface, command_buffer, &content, points, SURFACE_TEST_SCALE, {0, 0, 0, 1}, 7))
		}
		testing.expect(t, surface_test_submit(command_buffer))
	}
	testing.expect_value(t, surface.paints, 2)
	testing.expect_value(t, surface.pixel_width, 32)
	// One live persistent texture: the replaced one was unregistered.
	live := 0
	for texture in renderer.persistent {
		if texture != nil {live += 1}
	}
	testing.expect_value(t, live, 1)
	surface_destroy(renderer, &surface)
	for texture in renderer.persistent {
		testing.expect(t, texture == nil)
	}
	testing.expect_value(t, len(renderer.persistent_free), len(renderer.persistent))
}
