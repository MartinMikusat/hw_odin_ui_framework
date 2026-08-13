package draw

import "core:math"
import "core:mem"
import nvg "vendor:nanovg"

Path_Direction :: enum {
	Counter_Clockwise,
	Clockwise,
}

Path_Solidity :: enum {
	Solid,
	Hole,
}

Path_Line_Cap :: enum {
	Butt,
	Round,
	Square,
}

Path_Line_Join :: enum {
	Miter,
	Round,
	Bevel,
}

Path_Engine :: struct {
	allocator:         mem.Allocator,
	owner:             ^List,
	ctx:               ^nvg.Context,
	valid:             bool,
	open:              bool,
	fill_rule:         Path_Fill_Rule,
	label:             string,
}

path_value_is_finite :: proc(value: f32) -> bool {
	return !math.is_nan(value) && !math.is_inf(value)
}

path_values_are_finite :: proc(values: ..f32) -> bool {
	for value in values {
		if !path_value_is_finite(value) {return false}
	}
	return true
}

path_batch_destroy :: proc(path: ^Path_Batch) {
	if path == nil {return}
	delete(path.fill)
	delete(path.fringe)
	delete(path.cover)
	path^ = {}
}

batch_destroy :: proc(batch: ^Batch) {
	if batch == nil {return}
	delete(batch.instances)
	path_batch_destroy(&batch.path)
	batch^ = {}
}

path_batch_copy :: proc(destination, source: ^Path_Batch, allocator: mem.Allocator) {
	assert(destination != nil && source != nil)
	destination^ = source^
	destination.fill = make([dynamic]Path_Vertex, 0, len(source.fill), allocator)
	destination.fringe = make([dynamic]Path_Vertex, 0, len(source.fringe), allocator)
	destination.cover = make([dynamic]Path_Vertex, 0, len(source.cover), allocator)
	append(&destination.fill, ..source.fill[:])
	append(&destination.fringe, ..source.fringe[:])
	append(&destination.cover, ..source.cover[:])
}

path_engine_render_create :: proc(uptr: rawptr) -> bool {return uptr != nil}
path_engine_render_delete :: proc(uptr: rawptr) {}

path_engine_create_texture :: proc(
	uptr: rawptr,
	type: nvg.Texture,
	w, h: int,
	image_flags: nvg.ImageFlags,
	data: []byte,
) -> int {
	return 1
}

path_engine_delete_texture :: proc(uptr: rawptr, image: int) -> bool {return true}

path_engine_update_texture :: proc(
	uptr: rawptr,
	image: int,
	x, y: int,
	w, h: int,
	data: []byte,
) -> bool {
	return true
}

path_engine_get_texture_size :: proc(uptr: rawptr, image: int, w, h: ^int) -> bool {
	if w != nil {w^ = nvg.INIT_FONTIMAGE_SIZE}
	if h != nil {h^ = nvg.INIT_FONTIMAGE_SIZE}
	return true
}

path_engine_viewport :: proc(uptr: rawptr, width, height, pixel_ratio: f32) {}
path_engine_cancel :: proc(uptr: rawptr) {}
path_engine_flush :: proc(uptr: rawptr) {}

path_vertex :: proc(vertex: nvg.Vertex) -> Path_Vertex {
	return {position = {vertex[0], vertex[1]}, coverage = {vertex[2], vertex[3]}}
}

append_triangle_fan :: proc(destination: ^[dynamic]Path_Vertex, source: []nvg.Vertex) {
	if len(source) < 3 {return}
	for index in 1 ..< len(source)-1 {
		append(destination, path_vertex(source[0]), path_vertex(source[index]), path_vertex(source[index+1]))
	}
}

append_triangle_strip :: proc(destination: ^[dynamic]Path_Vertex, source: []nvg.Vertex) {
	if len(source) < 3 {return}
	for index in 2 ..< len(source) {
		if index & 1 == 0 {
			append(destination, path_vertex(source[index-2]), path_vertex(source[index-1]), path_vertex(source[index]))
		} else {
			append(destination, path_vertex(source[index-1]), path_vertex(source[index-2]), path_vertex(source[index]))
		}
	}
}

