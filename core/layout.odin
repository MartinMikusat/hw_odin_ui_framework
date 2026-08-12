package ui

import draw "ui_framework:draw"

content_rect :: proc(box: ^Box) -> draw.Rect {
	return {
		box.rect.x + box.layout.padding.left,
		box.rect.y + box.layout.padding.bottom,
		max(f32(0), box.rect.w-box.layout.padding.left-box.layout.padding.right),
		max(f32(0), box.rect.h-box.layout.padding.bottom-box.layout.padding.top),
	}
}

clamp_size :: proc(value: f32, spec: Size) -> f32 {
	result := max(value, spec.minimum)
	if spec.maximum > 0 {result = min(result, spec.maximum)}
	return result
}

measure_text :: proc(frame: ^Frame, box: ^Box) -> Text_Metrics {
	if len(box.text) == 0 || frame.text_backend.prepare == nil {return {}}
	prepared := frame.text_backend.prepare(
		frame.text_backend.user_data,
		box.style.text_style.font,
		box.text,
		box.style.text_style.size,
		box.style.text_style.tracking,
		0,
		false,
	)
	box.text_run = prepared.run
	return prepared.metrics
}

prepare_final_text_runs :: proc(frame: ^Frame) {
	if frame.text_backend.prepare == nil {return}
	for &box in frame.boxes {
		if .Draw_Text not_in box.flags || len(box.text) == 0 {continue}
		if !box.style.text_style.truncate && box.text_run != Text_Run_ID(0) {continue}
		maximum_width := f32(0)
		if box.style.text_style.truncate {
			maximum_width = max(
				f32(0),
				box.rect.w-box.style.text_style.inset*2,
			)
		}
		prepared := frame.text_backend.prepare(
			frame.text_backend.user_data,
			box.style.text_style.font,
			box.text,
			box.style.text_style.size,
			box.style.text_style.tracking,
			maximum_width,
			box.style.text_style.truncate,
		)
		box.text_run = prepared.run
		box.text_metrics = prepared.metrics
	}
}

axis_spec :: proc(box: ^Box, axis: Axis) -> Size {
	return box.layout.width if axis == .Horizontal else box.layout.height
}

axis_desired :: proc(box: ^Box, axis: Axis) -> f32 {
	return box.desired.x if axis == .Horizontal else box.desired.y
}

set_axis_desired :: proc(box: ^Box, axis: Axis, value: f32) {
	if axis == .Horizontal {box.desired.x = value} else {box.desired.y = value}
}

axis_padding :: proc(box: ^Box, axis: Axis) -> f32 {
	if axis == .Horizontal {return box.layout.padding.left+box.layout.padding.right}
	return box.layout.padding.bottom+box.layout.padding.top
}

axis_text_size :: proc(box: ^Box, axis: Axis) -> f32 {
	if axis == .Horizontal {return box.text_metrics.width+axis_padding(box, axis)}
	return box.text_metrics.ascent+box.text_metrics.descent+axis_padding(box, axis)
}

layout_measure_standalone :: proc(frame: ^Frame, axis: Axis) {
	for &box in frame.boxes {
		if axis == .Horizontal {box.text_metrics = measure_text(frame, &box)}
		spec := axis_spec(&box, axis)
		value := f32(0)
		switch spec.kind {
		case .Points: value = spec.value
		case .Text: value = axis_text_size(&box, axis)
		case .Auto: value = axis_text_size(&box, axis)
		case .Percent, .Remaining, .Children_Sum: value = spec.minimum
		}
		set_axis_desired(&box, axis, clamp_size(value, spec))
	}
}

layout_measure_upward :: proc(frame: ^Frame, index: int, axis: Axis) -> f32 {
	box := &frame.boxes[index]
	children_value := f32(0)
	child_count := 0
	flow_axis := (box.layout.flow == .Row && axis == .Horizontal) ||
	             (box.layout.flow == .Column && axis == .Vertical)
	for child := box.first_child; child >= 0; child = frame.boxes[child].next_sibling {
		if frame.boxes[child].layout.position == .Absolute {continue}
		value := layout_measure_upward(frame, child, axis)
		if child_count == 0 || flow_axis {
			children_value += value
		} else {
			children_value = max(children_value, value)
		}
		child_count += 1
	}
	if flow_axis && child_count > 1 {children_value += box.layout.gap*f32(child_count-1)}
	children_value += axis_padding(box, axis)
	spec := axis_spec(box, axis)
	value := axis_desired(box, axis)
	switch spec.kind {
	case .Children_Sum: value = children_value
	case .Auto: value = max(value, children_value)
	case .Points, .Text, .Percent, .Remaining:
	}
	value = clamp_size(value, spec)
	set_axis_desired(box, axis, value)
	return value
}

