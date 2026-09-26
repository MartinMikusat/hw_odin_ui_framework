package metal

import "core:mem"
import "core:dynlib"
import "core:strings"
import coretext "ui_framework:coretext"
import draw "ui_framework:draw"
import Metal "vendor:darwin/Metal"

Object :: rawptr
Selector :: rawptr

// Foundation reexports the Objective-C runtime (as in Odin's Foundation bindings).
foreign import objc "system:Foundation.framework"
foreign objc {
	objc_getClass    :: proc "c" (name: cstring) -> Object ---
	sel_registerName :: proc "c" (name: cstring) -> Selector ---
}

foreign import core_foundation "system:CoreFoundation.framework"
foreign core_foundation {
	CFStringCreateWithCString :: proc "c" (allocator: rawptr, text: cstring, encoding: u32) -> rawptr ---
	CFRelease                 :: proc "c" (value: rawptr) ---
}

foreign import dispatch "system:System"
foreign dispatch {
	dispatch_data_create :: proc "c" (buffer: rawptr, size: uint, queue: rawptr, destructor: rawptr) -> Object ---
}

UTF8_ENCODING :: u32(0x08000100)
// Development-only fallback for applications not yet shipping ui.metallib.
// Production shaders are precompiled with scripts/build-metallib.sh.
RUNTIME_SHADER_SOURCE :: #load("../shaders/ui.metal")

MTL_Origin :: struct {
	x, y, z: uint,
}

MTL_Size :: struct {
	width, height, depth: uint,
}

MTL_Region :: struct {
	origin: MTL_Origin,
	size:   MTL_Size,
}

MTL_Scissor_Rect :: struct {
	x, y, width, height: uint,
}

GPU_Quad_Instance :: struct {
	dst:              [4]f32,
	src:              [4]f32,
	colors:           [4][4]f32,
	corner_radii:     [4]f32,
	effect_offset:    [2]f32,
	border_thickness: f32,
	edge_softness:    f32,
	texture_mode:     u32,
	corner_shape:     u32,
	_tail:            [2]u32,
}

GPU_Path_Vertex :: struct {
	position: [2]f32,
	coverage: [2]f32,
}

Batch_Uniforms :: struct {
	viewport:    [2]f32,
	opacity:     f32,
	padding:     f32,
	transform:   [4]f32,
	translation: [2]f32,
	_tail:       [2]f32,
}

Batch_Range :: struct {
	start, count: uint,
}

Path_Batch_Range :: struct {
	fill, fringe, cover: Batch_Range,
}

Path_Uniforms :: struct {
	viewport:        [2]f32,
	opacity:         f32,
	padding:         f32,
	transform:       [4]f32,
	translation:     [2]f32,
	_transform_tail: [2]f32,
	color:           [4]f32,
	stroke_mult:     f32,
	stroke_threshold: f32,
	_tail:           [2]f32,
}

Renderer :: struct {
	allocator:        mem.Allocator,
	device:           Object,
	pipeline:         Object,
	stencil_pipeline: Object,
	max_pipeline:     Object,
	path_pipeline:    Object,
	path_stencil_pipeline: Object,
	path_stencil_write_pipeline: Object,
	disabled_depth_stencil_state: Object,
	fill_non_zero_state: Object,
	fill_even_odd_state: Object,
	stencil_equal_state: Object,
	stencil_not_equal_zero_state: Object,
	stroke_write_state: Object,
	stencil_clear_state: Object,
	white_texture:    Object,
	linear_sampler:   Object,
	nearest_sampler:  Object,
	textures:         [dynamic]Object,
	runtime_compiled: bool,
	pixel_format:     uint,
	shadow_texture:   Object,
	shadow_width:     uint,
	shadow_height:    uint,
	stencil_texture:  Object,
	stencil_width:    uint,
	stencil_height:   uint,
}

send_address: rawptr

load_objc :: proc() -> bool {
	if send_address != nil {return true}
	handle, loaded := dynlib.load_library("/usr/lib/libobjc.A.dylib")
	if !loaded {return false}
	send_address, loaded = dynlib.symbol_address(handle, "objc_msgSend")
	return loaded
}

msg_id :: proc(receiver: Object, selector: Selector) -> Object {
	p := cast(proc "c" (_: Object, _: Selector) -> Object)send_address
	return p(receiver, selector)
}

msg_void :: proc(receiver: Object, selector: Selector) {
	p := cast(proc "c" (_: Object, _: Selector))send_address
	p(receiver, selector)
}

msg_void_id :: proc(receiver: Object, selector: Selector, value: Object) {
	p := cast(proc "c" (_: Object, _: Selector, _: Object))send_address
	p(receiver, selector, value)
}

msg_void_id_u :: proc(receiver: Object, selector: Selector, value: Object, index: uint) {
	p := cast(proc "c" (_: Object, _: Selector, _: Object, _: uint))send_address
	p(receiver, selector, value, index)
}

msg_void_bool :: proc(receiver: Object, selector: Selector, value: bool) {
	p := cast(proc "c" (_: Object, _: Selector, _: bool))send_address
	p(receiver, selector, value)
}

msg_void_u :: proc(receiver: Object, selector: Selector, value: uint) {
	p := cast(proc "c" (_: Object, _: Selector, _: uint))send_address
	p(receiver, selector, value)
}

msg_id_id :: proc(receiver: Object, selector: Selector, value: Object) -> Object {
	p := cast(proc "c" (_: Object, _: Selector, _: Object) -> Object)send_address
	return p(receiver, selector, value)
}

msg_id_id_error :: proc(receiver: Object, selector: Selector, value: Object, error: ^Object) -> Object {
	p := cast(proc "c" (_: Object, _: Selector, _: Object, _: ^Object) -> Object)send_address
	return p(receiver, selector, value, error)
}

msg_id_source_error :: proc(receiver: Object, selector: Selector, source, options: Object, error: ^Object) -> Object {
	p := cast(proc "c" (_: Object, _: Selector, _: Object, _: Object, _: ^Object) -> Object)send_address
	return p(receiver, selector, source, options, error)
}

msg_id_descriptor_error :: proc(receiver: Object, selector: Selector, descriptor: Object, error: ^Object) -> Object {
	p := cast(proc "c" (_: Object, _: Selector, _: Object, _: ^Object) -> Object)send_address
	return p(receiver, selector, descriptor, error)
}

msg_id_u :: proc(receiver: Object, selector: Selector, value: uint) -> Object {
	p := cast(proc "c" (_: Object, _: Selector, _: uint) -> Object)send_address
	return p(receiver, selector, value)
}

