package draw

import "core:mem"

Texture_Handle :: distinct u64

Rect :: struct {
	x, y, w, h: f32,
}

Color :: [4]f32

Transform_2D :: struct {
	m00, m01, m10, m11, tx, ty: f32,
}

IDENTITY_TRANSFORM :: Transform_2D{1, 0, 0, 1, 0, 0}

Sampler :: enum {
	Linear,
	Nearest,
}

Texture_Mode :: enum {
	Solid,
	Alpha_Mask,
	Color,
}

Quad_Instance :: struct {
	dst:              Rect,
	src:              Rect,
	colors:           [4]Color,
	corner_radii:     [4]f32,
	border_thickness: f32,
	edge_softness:    f32,
	texture_mode:     Texture_Mode,
}

Batch_Key :: struct {
	texture:  Texture_Handle,
	sampler:  Sampler,
	clip:     Rect,
	clip_set: bool,
	transform: Transform_2D,
	opacity:  f32,
}

Batch :: struct {
	key:       Batch_Key,
	instances: [dynamic]Quad_Instance,
}

Trace_Kind :: enum {
	Solid,
	Image,
	Glyph,
	Icon,
	Group_Begin,
	Group_End,
}

Trace_Entry :: struct {
	kind:        Trace_Kind,
	label:       string,
	rect:        Rect,
	texture:     Texture_Handle,
	batch_index: int,
}

List :: struct {
	allocator:         mem.Allocator,
	batches:           [dynamic]Batch,
	trace:             [dynamic]Trace_Entry,
	clip_stack:        [dynamic]Rect,
	transform_stack:   [dynamic]Transform_2D,
	opacity_stack:     [dynamic]f32,
	clip_enabled_stack: [dynamic]bool,
}

Bucket :: List

rect_right :: proc(rect: Rect) -> f32 {
	return rect.x + rect.w
}

rect_top :: proc(rect: Rect) -> f32 {
	return rect.y + rect.h
}

rect_is_empty :: proc(rect: Rect) -> bool {
	return rect.w <= 0 || rect.h <= 0
}

rect_intersection :: proc(a, b: Rect) -> Rect {
	x0 := max(a.x, b.x)
	y0 := max(a.y, b.y)
	x1 := min(rect_right(a), rect_right(b))
	y1 := min(rect_top(a), rect_top(b))
	return {x0, y0, max(f32(0), x1-x0), max(f32(0), y1-y0)}
}

transform_compose :: proc(parent, child: Transform_2D) -> Transform_2D {
	return {
		m00 = parent.m00*child.m00+parent.m10*child.m01,
		m01 = parent.m01*child.m00+parent.m11*child.m01,
		m10 = parent.m00*child.m10+parent.m10*child.m11,
		m11 = parent.m01*child.m10+parent.m11*child.m11,
		tx = parent.m00*child.tx+parent.m10*child.ty+parent.tx,
		ty = parent.m01*child.tx+parent.m11*child.ty+parent.ty,
	}
}

transform_point :: proc(transform: Transform_2D, x, y: f32) -> (f32, f32) {
	return transform.m00*x+transform.m10*y+transform.tx,
	       transform.m01*x+transform.m11*y+transform.ty
}

transform_rect_bounds :: proc(transform: Transform_2D, rect: Rect) -> Rect {
	x0, y0 := transform_point(transform, rect.x, rect.y)
	x1, y1 := transform_point(transform, rect.x+rect.w, rect.y)
	x2, y2 := transform_point(transform, rect.x, rect.y+rect.h)
	x3, y3 := transform_point(transform, rect.x+rect.w, rect.y+rect.h)
	left := min(min(x0, x1), min(x2, x3))
	right := max(max(x0, x1), max(x2, x3))
	bottom := min(min(y0, y1), min(y2, y3))
	top := max(max(y0, y1), max(y2, y3))
	return {left, bottom, right-left, top-bottom}
}