path_bounds :: proc(batch: ^Path_Batch) -> Rect {
	left, bottom := f32(0), f32(0)
	right, top := f32(0), f32(0)
	found := false
	for source_index in 0..<3 {
		vertices := batch.fill[:]
		if source_index == 1 {vertices = batch.fringe[:]}
		if source_index == 2 {vertices = batch.cover[:]}
		for vertex in vertices {
			x, y := vertex.position[0], vertex.position[1]
			if !found {
				left, right, bottom, top = x, x, y, y
				found = true
			} else {
				left, right = min(left, x), max(right, x)
				bottom, top = min(bottom, y), max(top, y)
			}
		}
	}
	if !found {return {}}
	return {left, bottom, right-left, top-bottom}
}

append_path_batch :: proc(engine: ^Path_Engine, batch: Path_Batch) {
	list := engine.owner
	if list == nil {
		delete(batch.fill)
		delete(batch.fringe)
		delete(batch.cover)
		return
	}
	key := batch_key(list, Texture_Handle(0), .Linear)
	key.combine = .Over
	append(&list.batches, Batch{kind = .Path, key = key, path = batch})
	append(&list.trace, Trace_Entry{
		kind = .Path,
		label = engine.label,
		rect = path_bounds(&list.batches[len(list.batches)-1].path),
		batch_index = len(list.batches)-1,
	})
}

path_engine_render_fill :: proc(
	uptr: rawptr,
	paint: ^nvg.Paint,
	composite_operation: nvg.CompositeOperationState,
	scissor: ^nvg.ScissorT,
	fringe: f32,
	bounds: [4]f32,
	paths: []nvg.Path,
) {
	engine := (^Path_Engine)(uptr)
	if engine == nil || engine.owner == nil || paint == nil {return}
	kind := Path_Batch_Kind.Compound_Fill
	if len(paths) == 1 && paths[0].convex {kind = .Convex_Fill}
	batch := Path_Batch{
		kind = kind,
		fill_rule = engine.fill_rule,
		color = Color(paint.innerColor),
		stroke_mult = 1,
	}
	batch.fill = make([dynamic]Path_Vertex, 0, 128, engine.owner.allocator)
	batch.fringe = make([dynamic]Path_Vertex, 0, 128, engine.owner.allocator)
	batch.cover = make([dynamic]Path_Vertex, 0, 6, engine.owner.allocator)
	for path in paths {
		append_triangle_fan(&batch.fill, path.fill)
		append_triangle_strip(&batch.fringe, path.stroke)
	}
	if len(batch.fill) == 0 && len(batch.fringe) == 0 {
		path_batch_destroy(&batch)
		return
	}
	if kind == .Compound_Fill {
		cover := [4]nvg.Vertex{
			{bounds[2], bounds[3], 0.5, 1},
			{bounds[2], bounds[1], 0.5, 1},
			{bounds[0], bounds[3], 0.5, 1},
			{bounds[0], bounds[1], 0.5, 1},
		}
		append_triangle_strip(&batch.cover, cover[:])
	}
	append_path_batch(engine, batch)
}

path_engine_render_stroke :: proc(
	uptr: rawptr,
	paint: ^nvg.Paint,
	composite_operation: nvg.CompositeOperationState,
	scissor: ^nvg.ScissorT,
	fringe, stroke_width: f32,
	paths: []nvg.Path,
) {
	engine := (^Path_Engine)(uptr)
	if engine == nil || engine.owner == nil || paint == nil {return}
	stroke_mult := f32(1)
	if fringe > 0 {stroke_mult = (stroke_width*0.5+fringe*0.5)/fringe}
	batch := Path_Batch{
		kind = .Stroke,
		color = Color(paint.innerColor),
		stroke_mult = stroke_mult,
	}
	batch.fill = make([dynamic]Path_Vertex, 0, 128, engine.owner.allocator)
	batch.fringe = make([dynamic]Path_Vertex, engine.owner.allocator)
	batch.cover = make([dynamic]Path_Vertex, engine.owner.allocator)
	for path in paths {append_triangle_strip(&batch.fill, path.stroke)}
	if len(batch.fill) == 0 {
		path_batch_destroy(&batch)
		return
	}
	append_path_batch(engine, batch)
}

path_engine_render_triangles :: proc(
	uptr: rawptr,
	paint: ^nvg.Paint,
	composite_operation: nvg.CompositeOperationState,
	scissor: ^nvg.ScissorT,
	vertices: []nvg.Vertex,
	fringe: f32,
) {}