resolve_axis_size :: proc(spec: Size, desired, available, remaining_space, remaining_weight: f32) -> f32 {
	value := desired
	switch spec.kind {
	case .Points: value = spec.value
	case .Percent: value = available*spec.value
	case .Remaining:
		weight := spec.value
		if weight <= 0 {weight = 1}
		if remaining_weight > 0 {value = remaining_space*weight/remaining_weight}
	case .Text, .Children_Sum, .Auto:
	}
	return clamp_size(value, spec)
}

align_cross :: proc(container_start, container_size, child_size: f32, align: Align) -> f32 {
	switch align {
	case .Center: return container_start + (container_size-child_size)/2
	case .End: return container_start + container_size-child_size
	case .Start, .Stretch: return container_start
	}
	return container_start
}

axis_allows_overflow :: proc(box: ^Box, horizontal: bool) -> bool {
	return (.Allow_Overflow_X in box.flags) if horizontal else (.Allow_Overflow_Y in box.flags)
}

shrink_capacity :: proc(size: f32, spec: Size) -> f32 {
	return max(f32(0), size-spec.minimum)*(1-min(max(spec.strictness, 0), 1))
}

shrink_size :: proc(size: f32, spec: Size, violation, capacity: f32) -> f32 {
	if violation <= 0 || capacity <= 0 {return size}
	share := violation*shrink_capacity(size, spec)/capacity
	return max(spec.minimum, size-share)
}

resolve_flow_main_size :: proc(
	spec: Size,
	desired, available, remaining_extra, remaining_weight: f32,
	violation, shrinkable: f32,
) -> f32 {
	if spec.kind == .Remaining {
		weight := max(f32(1), spec.value)
		extra := f32(0)
		if remaining_weight > 0 {
			extra = remaining_extra*weight/remaining_weight
		}
		return clamp_size(spec.minimum+extra, spec)
	}
	resolved := resolve_axis_size(spec, desired, available, 0, 0)
	return shrink_size(resolved, spec, violation, shrinkable)
}

translate_subtree :: proc(frame: ^Frame, index: int, delta: Vec2) {
	box := &frame.boxes[index]
	box.rect.x += delta.x
	box.rect.y += delta.y
	for child := box.first_child; child >= 0; child = frame.boxes[child].next_sibling {
		translate_subtree(frame, child, delta)
	}
}

apply_scroll_layout :: proc(frame: ^Frame, index: int, content: draw.Rect) {
	box := &frame.boxes[index]
	if .Scroll not_in box.flags || box.first_child < 0 {return}
	max_right := content.x
	min_bottom := content.y+content.h
	for child := box.first_child; child >= 0; child = frame.boxes[child].next_sibling {
		child_box := &frame.boxes[child]
		max_right = max(max_right, child_box.rect.x+child_box.rect.w)
		min_bottom = min(min_bottom, child_box.rect.y)
	}
	box.overflow = {
		max(f32(0), max_right-(content.x+content.w)),
		max(f32(0), content.y-min_bottom),
	}
	state := frame.ui.states[box.key]
	state.view_bounds = {content.w+box.overflow.x, content.h+box.overflow.y}
	state.scroll_target.x = min(max(state.scroll_target.x, 0), box.overflow.x)
	state.scroll_target.y = min(max(state.scroll_target.y, 0), box.overflow.y)
	animating_x: bool
	state.scroll.x, animating_x = animation_step(
		state.scroll.x,
		state.scroll_target.x,
		22,
		frame.input.delta_seconds,
		0.01,
	)
	animating_y: bool
	state.scroll.y, animating_y = animation_step(
		state.scroll.y,
		state.scroll_target.y,
		22,
		frame.input.delta_seconds,
		0.01,
	)
	frame.ui.states[box.key] = state
	if animating_x || animating_y {request_frame(frame.ui, .Animation)}
	if state.scroll.x == 0 && state.scroll.y == 0 {return}
	delta := Vec2{-state.scroll.x, state.scroll.y}
	for child := box.first_child; child >= 0; child = frame.boxes[child].next_sibling {
		translate_subtree(frame, child, delta)
	}
}