list_init :: proc(list: ^List, allocator := context.allocator) {
	assert(list != nil)
	list^ = List{allocator = allocator}
	list.batches = make([dynamic]Batch, allocator)
	list.trace = make([dynamic]Trace_Entry, allocator)
	list.clip_stack = make([dynamic]Rect, allocator)
	list.transform_stack = make([dynamic]Transform_2D, allocator)
	list.opacity_stack = make([dynamic]f32, allocator)
	list.clip_enabled_stack = make([dynamic]bool, allocator)
	append(&list.transform_stack, IDENTITY_TRANSFORM)
	append(&list.opacity_stack, 1)
	append(&list.clip_stack, Rect{})
	append(&list.clip_enabled_stack, false)
}

list_reset :: proc(list: ^List) {
	if list == nil {return}
	for &batch in list.batches {delete(batch.instances)}
	clear(&list.batches)
	clear(&list.trace)
	clear(&list.clip_stack)
	clear(&list.transform_stack)
	clear(&list.opacity_stack)
	clear(&list.clip_enabled_stack)
	append(&list.transform_stack, IDENTITY_TRANSFORM)
	append(&list.opacity_stack, 1)
	append(&list.clip_stack, Rect{})
	append(&list.clip_enabled_stack, false)
}

list_destroy :: proc(list: ^List) {
	if list == nil {return}
	for &batch in list.batches {delete(batch.instances)}
	delete(list.batches)
	delete(list.trace)
	delete(list.clip_stack)
	delete(list.transform_stack)
	delete(list.opacity_stack)
	delete(list.clip_enabled_stack)
	list^ = {}
}

bucket_init :: proc(bucket: ^Bucket, allocator := context.allocator) {
	list_init(bucket, allocator)
}

bucket_reset :: proc(bucket: ^Bucket) {list_reset(bucket)}

bucket_destroy :: proc(bucket: ^Bucket) {list_destroy(bucket)}

begin_group :: proc(list: ^List, label: string) {
	append(&list.trace, Trace_Entry{kind = .Group_Begin, label = label, batch_index = -1})
}

end_group :: proc(list: ^List, label: string = "") {
	append(&list.trace, Trace_Entry{kind = .Group_End, label = label, batch_index = -1})
}

append_bucket :: proc(list: ^List, bucket: ^Bucket) {
	assert(list != nil && bucket != nil && list != bucket)
	parent_clip, parent_clip_set := top_clip(list)
	parent_transform := top_transform(list)
	parent_opacity := top_opacity(list)
	batch_map := make([]int, len(bucket.batches), list.allocator)
	defer delete(batch_map, list.allocator)
	for source, source_index in bucket.batches {
		key := source.key
		if source.key.clip_set {
			key.clip = transform_rect_bounds(parent_transform, source.key.clip)
		}
		if parent_clip_set {
			key.clip = parent_clip
			if source.key.clip_set {
				key.clip = rect_intersection(
					parent_clip,
					transform_rect_bounds(parent_transform, source.key.clip),
				)
			}
			key.clip_set = true
		}
		key.transform = transform_compose(parent_transform, source.key.transform)
		key.opacity *= parent_opacity
		destination_index := len(list.batches)-1
		if destination_index < 0 || list.batches[destination_index].key != key {
			copy := Batch{key = key}
			copy.instances = make(
				[dynamic]Quad_Instance,
				0,
				max(64, len(source.instances)),
				list.allocator,
			)
			append(&list.batches, copy)
			destination_index += 1
		}
		append(&list.batches[destination_index].instances, ..source.instances[:])
		batch_map[source_index] = destination_index
	}
	for source in bucket.trace {
		copy := source
		if source.batch_index >= 0 {copy.batch_index = batch_map[source.batch_index]}
		append(&list.trace, copy)
	}
}

top_clip :: proc(list: ^List) -> (Rect, bool) {
	index := len(list.clip_stack)-1
	return list.clip_stack[index], list.clip_enabled_stack[index]
}

