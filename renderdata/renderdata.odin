package renderdata

import draw "ui_framework:draw"
import "core:math"

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

scissor_rect :: proc(key:draw.Batch_Key,viewport:[2]f32,scale:f32)->([4]u32,bool) {
    width,height:=viewport[0]*scale,viewport[1]*scale
    if math.is_nan(width) || math.is_inf(width) || math.is_nan(height) || math.is_inf(height) || scale<=0 || width<=0 || height<=0 || f64(width)>=4294967296 || f64(height)>=4294967296 {return {},false}
    x0,y0,x1,y1:=f32(0),f32(0),width,height
    if key.clip_set {
        clip:=key.clip
        if math.is_nan(clip.x) || math.is_inf(clip.x) || math.is_nan(clip.y) || math.is_inf(clip.y) || math.is_nan(clip.w) || math.is_inf(clip.w) || math.is_nan(clip.h) || math.is_inf(clip.h) {return {},false}
        x0=clamp(clip.x*scale,0,width)
        y0=clamp((viewport[1]-clip.y-clip.h)*scale,0,height)
        x1=clamp((clip.x+clip.w)*scale,0,width)
        y1=clamp((viewport[1]-clip.y)*scale,0,height)
    }
    w,h:=u32(max(f32(0),x1-x0)),u32(max(f32(0),y1-y0))
    if w==0 || h==0 {return {},false}
    return {u32(x0),u32(y0),w,h},true
}