msg_id_u_u_u_bool :: proc(receiver: Object, selector: Selector, format, width, height: uint, mipmapped: bool) -> Object {
	p := cast(proc "c" (_: Object, _: Selector, _: uint, _: uint, _: uint, _: bool) -> Object)send_address
	return p(receiver, selector, format, width, height, mipmapped)
}

msg_id_ptr_u_u :: proc(receiver: Object, selector: Selector, bytes: rawptr, length, options: uint) -> Object {
	p := cast(proc "c" (_: Object, _: Selector, _: rawptr, _: uint, _: uint) -> Object)send_address
	return p(receiver, selector, bytes, length, options)
}

msg_void_ptr_u_u :: proc(receiver: Object, selector: Selector, bytes: rawptr, length, index: uint) {
	p := cast(proc "c" (_: Object, _: Selector, _: rawptr, _: uint, _: uint))send_address
	p(receiver, selector, bytes, length, index)
}

msg_void_id_u_u :: proc(receiver: Object, selector: Selector, value: Object, offset, index: uint) {
	p := cast(proc "c" (_: Object, _: Selector, _: Object, _: uint, _: uint))send_address
	p(receiver, selector, value, offset, index)
}

msg_void_region_u_ptr_u :: proc(receiver: Object, selector: Selector, region: MTL_Region, level: uint, bytes: rawptr, bytes_per_row: uint) {
	p := cast(proc "c" (_: Object, _: Selector, _: MTL_Region, _: uint, _: rawptr, _: uint))send_address
	p(receiver, selector, region, level, bytes, bytes_per_row)
}

msg_void_scissor :: proc(receiver: Object, selector: Selector, rect: MTL_Scissor_Rect) {
	p := cast(proc "c" (_: Object, _: Selector, _: MTL_Scissor_Rect))send_address
	p(receiver, selector, rect)
}

msg_void_draw_instanced :: proc(receiver: Object, selector: Selector, primitive, vertex_start, vertex_count, instance_count: uint) {
	p := cast(proc "c" (_: Object, _: Selector, _: uint, _: uint, _: uint, _: uint))send_address
	p(receiver, selector, primitive, vertex_start, vertex_count, instance_count)
}

MTL_LOAD_LOAD :: uint(1)
MTL_LOAD_CLEAR :: uint(2)

MTL_Clear_Color :: struct {
	red, green, blue, alpha: f64,
}

msg_void_clear_color :: proc(receiver: Object, selector: Selector, color: MTL_Clear_Color) {
	p := cast(proc "c" (_: Object, _: Selector, _: MTL_Clear_Color))send_address
	p(receiver, selector, color)
}

nsstring :: proc(value: string) -> Object {
	if len(value) == 0 {return CFStringCreateWithCString(nil, "", UTF8_ENCODING)}
	text, err := strings.clone_to_cstring(value, context.temp_allocator)
	if err != nil {return nil}
	defer delete(text, context.temp_allocator)
	return CFStringCreateWithCString(nil, text, UTF8_ENCODING)
}

release :: proc(value: Object) {
	if value != nil {msg_void(value, sel_registerName("release"))}
}

load_library :: proc(
	renderer: ^Renderer,
	metallib_path: string,
	metallib_data: []u8,
	allow_runtime_fallback: bool,
) -> Object {
	error: Object
	if len(metallib_data) > 0 {
		// A nil destructor makes dispatch copy the bytes; the caller keeps its slice.
		data := dispatch_data_create(raw_data(metallib_data), uint(len(metallib_data)), nil, nil)
		if data == nil {return nil}
		defer release(data)
		library := msg_id_id_error(renderer.device, sel_registerName("newLibraryWithData:error:"), data, &error)
		if library != nil {return library}
		if !allow_runtime_fallback {return nil}
	}
	if len(metallib_path) > 0 {
		path := nsstring(metallib_path)
		if path != nil {
			library := msg_id_id_error(
				renderer.device,
				sel_registerName("newLibraryWithFile:error:"),
				path,
				&error,
			)
			CFRelease(path)
			if library != nil {return library}
		}
	}
	if !allow_runtime_fallback {return nil}
	source := nsstring(string(RUNTIME_SHADER_SOURCE))
	if source == nil {return nil}
	defer CFRelease(source)
	library := msg_id_source_error(
		renderer.device,
		sel_registerName("newLibraryWithSource:options:error:"),
		source,
		nil,
		&error,
	)
	if library != nil {renderer.runtime_compiled = true}
	return library
}

create_pipeline :: proc(
	renderer: ^Renderer,
	library: Object,
	pixel_format: uint,
	vertex_function := "ui_vertex",
	fragment_function := "ui_fragment",
	max_blend := false,
	stencil_enabled := false,
	color_write := true,
) -> Object {
	vertex_name := nsstring(vertex_function)
	fragment_name := nsstring(fragment_function)
	if vertex_name == nil || fragment_name == nil {
		if vertex_name != nil {CFRelease(vertex_name)}
		if fragment_name != nil {CFRelease(fragment_name)}
		return nil
	}
	defer CFRelease(vertex_name)
	defer CFRelease(fragment_name)
	vertex := msg_id_id(library, sel_registerName("newFunctionWithName:"), vertex_name)
	fragment := msg_id_id(library, sel_registerName("newFunctionWithName:"), fragment_name)
	if vertex == nil || fragment == nil {
		release(vertex)
		release(fragment)
		return nil
	}
	defer release(vertex)
	defer release(fragment)
	descriptor := msg_id(objc_getClass("MTLRenderPipelineDescriptor"), sel_registerName("new"))
	if descriptor == nil {return nil}
	defer release(descriptor)
	msg_void_id(descriptor, sel_registerName("setVertexFunction:"), vertex)
	msg_void_id(descriptor, sel_registerName("setFragmentFunction:"), fragment)
	if stencil_enabled {
		msg_void_u(
			descriptor,
			sel_registerName("setStencilAttachmentPixelFormat:"),
			uint(Metal.PixelFormat.Stencil8),
		)
	}
	attachments := msg_id(descriptor, sel_registerName("colorAttachments"))
	attachment := msg_id_u(attachments, sel_registerName("objectAtIndexedSubscript:"), 0)
	msg_void_u(attachment, sel_registerName("setPixelFormat:"), pixel_format)
	if !color_write {msg_void_u(attachment, sel_registerName("setWriteMask:"), 0)}
	msg_void_bool(attachment, sel_registerName("setBlendingEnabled:"), true)
	if max_blend {
		msg_void_u(attachment, sel_registerName("setRgbBlendOperation:"), 4)
		msg_void_u(attachment, sel_registerName("setAlphaBlendOperation:"), 4)
		msg_void_u(attachment, sel_registerName("setSourceRGBBlendFactor:"), 1)
		msg_void_u(attachment, sel_registerName("setDestinationRGBBlendFactor:"), 1)
		msg_void_u(attachment, sel_registerName("setSourceAlphaBlendFactor:"), 1)
		msg_void_u(attachment, sel_registerName("setDestinationAlphaBlendFactor:"), 1)
	} else {
		msg_void_u(attachment, sel_registerName("setSourceRGBBlendFactor:"), 1)
		msg_void_u(attachment, sel_registerName("setDestinationRGBBlendFactor:"), 5)
		msg_void_u(attachment, sel_registerName("setSourceAlphaBlendFactor:"), 1)
		msg_void_u(attachment, sel_registerName("setDestinationAlphaBlendFactor:"), 5)
	}
	error: Object
	return msg_id_descriptor_error(
		renderer.device,
		sel_registerName("newRenderPipelineStateWithDescriptor:error:"),
		descriptor,
		&error,
	)
}