path_engine_ensure :: proc(list: ^List) -> ^Path_Engine {
	if list == nil {return nil}
	if list.path_engine == nil {
		engine := new(Path_Engine, list.allocator)
		engine^ = Path_Engine{allocator = list.allocator, owner = list, valid = true}
		params := nvg.Params{
			userPtr = engine,
			edgeAntiAlias = true,
			renderCreate = path_engine_render_create,
			renderDelete = path_engine_render_delete,
			renderCreateTexture = path_engine_create_texture,
			renderDeleteTexture = path_engine_delete_texture,
			renderUpdateTexture = path_engine_update_texture,
			renderGetTextureSize = path_engine_get_texture_size,
			renderViewport = path_engine_viewport,
			renderCancel = path_engine_cancel,
			renderFlush = path_engine_flush,
			renderFill = path_engine_render_fill,
			renderStroke = path_engine_render_stroke,
			renderTriangles = path_engine_render_triangles,
		}
		previous_allocator := context.allocator
		context.allocator = list.allocator
		engine.ctx = nvg.CreateInternal(params)
		context.allocator = previous_allocator
		list.path_engine = engine
		nvg.BeginFrame(engine.ctx, 1, 1, list.pixel_ratio)
	}
	list.path_engine.owner = list
	return list.path_engine
}

path_engine_reset :: proc(list: ^List) {
	if list == nil || list.path_engine == nil {return}
	list.path_engine.owner = list
	list.path_engine.valid = true
	list.path_engine.open = false
	nvg.BeginFrame(list.path_engine.ctx, 1, 1, list.pixel_ratio)
}

path_engine_destroy :: proc(list: ^List) {
	if list == nil || list.path_engine == nil {return}
	previous_allocator := context.allocator
	context.allocator = list.path_engine.allocator
	nvg.DeleteInternal(list.path_engine.ctx)
	allocator := list.path_engine.allocator
	free(list.path_engine, allocator)
	context.allocator = previous_allocator
	list.path_engine = nil
}

list_set_pixel_ratio :: proc(list: ^List, pixel_ratio: f32) {
	if list == nil {return}
	ratio := f32(1)
	if path_value_is_finite(pixel_ratio) {ratio = max(pixel_ratio, 1)}
	if ratio == list.pixel_ratio {return}
	list.pixel_ratio = ratio
	if list.path_engine != nil {path_engine_reset(list)}
}

path_invalidate_unless :: proc(engine: ^Path_Engine, values: ..f32) -> bool {
	if engine == nil || !engine.open || !engine.valid {return false}
	if !path_values_are_finite(..values) {
		engine.valid = false
		return false
	}
	return true
}

path_begin :: proc(list: ^List) {
	engine := path_engine_ensure(list)
	if engine == nil {return}
	engine.valid = true
	engine.open = true
	engine.label = ""
	nvg.BeginPath(engine.ctx)
}

path_move_to :: proc(list: ^List, x, y: f32) {
	engine := path_engine_ensure(list)
	if !path_invalidate_unless(engine, x, y) {return}
	nvg.MoveTo(engine.ctx, x, y)
}

path_line_to :: proc(list: ^List, x, y: f32) {
	engine := path_engine_ensure(list)
	if !path_invalidate_unless(engine, x, y) {return}
	nvg.LineTo(engine.ctx, x, y)
}

path_quad_to :: proc(list: ^List, control_x, control_y, x, y: f32) {
	engine := path_engine_ensure(list)
	if !path_invalidate_unless(engine, control_x, control_y, x, y) {return}
	nvg.QuadTo(engine.ctx, control_x, control_y, x, y)
}

path_cubic_to :: proc(list: ^List, c1x, c1y, c2x, c2y, x, y: f32) {
	engine := path_engine_ensure(list)
	if !path_invalidate_unless(engine, c1x, c1y, c2x, c2y, x, y) {return}
	nvg.BezierTo(engine.ctx, c1x, c1y, c2x, c2y, x, y)
}

path_arc_to :: proc(list: ^List, x1, y1, x2, y2, radius: f32) {
	engine := path_engine_ensure(list)
	if !path_invalidate_unless(engine, x1, y1, x2, y2, radius) || radius < 0 {return}
	nvg.ArcTo(engine.ctx, x1, y1, x2, y2, radius)
}

