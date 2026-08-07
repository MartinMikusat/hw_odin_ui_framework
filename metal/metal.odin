package metal

import "core:mem"
import "core:dynlib"
import "core:strings"
import coretext "ui_framework:coretext"
import draw "ui_framework:draw"

Object :: rawptr
Selector :: rawptr

foreign import objc "system:objc"
foreign objc {
	objc_getClass    :: proc "c" (name: cstring) -> Object ---
	sel_registerName :: proc "c" (name: cstring) -> Selector ---
}

foreign import core_foundation "system:CoreFoundation.framework"
foreign core_foundation {
	CFStringCreateWithCString :: proc "c" (allocator: rawptr, text: cstring, encoding: u32) -> rawptr ---
	CFRelease                 :: proc "c" (value: rawptr) ---
}

UTF8_ENCODING :: u32(0x08000100)
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
	border_thickness: f32,
	edge_softness:    f32,
	texture_mode:     u32,
	padding:          u32,
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

Renderer :: struct {
	allocator:       mem.Allocator,
	device:          Object,
	pipeline:        Object,
	white_texture:   Object,
	linear_sampler:  Object,
	nearest_sampler: Object,
	textures:        [dynamic]Object,
	runtime_compiled: bool,
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
	p := transmute(proc "c" (_: Object, _: Selector) -> Object)send_address
	return p(receiver, selector)
}

msg_void :: proc(receiver: Object, selector: Selector) {
	p := transmute(proc "c" (_: Object, _: Selector))send_address
	p(receiver, selector)
}

msg_void_id :: proc(receiver: Object, selector: Selector, value: Object) {
	p := transmute(proc "c" (_: Object, _: Selector, _: Object))send_address
	p(receiver, selector, value)
}

msg_void_id_u :: proc(receiver: Object, selector: Selector, value: Object, index: uint) {
	p := transmute(proc "c" (_: Object, _: Selector, _: Object, _: uint))send_address
	p(receiver, selector, value, index)
}

msg_void_bool :: proc(receiver: Object, selector: Selector, value: bool) {
	p := transmute(proc "c" (_: Object, _: Selector, _: bool))send_address
	p(receiver, selector, value)
}

msg_void_u :: proc(receiver: Object, selector: Selector, value: uint) {
	p := transmute(proc "c" (_: Object, _: Selector, _: uint))send_address
	p(receiver, selector, value)
}

msg_id_id :: proc(receiver: Object, selector: Selector, value: Object) -> Object {
	p := transmute(proc "c" (_: Object, _: Selector, _: Object) -> Object)send_address
	return p(receiver, selector, value)
}

msg_id_id_error :: proc(receiver: Object, selector: Selector, value: Object, error: ^Object) -> Object {
	p := transmute(proc "c" (_: Object, _: Selector, _: Object, _: ^Object) -> Object)send_address
	return p(receiver, selector, value, error)
}

msg_id_source_error :: proc(receiver: Object, selector: Selector, source, options: Object, error: ^Object) -> Object {
	p := transmute(proc "c" (_: Object, _: Selector, _: Object, _: Object, _: ^Object) -> Object)send_address
	return p(receiver, selector, source, options, error)
}

msg_id_descriptor_error :: proc(receiver: Object, selector: Selector, descriptor: Object, error: ^Object) -> Object {
	p := transmute(proc "c" (_: Object, _: Selector, _: Object, _: ^Object) -> Object)send_address
	return p(receiver, selector, descriptor, error)
}

msg_id_u :: proc(receiver: Object, selector: Selector, value: uint) -> Object {
	p := transmute(proc "c" (_: Object, _: Selector, _: uint) -> Object)send_address
	return p(receiver, selector, value)
}

msg_id_u_u_u_bool :: proc(receiver: Object, selector: Selector, format, width, height: uint, mipmapped: bool) -> Object {
	p := transmute(proc "c" (_: Object, _: Selector, _: uint, _: uint, _: uint, _: bool) -> Object)send_address
	return p(receiver, selector, format, width, height, mipmapped)
}

msg_id_ptr_u_u :: proc(receiver: Object, selector: Selector, bytes: rawptr, length, options: uint) -> Object {
	p := transmute(proc "c" (_: Object, _: Selector, _: rawptr, _: uint, _: uint) -> Object)send_address
	return p(receiver, selector, bytes, length, options)
}

msg_void_ptr_u_u :: proc(receiver: Object, selector: Selector, bytes: rawptr, length, index: uint) {
	p := transmute(proc "c" (_: Object, _: Selector, _: rawptr, _: uint, _: uint))send_address
	p(receiver, selector, bytes, length, index)
}

msg_void_id_u_u :: proc(receiver: Object, selector: Selector, value: Object, offset, index: uint) {
	p := transmute(proc "c" (_: Object, _: Selector, _: Object, _: uint, _: uint))send_address
	p(receiver, selector, value, offset, index)
}

msg_void_region_u_ptr_u :: proc(receiver: Object, selector: Selector, region: MTL_Region, level: uint, bytes: rawptr, bytes_per_row: uint) {
	p := transmute(proc "c" (_: Object, _: Selector, _: MTL_Region, _: uint, _: rawptr, _: uint))send_address
	p(receiver, selector, region, level, bytes, bytes_per_row)
}