create_stencil_face :: proc(
	compare: Metal.CompareFunction,
	pass: Metal.StencilOperation,
) -> Object {
	descriptor := msg_id(objc_getClass("MTLStencilDescriptor"), sel_registerName("new"))
	if descriptor == nil {return nil}
	msg_void_u(descriptor, sel_registerName("setStencilCompareFunction:"), uint(compare))
	msg_void_u(descriptor, sel_registerName("setStencilFailureOperation:"), uint(Metal.StencilOperation.Keep))
	msg_void_u(descriptor, sel_registerName("setDepthFailureOperation:"), uint(Metal.StencilOperation.Keep))
	msg_void_u(descriptor, sel_registerName("setDepthStencilPassOperation:"), uint(pass))
	msg_void_u(descriptor, sel_registerName("setReadMask:"), 0xff)
	msg_void_u(descriptor, sel_registerName("setWriteMask:"), 0xff)
	return descriptor
}

create_depth_stencil_state :: proc(renderer: ^Renderer, front, back: Object) -> Object {
	if renderer == nil || front == nil || back == nil {return nil}
	descriptor := msg_id(objc_getClass("MTLDepthStencilDescriptor"), sel_registerName("new"))
	if descriptor == nil {return nil}
	defer release(descriptor)
	msg_void_id(descriptor, sel_registerName("setFrontFaceStencil:"), front)
	msg_void_id(descriptor, sel_registerName("setBackFaceStencil:"), back)
	return msg_id_id(renderer.device, sel_registerName("newDepthStencilStateWithDescriptor:"), descriptor)
}

create_disabled_depth_stencil_state :: proc(renderer: ^Renderer) -> Object {
	if renderer == nil || renderer.device == nil {return nil}
	descriptor := Metal.DepthStencilDescriptor_init(Metal.DepthStencilDescriptor_alloc())
	if descriptor == nil {return nil}
	defer release(Object(descriptor))
	state := Metal.Device_newDepthStencilState((^Metal.Device)(renderer.device), descriptor)
	return Object(state)
}

create_stencil_states :: proc(renderer: ^Renderer) -> bool {
	renderer.disabled_depth_stencil_state = create_disabled_depth_stencil_state(renderer)
	if renderer.disabled_depth_stencil_state == nil {return false}
	front := create_stencil_face(.Always, .IncrementWrap)
	back := create_stencil_face(.Always, .DecrementWrap)
	if front == nil || back == nil {release(front); release(back); return false}
	renderer.fill_non_zero_state = create_depth_stencil_state(renderer, front, back)
	release(front)
	release(back)

	even_odd := create_stencil_face(.Always, .Invert)
	equal := create_stencil_face(.Equal, .Keep)
	not_equal_zero := create_stencil_face(.NotEqual, .Zero)
	stroke_write := create_stencil_face(.Equal, .IncrementClamp)
	clear := create_stencil_face(.Always, .Zero)
	if even_odd == nil || equal == nil || not_equal_zero == nil || stroke_write == nil || clear == nil {
		release(even_odd); release(equal); release(not_equal_zero); release(stroke_write); release(clear)
		return false
	}
	renderer.fill_even_odd_state = create_depth_stencil_state(renderer, even_odd, even_odd)
	renderer.stencil_equal_state = create_depth_stencil_state(renderer, equal, equal)
	renderer.stencil_not_equal_zero_state = create_depth_stencil_state(renderer, not_equal_zero, not_equal_zero)
	renderer.stroke_write_state = create_depth_stencil_state(renderer, stroke_write, stroke_write)
	renderer.stencil_clear_state = create_depth_stencil_state(renderer, clear, clear)
	release(even_odd)
	release(equal)
	release(not_equal_zero)
	release(stroke_write)
	release(clear)
	return renderer.disabled_depth_stencil_state != nil && renderer.fill_non_zero_state != nil &&
	       renderer.fill_even_odd_state != nil &&
	       renderer.stencil_equal_state != nil && renderer.stencil_not_equal_zero_state != nil &&
	       renderer.stroke_write_state != nil && renderer.stencil_clear_state != nil
}

create_sampler :: proc(renderer: ^Renderer, nearest: bool) -> Object {
	descriptor := msg_id(objc_getClass("MTLSamplerDescriptor"), sel_registerName("new"))
	if descriptor == nil {return nil}
	defer release(descriptor)
	filter := uint(0)
	if !nearest {filter = 1}
	msg_void_u(descriptor, sel_registerName("setMinFilter:"), filter)
	msg_void_u(descriptor, sel_registerName("setMagFilter:"), filter)
	msg_void_u(descriptor, sel_registerName("setSAddressMode:"), 0)
	msg_void_u(descriptor, sel_registerName("setTAddressMode:"), 0)
	return msg_id_id(renderer.device, sel_registerName("newSamplerStateWithDescriptor:"), descriptor)
}

create_white_texture :: proc(renderer: ^Renderer) -> Object {
	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		70,
		1,
		1,
		false,
	)
	if descriptor == nil {return nil}
	texture := msg_id_id(renderer.device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	if texture == nil {return nil}
	pixel := [4]u8{255, 255, 255, 255}
	msg_void_region_u_ptr_u(
		texture,
		sel_registerName("replaceRegion:mipmapLevel:withBytes:bytesPerRow:"),
		{size = {1, 1, 1}},
		0,
		raw_data(pixel[:]),
		4,
	)
	return texture
}