path_arc :: proc(
	list: ^List,
	center_x, center_y, radius, start_angle, end_angle: f32,
	direction := Path_Direction.Clockwise,
) {
	engine := path_engine_ensure(list)
	if !path_invalidate_unless(engine, center_x, center_y, radius, start_angle, end_angle) || radius < 0 {return}
	nvg_direction := nvg.Winding.CW
	if direction == .Counter_Clockwise {nvg_direction = .CCW}
	nvg.Arc(engine.ctx, center_x, center_y, radius, start_angle, end_angle, nvg_direction)
}

path_close :: proc(list: ^List) {
	engine := path_engine_ensure(list)
	if engine == nil || !engine.open || !engine.valid {return}
	nvg.ClosePath(engine.ctx)
}

path_solidity :: proc(list: ^List, solidity: Path_Solidity) {
	engine := path_engine_ensure(list)
	if engine == nil || !engine.open || !engine.valid {return}
	value := nvg.Solidity.SOLID
	if solidity == .Hole {value = .HOLE}
	nvg.PathSolidity(engine.ctx, value)
}

path_winding :: proc(list: ^List, direction: Path_Direction) {
	engine := path_engine_ensure(list)
	if engine == nil || !engine.open || !engine.valid {return}
	value := nvg.Winding.CW
	if direction == .Counter_Clockwise {value = .CCW}
	nvg.PathWinding(engine.ctx, value)
}

path_rect :: proc(list: ^List, rect: Rect) {
	engine := path_engine_ensure(list)
	if !path_invalidate_unless(engine, rect.x, rect.y, rect.w, rect.h) || rect_is_empty(rect) {return}
	nvg.Rect(engine.ctx, rect.x, rect.y, rect.w, rect.h)
}

path_rounded_rect :: proc(list: ^List, rect: Rect, radius: f32) {
	engine := path_engine_ensure(list)
	if !path_invalidate_unless(engine, rect.x, rect.y, rect.w, rect.h, radius) || rect_is_empty(rect) || radius < 0 {return}
	nvg.RoundedRect(engine.ctx, rect.x, rect.y, rect.w, rect.h, radius)
}

path_circle :: proc(list: ^List, center_x, center_y, radius: f32) {
	engine := path_engine_ensure(list)
	if !path_invalidate_unless(engine, center_x, center_y, radius) || radius <= 0 {return}
	nvg.Circle(engine.ctx, center_x, center_y, radius)
}

path_ellipse :: proc(list: ^List, center_x, center_y, radius_x, radius_y: f32) {
	engine := path_engine_ensure(list)
	if !path_invalidate_unless(engine, center_x, center_y, radius_x, radius_y) || radius_x <= 0 || radius_y <= 0 {return}
	nvg.Ellipse(engine.ctx, center_x, center_y, radius_x, radius_y)
}

path_fill :: proc(
	list: ^List,
	color: Color,
	rule := Path_Fill_Rule.Non_Zero,
	label := "",
) {
	engine := path_engine_ensure(list)
	if engine == nil || !engine.open || !engine.valid || color[3] <= 0 {return}
	if !path_values_are_finite(color[0], color[1], color[2], color[3]) {engine.valid = false; return}
	engine.fill_rule = rule
	engine.label = label
	nvg.FillColor(engine.ctx, nvg.Color(color))
	nvg.Fill(engine.ctx)
}

path_stroke :: proc(
	list: ^List,
	color: Color,
	width: f32,
	cap := Path_Line_Cap.Butt,
	join := Path_Line_Join.Miter,
	miter_limit := f32(10),
	label := "",
) {
	engine := path_engine_ensure(list)
	if engine == nil || !engine.open || !engine.valid || color[3] <= 0 || width <= 0 {return}
	if !path_values_are_finite(
		width,
		miter_limit,
		color[0],
		color[1],
		color[2],
		color[3],
	) {engine.valid = false; return}
	nvg_cap := nvg.LineCapType.BUTT
	switch cap {
	case .Round: nvg_cap = .ROUND
	case .Square: nvg_cap = .SQUARE
	case .Butt:
	}
	nvg_join := nvg.LineCapType.MITER
	switch join {
	case .Round: nvg_join = .ROUND
	case .Bevel: nvg_join = .BEVEL
	case .Miter:
	}
	engine.label = label
	nvg.StrokeColor(engine.ctx, nvg.Color(color))
	nvg.StrokeWidth(engine.ctx, width)
	nvg.LineCap(engine.ctx, nvg_cap)
	nvg.LineJoin(engine.ctx, nvg_join)
	nvg.MiterLimit(engine.ctx, max(miter_limit, 0))
	nvg.Stroke(engine.ctx)
}