msg_void_scissor :: proc(receiver: Object, selector: Selector, rect: MTL_Scissor_Rect) {
	p := transmute(proc "c" (_: Object, _: Selector, _: MTL_Scissor_Rect))send_address
	p(receiver, selector, rect)
}

msg_void_draw_instanced :: proc(receiver: Object, selector: Selector, primitive, vertex_start, vertex_count, instance_count: uint) {
	p := transmute(proc "c" (_: Object, _: Selector, _: uint, _: uint, _: uint, _: uint))send_address
	p(receiver, selector, primitive, vertex_start, vertex_count, instance_count)
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

load_library :: proc(renderer: ^Renderer, metallib_path: string, allow_runtime_fallback: bool) -> Object {
	error: Object
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

create_pipeline :: proc(renderer: ^Renderer, library: Object, pixel_format: uint) -> Object {
	vertex_name := nsstring("ui_vertex")
	fragment_name := nsstring("ui_fragment")
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
	attachments := msg_id(descriptor, sel_registerName("colorAttachments"))
	attachment := msg_id_u(attachments, sel_registerName("objectAtIndexedSubscript:"), 0)
	msg_void_u(attachment, sel_registerName("setPixelFormat:"), pixel_format)
	msg_void_bool(attachment, sel_registerName("setBlendingEnabled:"), true)
	msg_void_u(attachment, sel_registerName("setSourceRGBBlendFactor:"), 1)
	msg_void_u(attachment, sel_registerName("setDestinationRGBBlendFactor:"), 5)
	msg_void_u(attachment, sel_registerName("setSourceAlphaBlendFactor:"), 1)
	msg_void_u(attachment, sel_registerName("setDestinationAlphaBlendFactor:"), 5)
	error: Object
	return msg_id_descriptor_error(
		renderer.device,
		sel_registerName("newRenderPipelineStateWithDescriptor:error:"),
		descriptor,
		&error,
	)
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
	allow_runtime_fallback := true,
	allocator := context.allocator,
) -> bool {
	assert(renderer != nil)
	if device == nil || !load_objc() {return false}
	renderer^ = Renderer{allocator = allocator, device = device}
	renderer.textures = make([dynamic]Object, allocator)
	library := load_library(renderer, metallib_path, allow_runtime_fallback)
	if library == nil {renderer_destroy(renderer); return false}
	renderer.pipeline = create_pipeline(renderer, library, pixel_format)
	release(library)
	renderer.white_texture = create_white_texture(renderer)
	renderer.linear_sampler = create_sampler(renderer, false)
	renderer.nearest_sampler = create_sampler(renderer, true)
	if renderer.pipeline == nil || renderer.white_texture == nil ||
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

// Snapshot retained Metal texture natives so callers can rebuild matching handles
// after begin_texture_frame without regenerating glyph atlas pages.
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

// Recreate handle indices 1..N from previously snapshotted natives.
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
		border_thickness = instance.border_thickness,
		edge_softness = instance.edge_softness,
		texture_mode = u32(instance.texture_mode),
	}
}

encode :: proc(
	renderer: ^Renderer,
	encoder: Object,
	list: ^draw.List,
	viewport_points: [2]f32,
	backing_scale := f32(1),
) -> bool {
	if renderer == nil || renderer.pipeline == nil || encoder == nil || list == nil {return false}
	total := 0
	for &batch in list.batches {total += len(batch.instances)}
	if total == 0 {return true}
	instances := make([]GPU_Quad_Instance, total, context.temp_allocator)
	defer delete(instances, context.temp_allocator)
	ranges := make([]Batch_Range, len(list.batches), context.temp_allocator)
	defer delete(ranges, context.temp_allocator)
	cursor := 0
	for &batch, index in list.batches {
		ranges[index] = {uint(cursor), uint(len(batch.instances))}
		for instance in batch.instances {
			instances[cursor] = gpu_instance(instance)
			cursor += 1
		}
	}
	buffer := msg_id_ptr_u_u(
		renderer.device,
		sel_registerName("newBufferWithBytes:length:options:"),
		raw_data(instances),
		uint(len(instances))*size_of(GPU_Quad_Instance),
		0,
	)
	if buffer == nil {return false}
	defer release(buffer)
	msg_void_id(encoder, sel_registerName("setRenderPipelineState:"), renderer.pipeline)
	msg_void_id_u_u(encoder, sel_registerName("setVertexBuffer:offset:atIndex:"), buffer, 0, 0)
	for &batch, index in list.batches {
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
		clip := MTL_Scissor_Rect{
			width = uint(max(f32(1), viewport_points[0]*backing_scale)),
			height = uint(max(f32(1), viewport_points[1]*backing_scale)),
		}
		if batch.key.clip_set {
			x0 := max(f32(0), batch.key.clip.x*backing_scale)
			y0 := max(f32(0), (viewport_points[1]-batch.key.clip.y-batch.key.clip.h)*backing_scale)
			x1 := min(viewport_points[0]*backing_scale, (batch.key.clip.x+batch.key.clip.w)*backing_scale)
			y1 := min(viewport_points[1]*backing_scale, (viewport_points[1]-batch.key.clip.y)*backing_scale)
			clip = {
				x = uint(x0),
				y = uint(y0),
				width = uint(max(f32(0), x1-x0)),
				height = uint(max(f32(0), y1-y0)),
			}
			if clip.width == 0 || clip.height == 0 {continue}
		}
		msg_void_scissor(encoder, sel_registerName("setScissorRect:"), clip)
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
	return true
}