renderer_init :: proc(
	renderer: ^Renderer,
	device: Object,
	metallib_path := "",
	pixel_format := uint(80),
	allow_runtime_fallback := false,
	allocator := context.allocator,
	metallib_data: []u8 = nil,
) -> bool {
	assert(renderer != nil)
	if device == nil || !load_objc() {return false}
	renderer^ = Renderer{allocator = allocator, device = device, pixel_format = pixel_format}
	renderer.textures = make([dynamic]Object, allocator)
	library := load_library(renderer, metallib_path, metallib_data, allow_runtime_fallback)
	if library == nil {renderer_destroy(renderer); return false}
	renderer.pipeline = create_pipeline(renderer, library, pixel_format)
	renderer.stencil_pipeline = create_pipeline(renderer, library, pixel_format, stencil_enabled = true)
	renderer.max_pipeline = create_pipeline(renderer, library, pixel_format, max_blend = true)
	renderer.path_pipeline = create_pipeline(
		renderer,
		library,
		pixel_format,
		vertex_function = "path_vertex",
		fragment_function = "path_fragment",
	)
	renderer.path_stencil_pipeline = create_pipeline(
		renderer,
		library,
		pixel_format,
		vertex_function = "path_vertex",
		fragment_function = "path_fragment",
		stencil_enabled = true,
	)
	renderer.path_stencil_write_pipeline = create_pipeline(
		renderer,
		library,
		pixel_format,
		vertex_function = "path_vertex",
		fragment_function = "path_fragment",
		stencil_enabled = true,
		color_write = false,
	)
	release(library)
	if !create_stencil_states(renderer) {renderer_destroy(renderer); return false}
	renderer.white_texture = create_white_texture(renderer)
	renderer.linear_sampler = create_sampler(renderer, false)
	renderer.nearest_sampler = create_sampler(renderer, true)
	if renderer.pipeline == nil || renderer.stencil_pipeline == nil || renderer.max_pipeline == nil ||
	   renderer.path_pipeline == nil || renderer.path_stencil_pipeline == nil ||
	   renderer.path_stencil_write_pipeline == nil || renderer.white_texture == nil ||
	   renderer.linear_sampler == nil || renderer.nearest_sampler == nil {
		renderer_destroy(renderer)
		return false
	}
	return true
}

renderer_destroy :: proc(renderer: ^Renderer) {
	if renderer == nil {return}
	end_texture_frame(renderer)
	delete(renderer.textures)
	release(renderer.pipeline)
	release(renderer.stencil_pipeline)
	release(renderer.max_pipeline)
	release(renderer.path_pipeline)
	release(renderer.path_stencil_pipeline)
	release(renderer.path_stencil_write_pipeline)
	release(renderer.disabled_depth_stencil_state)
	release(renderer.fill_non_zero_state)
	release(renderer.fill_even_odd_state)
	release(renderer.stencil_equal_state)
	release(renderer.stencil_not_equal_zero_state)
	release(renderer.stroke_write_state)
	release(renderer.stencil_clear_state)
	release(renderer.shadow_texture)
	release(renderer.stencil_texture)
	release(renderer.white_texture)
	release(renderer.linear_sampler)
	release(renderer.nearest_sampler)
	renderer^ = {}
}

begin_texture_frame :: proc(renderer: ^Renderer) {
	end_texture_frame(renderer)
}

end_texture_frame :: proc(renderer: ^Renderer) {
	if renderer == nil {return}
	for texture in renderer.textures {release(texture)}
	clear(&renderer.textures)
}

register_texture :: proc(renderer: ^Renderer, texture: Object) -> draw.Texture_Handle {
	if renderer == nil || texture == nil {return draw.Texture_Handle(0)}
	retained := msg_id(texture, sel_registerName("retain"))
	append(&renderer.textures, retained)
	return draw.Texture_Handle(len(renderer.textures))
}

/**
 * Snapshot retained Metal texture natives for hot-loop chrome retention.
 * Call after building a draw bucket that must outlive the next
 * begin_texture_frame. Pair with rebind_texture_natives before encode so
 * Texture_Handle indices in the retained bucket match the renderer again
 * without regenerating glyph atlas pages.
 */
snapshot_texture_natives :: proc(
	renderer: ^Renderer,
	destination: ^[dynamic]u64,
) {
	if destination == nil {return}
	clear(destination)
	if renderer == nil {return}
	for texture in renderer.textures {
		append(destination, u64(uintptr(texture)))
	}
}

/**
 * Recreate handle indices 1..N from previously snapshotted natives.
 * Retained chrome buckets may outlive begin_texture_frame only when callers
 * snapshot after the chrome rebuild and rebind before composing or encoding
 * the ordered stream on a warm tick.
 */
rebind_texture_natives :: proc(renderer: ^Renderer, natives: []u64) {
	if renderer == nil {return}
	begin_texture_frame(renderer)
	for native in natives {
		if native == 0 {continue}
		_ = register_texture(renderer, Object(rawptr(uintptr(native))))
	}
}

atlas_create :: proc(data: rawptr, format: coretext.Atlas_Format, width, height: int) -> u64 {
	renderer := (^Renderer)(data)
	if renderer == nil || renderer.device == nil || width <= 0 || height <= 0 {return 0}
	pixel_format := uint(10)
	if format == .Color {pixel_format = 80}
	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		pixel_format,
		uint(width),
		uint(height),
		false,
	)
	if descriptor == nil {return 0}
	texture := msg_id_id(renderer.device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	return u64(uintptr(texture))
}

atlas_upload :: proc(
	data: rawptr,
	native: u64,
	format: coretext.Atlas_Format,
	x, y, width, height: int,
	pixels: [^]u8,
	bytes_per_row: int,
) {
	texture := Object(rawptr(uintptr(native)))
	if texture == nil || pixels == nil || width <= 0 || height <= 0 {return}
	msg_void_region_u_ptr_u(
		texture,
		sel_registerName("replaceRegion:mipmapLevel:withBytes:bytesPerRow:"),
		{
			origin = {uint(x), uint(y), 0},
			size = {uint(width), uint(height), 1},
		},
		0,
		pixels,
		uint(bytes_per_row),
	)
}

atlas_destroy :: proc(data: rawptr, native: u64) {
	release(Object(rawptr(uintptr(native))))
}

