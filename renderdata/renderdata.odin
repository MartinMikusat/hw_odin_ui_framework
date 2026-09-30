package renderdata

import draw "ui_framework:draw"

Quad_Instance :: struct {
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

Path_Vertex :: struct {
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

quad_instance :: proc(instance: draw.Quad_Instance) -> Quad_Instance {
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

path_vertex :: proc(vertex: draw.Path_Vertex) -> Path_Vertex {
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
	vertices: []Path_Vertex,
	ranges: []Path_Batch_Range,
) {
	assert(list!=nil && len(ranges)==len(list.batches))
	assert(len(vertices)==path_vertex_count(list))
	cursor := 0
	for &batch, index in list.batches {
		if batch.kind != .Path {continue}
		ranges[index].fill = {uint(cursor), uint(len(batch.path.fill))}
		for vertex in batch.path.fill {vertices[cursor] = path_vertex(vertex); cursor += 1}
		ranges[index].fringe = {uint(cursor), uint(len(batch.path.fringe))}
		for vertex in batch.path.fringe {vertices[cursor] = path_vertex(vertex); cursor += 1}
		ranges[index].cover = {uint(cursor), uint(len(batch.path.cover))}
		for vertex in batch.path.cover {vertices[cursor] = path_vertex(vertex); cursor += 1}
	}
	assert(cursor==len(vertices))
}

#assert(size_of(Quad_Instance)==144)
#assert(size_of(Path_Vertex)==16)
#assert(size_of(Batch_Uniforms)==48)
#assert(size_of(Path_Uniforms)==80)