top_transform :: proc(list: ^List) -> Transform_2D {
	return list.transform_stack[len(list.transform_stack)-1]
}

top_opacity :: proc(list: ^List) -> f32 {
	return list.opacity_stack[len(list.opacity_stack)-1]
}

push_clip :: proc(list: ^List, rect: Rect) {
	previous, enabled := top_clip(list)
	next := transform_rect_bounds(top_transform(list), rect)
	if enabled {next = rect_intersection(previous, rect)}
	append(&list.clip_stack, next)
	append(&list.clip_enabled_stack, true)
}

pop_clip :: proc(list: ^List) {
	assert(len(list.clip_stack) > 1)
	resize(&list.clip_stack, len(list.clip_stack)-1)
	resize(&list.clip_enabled_stack, len(list.clip_enabled_stack)-1)
}

push_transform :: proc(list: ^List, transform: Transform_2D) {
	append(&list.transform_stack, transform_compose(top_transform(list), transform))
}

pop_transform :: proc(list: ^List) {
	assert(len(list.transform_stack) > 1)
	resize(&list.transform_stack, len(list.transform_stack)-1)
}

push_opacity :: proc(list: ^List, opacity: f32) {
	append(&list.opacity_stack, top_opacity(list)*min(max(opacity, 0), 1))
}

pop_opacity :: proc(list: ^List) {
	assert(len(list.opacity_stack) > 1)
	resize(&list.opacity_stack, len(list.opacity_stack)-1)
}

batch_key :: proc(list: ^List, texture: Texture_Handle, sampler: Sampler) -> Batch_Key {
	clip, clip_set := top_clip(list)
	return {
		texture = texture,
		sampler = sampler,
		clip = clip,
		clip_set = clip_set,
		transform = top_transform(list),
		opacity = top_opacity(list),
	}
}

append_quad :: proc(
	list: ^List,
	instance: Quad_Instance,
	texture := Texture_Handle(0),
	sampler := Sampler.Linear,
	kind := Trace_Kind.Solid,
	label := "",
) {
	assert(list != nil)
	key := batch_key(list, texture, sampler)
	batch_index := len(list.batches)-1
	if batch_index < 0 || list.batches[batch_index].key != key {
		batch := Batch{key = key}
		batch.instances = make([dynamic]Quad_Instance, 0, 64, list.allocator)
		append(&list.batches, batch)
		batch_index += 1
	}
	append(&list.batches[batch_index].instances, instance)
	append(&list.trace, Trace_Entry{
		kind = kind,
		label = label,
		rect = instance.dst,
		texture = texture,
		batch_index = batch_index,
	})
}

solid :: proc(
	list: ^List,
	rect: Rect,
	color: Color,
	corner_radius: f32 = 0,
	border_thickness: f32 = 0,
	edge_softness: f32 = 1,
	label := "",
) {
	if rect_is_empty(rect) || color[3] <= 0 {return}
	instance := Quad_Instance{
		dst = rect,
		colors = {color, color, color, color},
		corner_radii = {corner_radius, corner_radius, corner_radius, corner_radius},
		border_thickness = border_thickness,
		edge_softness = edge_softness,
		texture_mode = .Solid,
	}
	append_quad(list, instance, kind = .Solid, label = label)
}

image :: proc(
	list: ^List,
	texture: Texture_Handle,
	dst, src: Rect,
	color: Color = {1, 1, 1, 1},
	mode := Texture_Mode.Color,
	sampler := Sampler.Linear,
	kind := Trace_Kind.Image,
	label := "",
) {
	if texture == Texture_Handle(0) || rect_is_empty(dst) || color[3] <= 0 {return}
	instance := Quad_Instance{
		dst = dst,
		src = src,
		colors = {color, color, color, color},
		texture_mode = mode,
	}
	append_quad(list, instance, texture, sampler, kind, label)
}