atlas_bind :: proc(data: rawptr, native: u64) -> draw.Texture_Handle {
	return register_texture((^Renderer)(data), Object(rawptr(uintptr(native))))
}

atlas_io :: proc(renderer: ^Renderer) -> coretext.Atlas_IO {
	return {
		user_data = renderer,
		create = atlas_create,
		upload = atlas_upload,
		destroy = atlas_destroy,
		bind = atlas_bind,
	}
}

texture_for_handle :: proc(renderer: ^Renderer, handle: draw.Texture_Handle) -> Object {
	index := int(handle)-1
	if index < 0 || index >= len(renderer.textures) {return renderer.white_texture}
	return renderer.textures[index]
}

gpu_instance :: proc(instance: draw.Quad_Instance) -> GPU_Quad_Instance {
	return {
		dst = {instance.dst.x, instance.dst.y, instance.dst.w, instance.dst.h},
		src = {instance.src.x, instance.src.y, instance.src.w, instance.src.h},
		colors = instance.colors,
		corner_radii = instance.corner_radii,
		effect_offset = instance.effect_offset,
		border_thickness = instance.border_thickness,
		edge_softness = instance.edge_softness,
		texture_mode = u32(instance.texture_mode),
		corner_shape = u32(instance.corner_shape),
	}
}

gpu_path_vertex :: proc(vertex: draw.Path_Vertex) -> GPU_Path_Vertex {
	return {position = vertex.position, coverage = vertex.coverage}
}

list_requires_stencil :: proc(list: ^draw.List) -> bool {
	if list == nil {return false}
	for &batch in list.batches {
		if batch.kind == .Path && batch.path.kind != .Convex_Fill {return true}
	}
	return false
}

path_vertex_count :: proc(list: ^draw.List) -> int {
	total := 0
	if list == nil {return total}
	for &batch in list.batches {
		if batch.kind != .Path {continue}
		total += len(batch.path.fill)+len(batch.path.fringe)+len(batch.path.cover)
	}
	return total
}

pack_path_vertices :: proc(
	list: ^draw.List,
	vertices: []GPU_Path_Vertex,
	ranges: []Path_Batch_Range,
) {
	cursor := 0
	for &batch, index in list.batches {
		if batch.kind != .Path {continue}
		ranges[index].fill = {uint(cursor), uint(len(batch.path.fill))}
		for vertex in batch.path.fill {vertices[cursor] = gpu_path_vertex(vertex); cursor += 1}
		ranges[index].fringe = {uint(cursor), uint(len(batch.path.fringe))}
		for vertex in batch.path.fringe {vertices[cursor] = gpu_path_vertex(vertex); cursor += 1}
		ranges[index].cover = {uint(cursor), uint(len(batch.path.cover))}
		for vertex in batch.path.cover {vertices[cursor] = gpu_path_vertex(vertex); cursor += 1}
	}
}

set_batch_scissor :: proc(
	encoder: Object,
	key: draw.Batch_Key,
	viewport_points: [2]f32,
	backing_scale: f32,
) -> bool {
	clip := MTL_Scissor_Rect{
		width = uint(max(f32(1), viewport_points[0]*backing_scale)),
		height = uint(max(f32(1), viewport_points[1]*backing_scale)),
	}
	if key.clip_set {
		x0 := max(f32(0), key.clip.x*backing_scale)
		y0 := max(f32(0), (viewport_points[1]-key.clip.y-key.clip.h)*backing_scale)
		x1 := min(viewport_points[0]*backing_scale, (key.clip.x+key.clip.w)*backing_scale)
		y1 := min(viewport_points[1]*backing_scale, (viewport_points[1]-key.clip.y)*backing_scale)
		clip = {
			x = uint(x0),
			y = uint(y0),
			width = uint(max(f32(0), x1-x0)),
			height = uint(max(f32(0), y1-y0)),
		}
		if clip.width == 0 || clip.height == 0 {return false}
	}
	msg_void_scissor(encoder, sel_registerName("setScissorRect:"), clip)
	return true
}

encode_path_range :: proc(
	encoder, pipeline, depth_state, buffer: Object,
	range: Batch_Range,
	uniforms: ^Path_Uniforms,
	stroke_threshold: f32,
) {
	if range.count == 0 {return}
	uniforms.stroke_threshold = stroke_threshold
	msg_void_id(encoder, sel_registerName("setRenderPipelineState:"), pipeline)
	msg_void_id(encoder, sel_registerName("setDepthStencilState:"), depth_state)
	msg_void_u(encoder, sel_registerName("setStencilReferenceValue:"), 0)
	msg_void_id_u_u(encoder, sel_registerName("setVertexBuffer:offset:atIndex:"), buffer, 0, 0)
	msg_void_ptr_u_u(
		encoder,
		sel_registerName("setVertexBytes:length:atIndex:"),
		uniforms,
		size_of(Path_Uniforms),
		1,
	)
	msg_void_ptr_u_u(
		encoder,
		sel_registerName("setFragmentBytes:length:atIndex:"),
		uniforms,
		size_of(Path_Uniforms),
		1,
	)
	msg_void_draw_instanced(
		encoder,
		sel_registerName("drawPrimitives:vertexStart:vertexCount:instanceCount:"),
		uint(Metal.PrimitiveType.Triangle),
		range.start,
		range.count,
		1,
	)
}