arrange_children :: proc(frame: ^Frame, index: int) {
	box := &frame.boxes[index]
	content := content_rect(box)
	if box.first_child < 0 {return}
	if box.layout.flow == .Overlay {
		for child_index := box.first_child; child_index >= 0; child_index = frame.boxes[child_index].next_sibling {
			child := &frame.boxes[child_index]
			if child.layout.position == .Absolute {
				child.rect = {
					content.x+child.layout.absolute.x+child.layout.offset.x,
					content.y+child.layout.absolute.y+child.layout.offset.y,
					child.layout.absolute.w,
					child.layout.absolute.h,
				}
			} else {
				width := resolve_axis_size(child.layout.width, child.desired.x, content.w, content.w, 1)
				height := resolve_axis_size(child.layout.height, child.desired.y, content.h, content.h, 1)
				if box.layout.cross_align == .Stretch {width = content.w}
				if box.layout.main_align == .Stretch {height = content.h}
				child.rect = {
					align_cross(content.x, content.w, width, box.layout.cross_align)+child.layout.offset.x,
					align_cross(content.y, content.h, height, box.layout.main_align)+child.layout.offset.y,
					width,
					height,
				}
			}
			arrange_children(frame, child_index)
		}
		apply_scroll_layout(frame, index, content)
		return
	}
	horizontal := box.layout.flow == .Row
	main_available := content.w if horizontal else content.h
	cross_available := content.h if horizontal else content.w
	fixed: f32
	remaining_minimum: f32
	shrinkable: f32
	remaining_weight: f32
	flow_count := 0
	for child_index := box.first_child; child_index >= 0; child_index = frame.boxes[child_index].next_sibling {
		child := &frame.boxes[child_index]
		if child.layout.position == .Absolute {continue}
		flow_count += 1
		spec := child.layout.width if horizontal else child.layout.height
		desired := child.desired.x if horizontal else child.desired.y
		if spec.kind == .Remaining {
			remaining_weight += max(f32(1), spec.value)
			remaining_minimum += spec.minimum
		} else {
			resolved := resolve_axis_size(spec, desired, main_available, 0, 0)
			fixed += resolved
			shrinkable += shrink_capacity(resolved, spec)
		}
	}
	gap_total := box.layout.gap*f32(max(0, flow_count-1))
	violation := max(
		f32(0),
		fixed+remaining_minimum+gap_total-main_available,
	)
	if axis_allows_overflow(box, horizontal) {violation = 0}
	resolved_violation := min(violation, shrinkable)
	fixed -= resolved_violation
	remaining_extra := max(
		f32(0),
		main_available-fixed-remaining_minimum-gap_total,
	)
	used := gap_total
	for child_index := box.first_child; child_index >= 0; child_index = frame.boxes[child_index].next_sibling {
		child := &frame.boxes[child_index]
		if child.layout.position == .Absolute {continue}
		spec := child.layout.width if horizontal else child.layout.height
		desired := child.desired.x if horizontal else child.desired.y
		used += resolve_flow_main_size(
			spec,
			desired,
			main_available,
			remaining_extra,
			remaining_weight,
			resolved_violation,
			shrinkable,
		)
	}
	main_cursor := f32(0)
	if box.layout.main_align == .Center {main_cursor = (main_available-used)/2}
	if box.layout.main_align == .End {main_cursor = main_available-used}
	for child_index := box.first_child; child_index >= 0; child_index = frame.boxes[child_index].next_sibling {
		child := &frame.boxes[child_index]
		if child.layout.position == .Absolute {
			child.rect = {
				content.x+child.layout.absolute.x+child.layout.offset.x,
				content.y+child.layout.absolute.y+child.layout.offset.y,
				child.layout.absolute.w,
				child.layout.absolute.h,
			}
			arrange_children(frame, child_index)
			continue
		}
		main_spec := child.layout.width if horizontal else child.layout.height
		cross_spec := child.layout.height if horizontal else child.layout.width
		main_desired := child.desired.x if horizontal else child.desired.y
		cross_desired := child.desired.y if horizontal else child.desired.x
		main_size := resolve_flow_main_size(
			main_spec,
			main_desired,
			main_available,
			remaining_extra,
			remaining_weight,
			resolved_violation,
			shrinkable,
		)
		cross_size := resolve_axis_size(cross_spec, cross_desired, cross_available, cross_available, 1)
		if box.layout.cross_align == .Stretch {cross_size = cross_available}
		if !axis_allows_overflow(box, !horizontal) && cross_size > cross_available {
			capacity := shrink_capacity(cross_size, cross_spec)
			cross_size -= min(cross_size-cross_available, capacity)
		}
		cross_start := align_cross(0, cross_available, cross_size, box.layout.cross_align)
		if horizontal {
			child.rect = {
				content.x+main_cursor+child.layout.offset.x,
				content.y+cross_start+child.layout.offset.y,
				main_size,
				cross_size,
			}
		} else {
			child.rect = {
				content.x+cross_start+child.layout.offset.x,
				content.y+content.h-main_cursor-main_size+child.layout.offset.y,
				cross_size,
				main_size,
			}
		}
		main_cursor += main_size+box.layout.gap
		arrange_children(frame, child_index)
	}
	if horizontal {
		box.overflow.x = max(f32(0), used-main_available)
	} else {
		box.overflow.y = max(f32(0), used-main_available)
	}
	apply_scroll_layout(frame, index, content)
}
