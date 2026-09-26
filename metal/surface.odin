package metal

import draw "ui_framework:draw"

// Persistent texture handles stay valid across frames until unregistered, so
// retained textures (cached surfaces, glyph atlas pages) need no per-frame
// registration. Frame handles from register_texture are 1..N; persistent handles
// start at PERSISTENT_HANDLE_BASE, so the two ranges never collide.
PERSISTENT_HANDLE_BASE :: draw.Texture_Handle(1 << 32)

register_persistent_texture :: proc(renderer: ^Renderer, texture: Object) -> draw.Texture_Handle {
	assert(renderer != nil)
	assert(texture != nil)
	retained := msg_id(texture, sel_registerName("retain"))
	index: int
	if count := len(renderer.persistent_free); count > 0 {
		index = int(renderer.persistent_free[count - 1])
		pop(&renderer.persistent_free)
		assert(renderer.persistent[index] == nil)
		renderer.persistent[index] = retained
	} else {
		index = len(renderer.persistent)
		append(&renderer.persistent, retained)
	}
	return PERSISTENT_HANDLE_BASE + draw.Texture_Handle(index)
}

unregister_persistent_texture :: proc(renderer: ^Renderer, handle: draw.Texture_Handle) {
	assert(handle >= PERSISTENT_HANDLE_BASE)
	index := int(handle - PERSISTENT_HANDLE_BASE)
	assert(index < len(renderer.persistent))
	assert(renderer.persistent[index] != nil, "persistent texture handle released twice")
	release(renderer.persistent[index])
	renderer.persistent[index] = nil
	append(&renderer.persistent_free, u32(index))
}

persistent_destroy :: proc(renderer: ^Renderer) {
	for texture in renderer.persistent {
		if texture != nil {release(texture)}
	}
	delete(renderer.persistent)
	delete(renderer.persistent_free)
	delete(renderer.atlas_handles)
	renderer.persistent = nil
	renderer.persistent_free = nil
	renderer.atlas_handles = nil
}

// A cached, GPU-private render target for one independently changing UI piece.
// Paint it only when it is not current; every other frame composites its texture.
// content_revision is the application's value for everything the pixels depend on
// besides size and scale; zero means never painted.
Surface :: struct {
	texture:          Object,
	handle:           draw.Texture_Handle, // Persistent while texture is alive.
	pixel_width:      uint,
	pixel_height:     uint,
	viewport_points:  [2]f32,
	content_revision: u64,
	paints:           u64, // Completed paint encodes, for invalidation checks.
}

surface_pixel_size :: proc(viewport_points: [2]f32, backing_scale: f32) -> (uint, uint) {
	// Matches encode_to_drawable's viewport-to-pixel conversion.
	return uint(max(f32(1), viewport_points[0] * backing_scale)),
		uint(max(f32(1), viewport_points[1] * backing_scale))
}

surface_is_current :: proc(
	surface: ^Surface,
	viewport_points: [2]f32,
	backing_scale: f32,
	content_revision: u64,
) -> bool {
	assert(content_revision != 0)
	pixel_width, pixel_height := surface_pixel_size(viewport_points, backing_scale)
	return surface.texture != nil && surface.content_revision == content_revision &&
		surface.viewport_points == viewport_points && surface.pixel_width == pixel_width &&
		surface.pixel_height == pixel_height
}

// Encodes list into the surface, replacing its texture when the pixel size changed.
// A command buffer that still reads a replaced texture keeps it alive.
surface_paint :: proc(
	renderer: ^Renderer,
	surface: ^Surface,
	command_buffer: Object,
	list: ^draw.List,
	viewport_points: [2]f32,
	backing_scale: f32,
	clear_color: draw.Color,
	content_revision: u64,
) -> bool {
	assert(renderer != nil)
	assert(surface != nil)
	assert(content_revision != 0)
	pixel_width, pixel_height := surface_pixel_size(viewport_points, backing_scale)
	if surface.texture == nil || surface.pixel_width != pixel_width || surface.pixel_height != pixel_height {
		texture := surface_texture_create(renderer, pixel_width, pixel_height)
		if texture == nil {return false}
		surface_release_texture(renderer, surface)
		surface.texture = texture
		surface.handle = register_persistent_texture(renderer, texture)
		surface.pixel_width = pixel_width
		surface.pixel_height = pixel_height
	}
	surface.content_revision = 0
	if !encode_to_drawable(
		renderer,
		command_buffer,
		surface.texture,
		list,
		viewport_points,
		backing_scale,
		clear_color,
	) {
		return false
	}
	surface.viewport_points = viewport_points
	surface.content_revision = content_revision
	surface.paints += 1
	return true
}

// Draws the surface's texture into dst, one texel per backing pixel when dst matches
// the painted viewport. The texture stores its top row first: flip v.
surface_composite :: proc(list: ^draw.List, surface: ^Surface, dst: draw.Rect, opacity := f32(1)) {
	assert(surface.texture != nil)
	assert(surface.handle >= PERSISTENT_HANDLE_BASE)
	draw.image(list, surface.handle, dst, {0, 1, 1, -1}, {opacity, opacity, opacity, opacity}, .Color, .Nearest, label = "surface")
}

surface_destroy :: proc(renderer: ^Renderer, surface: ^Surface) {
	surface_release_texture(renderer, surface)
	surface^ = {}
}

surface_release_texture :: proc(renderer: ^Renderer, surface: ^Surface) {
	if surface.texture == nil {return}
	unregister_persistent_texture(renderer, surface.handle)
	release(surface.texture)
	surface.texture = nil
	surface.handle = 0
}

MTL_TEXTURE_USAGE_SHADER_READ :: uint(1 << 0)
MTL_TEXTURE_USAGE_RENDER_TARGET :: uint(1 << 2)
MTL_STORAGE_MODE_PRIVATE :: uint(2)

surface_texture_create :: proc(renderer: ^Renderer, pixel_width, pixel_height: uint) -> Object {
	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		renderer.pixel_format,
		pixel_width,
		pixel_height,
		false,
	)
	if descriptor == nil {return nil}
	msg_void_u(descriptor, sel_registerName("setUsage:"), MTL_TEXTURE_USAGE_SHADER_READ | MTL_TEXTURE_USAGE_RENDER_TARGET)
	msg_void_u(descriptor, sel_registerName("setStorageMode:"), MTL_STORAGE_MODE_PRIVATE)
	return msg_id_id(renderer.device, sel_registerName("newTextureWithDescriptor:"), descriptor)
}