encode_path_batch :: proc(
	renderer: ^Renderer,
	encoder, buffer: Object,
	batch: ^draw.Batch,
	ranges: Path_Batch_Range,
	viewport_points: [2]f32,
	backing_scale: f32,
	stencil_available: bool,
) -> bool {
	if batch == nil || batch.kind != .Path {return true}
	if batch.path.kind != .Convex_Fill && !stencil_available {return false}
	if !set_batch_scissor(encoder, batch.key, viewport_points, backing_scale) {return true}
	msg_void_u(encoder, sel_registerName("setCullMode:"), uint(Metal.CullMode.None))
	msg_void_u(
		encoder,
		sel_registerName("setFrontFacingWinding:"),
		uint(Metal.Winding.CounterClockwise),
	)
	uniforms := Path_Uniforms{
		viewport = viewport_points,
		opacity = batch.key.opacity,
		transform = {
			batch.key.transform.m00,
			batch.key.transform.m01,
			batch.key.transform.m10,
			batch.key.transform.m11,
		},
		translation = {batch.key.transform.tx, batch.key.transform.ty},
		color = batch.path.color,
		stroke_mult = batch.path.stroke_mult,
	}
	color_pipeline := renderer.path_pipeline
	if stencil_available {color_pipeline = renderer.path_stencil_pipeline}
	switch batch.path.kind {
	case .Convex_Fill:
		encode_path_range(
			encoder,
			color_pipeline,
			renderer.disabled_depth_stencil_state,
			buffer,
			ranges.fill,
			&uniforms,
			-1,
		)
		encode_path_range(
			encoder,
			color_pipeline,
			renderer.disabled_depth_stencil_state,
			buffer,
			ranges.fringe,
			&uniforms,
			-1,
		)
	case .Compound_Fill:
		fill_state := renderer.fill_non_zero_state
		if batch.path.fill_rule == .Even_Odd {fill_state = renderer.fill_even_odd_state}
		encode_path_range(
			encoder,
			renderer.path_stencil_write_pipeline,
			fill_state,
			buffer,
			ranges.fill,
			&uniforms,
			-1,
		)
		encode_path_range(
			encoder,
			renderer.path_stencil_pipeline,
			renderer.stencil_equal_state,
			buffer,
			ranges.fringe,
			&uniforms,
			-1,
		)
		encode_path_range(
			encoder,
			renderer.path_stencil_pipeline,
			renderer.stencil_not_equal_zero_state,
			buffer,
			ranges.cover,
			&uniforms,
			-1,
		)
	case .Stroke:
		encode_path_range(
			encoder,
			renderer.path_stencil_pipeline,
			renderer.stroke_write_state,
			buffer,
			ranges.fill,
			&uniforms,
			1-0.5/255,
		)
		encode_path_range(
			encoder,
			renderer.path_stencil_pipeline,
			renderer.stencil_equal_state,
			buffer,
			ranges.fill,
			&uniforms,
			-1,
		)
		encode_path_range(
			encoder,
			renderer.path_stencil_write_pipeline,
			renderer.stencil_clear_state,
			buffer,
			ranges.fill,
			&uniforms,
			-1,
		)
	}
	msg_void_id(
		encoder,
		sel_registerName("setDepthStencilState:"),
		renderer.disabled_depth_stencil_state,
	)
	return true
}

encode :: proc(
	renderer: ^Renderer,
	encoder: Object,
	list: ^draw.List,
	viewport_points: [2]f32,
	backing_scale := f32(1),
	stencil_available := false,
) -> bool {
	if renderer == nil || renderer.pipeline == nil || encoder == nil || list == nil {return false}
	if list_requires_stencil(list) && !stencil_available {return false}
	quad_total := 0
	for &batch in list.batches {
		if batch.kind == .Quad {quad_total += len(batch.instances)}
	}
	path_total := path_vertex_count(list)
	if quad_total == 0 && path_total == 0 {return true}
	instances := make([]GPU_Quad_Instance, max(quad_total, 1), context.temp_allocator)
	defer delete(instances, context.temp_allocator)
	ranges := make([]Batch_Range, len(list.batches), context.temp_allocator)
	defer delete(ranges, context.temp_allocator)
	cursor := 0
	for &batch, index in list.batches {
		if batch.kind != .Quad {continue}
		ranges[index] = {uint(cursor), uint(len(batch.instances))}
		for instance in batch.instances {
			instances[cursor] = gpu_instance(instance)
			cursor += 1
		}
	}
	quad_buffer: Object
	if quad_total > 0 {
		quad_buffer = msg_id_ptr_u_u(
			renderer.device,
			sel_registerName("newBufferWithBytes:length:options:"),
			raw_data(instances),
			uint(quad_total)*size_of(GPU_Quad_Instance),
			0,
		)
		if quad_buffer == nil {return false}
	}
	defer release(quad_buffer)
	path_ranges := make([]Path_Batch_Range, len(list.batches), context.temp_allocator)
	defer delete(path_ranges, context.temp_allocator)
	path_vertices := make([]GPU_Path_Vertex, max(path_total, 1), context.temp_allocator)
	defer delete(path_vertices, context.temp_allocator)
	path_buffer: Object
	if path_total > 0 {
		pack_path_vertices(list, path_vertices[:path_total], path_ranges)
		path_buffer = msg_id_ptr_u_u(
			renderer.device,
			sel_registerName("newBufferWithBytes:length:options:"),
			raw_data(path_vertices),
			uint(path_total)*size_of(GPU_Path_Vertex),
			0,
		)
		if path_buffer == nil {return false}
	}
	defer release(path_buffer)
	for &batch, index in list.batches {
		switch batch.kind {
		case .Quad:
			pipeline := renderer.pipeline
			if stencil_available {pipeline = renderer.stencil_pipeline}
			encode_batch_range(
				renderer, encoder, pipeline, quad_buffer, list, ranges,
				index, index+1, viewport_points, backing_scale,
			)
		case .Path:
			if !encode_path_batch(
				renderer, encoder, path_buffer, &batch, path_ranges[index],
				viewport_points, backing_scale, stencil_available,
			) {return false}
		}
	}
	return true
}

ensure_shadow_texture :: proc(renderer: ^Renderer, width, height: uint) -> bool {
	if renderer.shadow_texture != nil && renderer.shadow_width == width && renderer.shadow_height == height {
		return true
	}
	release(renderer.shadow_texture)
	renderer.shadow_texture = nil
	if width == 0 || height == 0 {return false}
	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		renderer.pixel_format,
		width,
		height,
		false,
	)
	if descriptor == nil {return false}
	msg_void_u(descriptor, sel_registerName("setUsage:"), 5)
	texture := msg_id_id(renderer.device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	if texture == nil {return false}
	renderer.shadow_texture = texture
	renderer.shadow_width = width
	renderer.shadow_height = height
	return true
}

ensure_stencil_texture :: proc(renderer: ^Renderer, width, height: uint) -> bool {
	if renderer.stencil_texture != nil && renderer.stencil_width == width && renderer.stencil_height == height {
		return true
	}
	release(renderer.stencil_texture)
	renderer.stencil_texture = nil
	if width == 0 || height == 0 {return false}
	descriptor := msg_id_u_u_u_bool(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		uint(Metal.PixelFormat.Stencil8),
		width,
		height,
		false,
	)
	if descriptor == nil {return false}
	msg_void_u(descriptor, sel_registerName("setUsage:"), 4)
	texture := msg_id_id(renderer.device, sel_registerName("newTextureWithDescriptor:"), descriptor)
	if texture == nil {return false}
	renderer.stencil_texture = texture
	renderer.stencil_width = width
	renderer.stencil_height = height
	return true
}

begin_color_encoder :: proc(
	command_buffer: Object,
	texture: Object,
	load_action: uint,
	clear: MTL_Clear_Color,
	stencil_texture: Object = nil,
) -> Object {
	pass := msg_id(objc_getClass("MTLRenderPassDescriptor"), sel_registerName("renderPassDescriptor"))
	if pass == nil {return nil}
	attachments := msg_id(pass, sel_registerName("colorAttachments"))
	attachment := msg_id_u(attachments, sel_registerName("objectAtIndexedSubscript:"), 0)
	msg_void_id(attachment, sel_registerName("setTexture:"), texture)
	msg_void_u(attachment, sel_registerName("setLoadAction:"), load_action)
	msg_void_u(attachment, sel_registerName("setStoreAction:"), 1)
	if load_action == MTL_LOAD_CLEAR {
		msg_void_clear_color(attachment, sel_registerName("setClearColor:"), clear)
	}
	if stencil_texture != nil {
		stencil := msg_id(pass, sel_registerName("stencilAttachment"))
		msg_void_id(stencil, sel_registerName("setTexture:"), stencil_texture)
		msg_void_u(stencil, sel_registerName("setLoadAction:"), MTL_LOAD_CLEAR)
		msg_void_u(stencil, sel_registerName("setStoreAction:"), 0)
		msg_void_u(stencil, sel_registerName("setClearStencil:"), 0)
	}
	return msg_id_id(command_buffer, sel_registerName("renderCommandEncoderWithDescriptor:"), pass)
}

encode_batch_range :: proc(
	renderer: ^Renderer,
	encoder: Object,
	pipeline: Object,
	buffer: Object,
	list: ^draw.List,
	ranges: []Batch_Range,
	start, end: int,
	viewport_points: [2]f32,
	backing_scale: f32,
) {
	msg_void_id(encoder, sel_registerName("setRenderPipelineState:"), pipeline)
	msg_void_id(
		encoder,
		sel_registerName("setDepthStencilState:"),
		renderer.disabled_depth_stencil_state,
	)
	for index in start ..< end {
		batch := &list.batches[index]
		if batch.kind != .Quad {continue}
		if ranges[index].count == 0 {continue}
		uniforms := Batch_Uniforms{
			viewport = viewport_points,
			opacity = batch.key.opacity,
			transform = {
				batch.key.transform.m00,
				batch.key.transform.m01,
				batch.key.transform.m10,
				batch.key.transform.m11,
			},
			translation = {batch.key.transform.tx, batch.key.transform.ty},
		}
		msg_void_ptr_u_u(
			encoder,
			sel_registerName("setVertexBytes:length:atIndex:"),
			&uniforms,
			size_of(Batch_Uniforms),
			1,
		)
		texture := texture_for_handle(renderer, batch.key.texture)
		msg_void_id_u(encoder, sel_registerName("setFragmentTexture:atIndex:"), texture, 0)
		sampler := renderer.linear_sampler
		if batch.key.sampler == .Nearest {sampler = renderer.nearest_sampler}
		msg_void_id_u(encoder, sel_registerName("setFragmentSamplerState:atIndex:"), sampler, 0)
		if !set_batch_scissor(encoder, batch.key, viewport_points, backing_scale) {continue}
		msg_void_id_u_u(
			encoder,
			sel_registerName("setVertexBuffer:offset:atIndex:"),
			buffer,
			ranges[index].start*size_of(GPU_Quad_Instance),
			0,
		)
		msg_void_draw_instanced(
			encoder,
			sel_registerName("drawPrimitives:vertexStart:vertexCount:instanceCount:"),
			3,
			0,
			6,
			ranges[index].count,
		)
	}
}

composite_shadow_texture :: proc(
	renderer: ^Renderer,
	encoder: Object,
	viewport_points: [2]f32,
	backing_scale: f32,
	stencil_available := false,
) {
	instance := GPU_Quad_Instance{
		dst = {0, 0, viewport_points[0], viewport_points[1]},
		src = {0, 1, 1, -1},
		colors = {{1, 1, 1, 1}, {1, 1, 1, 1}, {1, 1, 1, 1}, {1, 1, 1, 1}},
		edge_softness = 0.5,
		texture_mode = u32(draw.Texture_Mode.Color),
	}
	buffer := msg_id_ptr_u_u(
		renderer.device,
		sel_registerName("newBufferWithBytes:length:options:"),
		&instance,
		size_of(GPU_Quad_Instance),
		0,
	)
	if buffer == nil {return}
	defer release(buffer)
	uniforms := Batch_Uniforms{
		viewport = viewport_points,
		opacity = 1,
		transform = {1, 0, 0, 1},
	}
	pipeline := renderer.pipeline
	if stencil_available {pipeline = renderer.stencil_pipeline}
	msg_void_id(encoder, sel_registerName("setRenderPipelineState:"), pipeline)
	msg_void_id(
		encoder,
		sel_registerName("setDepthStencilState:"),
		renderer.disabled_depth_stencil_state,
	)
	msg_void_id_u_u(encoder, sel_registerName("setVertexBuffer:offset:atIndex:"), buffer, 0, 0)
	msg_void_ptr_u_u(
		encoder,
		sel_registerName("setVertexBytes:length:atIndex:"),
		&uniforms,
		size_of(Batch_Uniforms),
		1,
	)
	msg_void_id_u(encoder, sel_registerName("setFragmentTexture:atIndex:"), renderer.shadow_texture, 0)
	msg_void_id_u(encoder, sel_registerName("setFragmentSamplerState:atIndex:"), renderer.nearest_sampler, 0)
	clip := MTL_Scissor_Rect{
		width = uint(max(f32(1), viewport_points[0]*backing_scale)),
		height = uint(max(f32(1), viewport_points[1]*backing_scale)),
	}
	msg_void_scissor(encoder, sel_registerName("setScissorRect:"), clip)
	msg_void_draw_instanced(
		encoder,
		sel_registerName("drawPrimitives:vertexStart:vertexCount:instanceCount:"),
		3,
		0,
		6,
		1,
	)
}

encode_to_drawable :: proc(
	renderer: ^Renderer,
	command_buffer: Object,
	color_texture: Object,
	list: ^draw.List,
	viewport_points: [2]f32,
	backing_scale := f32(1),
	clear_color: draw.Color = {0, 0, 0, 1},
) -> bool {
	if renderer == nil || renderer.pipeline == nil || command_buffer == nil ||
	   color_texture == nil || list == nil {
		return false
	}
	pixel_w := uint(max(f32(1), viewport_points[0]*backing_scale))
	pixel_h := uint(max(f32(1), viewport_points[1]*backing_scale))
	stencil_available := list_requires_stencil(list)
	if stencil_available && !ensure_stencil_texture(renderer, pixel_w, pixel_h) {return false}
	quad_total := 0
	for &batch in list.batches {
		if batch.kind == .Quad {quad_total += len(batch.instances)}
	}
	instances := make([]GPU_Quad_Instance, max(quad_total, 1), context.temp_allocator)
	defer delete(instances, context.temp_allocator)
	ranges := make([]Batch_Range, len(list.batches), context.temp_allocator)
	defer delete(ranges, context.temp_allocator)
	cursor := 0
	for &batch, index in list.batches {
		if batch.kind != .Quad {continue}
		ranges[index] = {uint(cursor), uint(len(batch.instances))}
		for instance in batch.instances {
			instances[cursor] = gpu_instance(instance)
			cursor += 1
		}
	}
	buffer: Object
	if quad_total > 0 {
		buffer = msg_id_ptr_u_u(
			renderer.device,
			sel_registerName("newBufferWithBytes:length:options:"),
			raw_data(instances),
			uint(quad_total)*size_of(GPU_Quad_Instance),
			0,
		)
		if buffer == nil {return false}
	}
	defer release(buffer)
	path_total := path_vertex_count(list)
	path_ranges := make([]Path_Batch_Range, len(list.batches), context.temp_allocator)
	defer delete(path_ranges, context.temp_allocator)
	path_vertices := make([]GPU_Path_Vertex, max(path_total, 1), context.temp_allocator)
	defer delete(path_vertices, context.temp_allocator)
	path_buffer: Object
	if path_total > 0 {
		pack_path_vertices(list, path_vertices[:path_total], path_ranges)
		path_buffer = msg_id_ptr_u_u(
			renderer.device,
			sel_registerName("newBufferWithBytes:length:options:"),
			raw_data(path_vertices),
			uint(path_total)*size_of(GPU_Path_Vertex),
			0,
		)
		if path_buffer == nil {return false}
	}
	defer release(path_buffer)

	clear := MTL_Clear_Color{
		f64(clear_color[0]),
		f64(clear_color[1]),
		f64(clear_color[2]),
		f64(clear_color[3]),
	}
	main_encoder: Object
	main_load := MTL_LOAD_CLEAR
	in_max := false
	max_start := 0

	end_main :: proc(encoder: ^Object) {
		if encoder^ == nil {return}
		msg_void(encoder^, sel_registerName("endEncoding"))
		encoder^ = nil
	}

	flush_max :: proc(
		renderer: ^Renderer,
		command_buffer: Object,
		color_texture: Object,
		buffer: Object,
		list: ^draw.List,
		ranges: []Batch_Range,
		max_start, max_end: int,
		viewport_points: [2]f32,
		backing_scale: f32,
		pixel_w, pixel_h: uint,
		main_encoder: ^Object,
		main_load: ^uint,
		clear: MTL_Clear_Color,
		stencil_texture: Object,
		stencil_available: bool,
	) -> bool {
		end_main(main_encoder)
		if !ensure_shadow_texture(renderer, pixel_w, pixel_h) {return false}
		shadow_encoder := begin_color_encoder(
			command_buffer,
			renderer.shadow_texture,
			MTL_LOAD_CLEAR,
			{0, 0, 0, 0},
		)
		if shadow_encoder == nil {return false}
		if buffer != nil {
			encode_batch_range(
				renderer,
				shadow_encoder,
				renderer.max_pipeline,
				buffer,
				list,
				ranges,
				max_start,
				max_end,
				viewport_points,
				backing_scale,
			)
		}
		msg_void(shadow_encoder, sel_registerName("endEncoding"))
		main_encoder^ = begin_color_encoder(
			command_buffer,
			color_texture,
			main_load^,
			clear,
			stencil_texture,
		)
		if main_encoder^ == nil {return false}
		main_load^ = MTL_LOAD_LOAD
		composite_shadow_texture(
			renderer,
			main_encoder^,
			viewport_points,
			backing_scale,
			stencil_available,
		)
		return true
	}
	main_stencil: Object
	main_pipeline := renderer.pipeline
	if stencil_available {
		main_stencil = renderer.stencil_texture
		main_pipeline = renderer.stencil_pipeline
	}

	for index in 0 ..< len(list.batches) {
		if list.batches[index].key.combine == .Max {
			if !in_max {
				max_start = index
				in_max = true
			}
			continue
		}
		if in_max {
			if !flush_max(
				renderer,
				command_buffer,
				color_texture,
				buffer,
				list,
				ranges,
				max_start,
				index,
				viewport_points,
				backing_scale,
				pixel_w,
				pixel_h,
				&main_encoder,
				&main_load,
				clear,
				main_stencil,
				stencil_available,
			) {
				return false
			}
			in_max = false
		}
		if main_encoder == nil {
			main_encoder = begin_color_encoder(
				command_buffer,
				color_texture,
				main_load,
				clear,
				main_stencil,
			)
			if main_encoder == nil {return false}
			main_load = MTL_LOAD_LOAD
		}
		switch list.batches[index].kind {
		case .Quad:
			if buffer == nil {continue}
			encode_batch_range(
				renderer,
				main_encoder,
				main_pipeline,
				buffer,
				list,
				ranges,
				index,
				index+1,
				viewport_points,
				backing_scale,
			)
		case .Path:
			if !encode_path_batch(
				renderer,
				main_encoder,
				path_buffer,
				&list.batches[index],
				path_ranges[index],
				viewport_points,
				backing_scale,
				stencil_available,
			) {return false}
		}
	}
	if in_max {
		if !flush_max(
			renderer,
			command_buffer,
			color_texture,
			buffer,
			list,
			ranges,
			max_start,
			len(list.batches),
			viewport_points,
			backing_scale,
			pixel_w,
			pixel_h,
			&main_encoder,
			&main_load,
			clear,
			main_stencil,
			stencil_available,
		) {
			return false
		}
	}
	if main_encoder == nil {
		main_encoder = begin_color_encoder(
			command_buffer,
			color_texture,
			main_load,
			clear,
			main_stencil,
		)
		if main_encoder == nil {return false}
	}
	end_main(&main_encoder)
	return true
}
