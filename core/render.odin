package ui

import "core:mem"
import draw "ui_framework:draw"

is_descendant_of :: proc(frame: ^Frame, index, ancestor: int) -> bool {
	for cursor := index; cursor >= 0; cursor = frame.boxes[cursor].parent {
		if cursor == ancestor {return true}
	}
	return false
}

emit_box_layer :: proc(frame: ^Frame, index: int, layer: Layer) {
	box := &frame.boxes[index]
	box.clipped_rect = box.rect
	for parent := box.parent; parent >= 0; parent = frame.boxes[parent].parent {
		ancestor := &frame.boxes[parent]
		if ancestor.style.clip || .Clip in ancestor.flags {
			box.clipped_rect = draw.rect_intersection(box.clipped_rect, ancestor.rect)
		}
	}
	trace_label := box.debug_label
	if len(trace_label) == 0 {trace_label = box.text}
	if box.style.opacity < 1 {draw.push_opacity(&frame.draw_list, box.style.opacity)}
	if box.layer == layer && .Draw_Background in box.flags {
		draw.solid(
			&frame.draw_list,
			box.rect,
			box.style.background,
			box.style.corner_radius,
			0,
			box.style.edge_softness,
			trace_label,
		)
	}
	if box.layer == layer && .Draw_Border in box.flags && box.style.border_thickness > 0 {
		draw.solid(
			&frame.draw_list,
			box.rect,
			box.style.border,
			box.style.corner_radius,
			box.style.border_thickness,
			box.style.edge_softness,
			"border",
		)
	}
	if box.style.clip {draw.push_clip(&frame.draw_list, box.rect)}
	if box.layer == layer && .Draw_Image in box.flags {
		draw.image(&frame.draw_list, box.texture, box.rect, box.texture_src, label = trace_label)
	}
	if box.layer == layer && .Draw_Text in box.flags && frame.text_backend.emit != nil &&
	   box.text_run != Text_Run_ID(0) {
		frame.text_backend.emit(
			frame.text_backend.user_data,
			&frame.draw_list,
			box.text_run,
			box.text,
			box.rect,
			box.style.text_style,
			box.style.text,
		)
	}
	if box.layer == layer && box.custom_draw != nil {
		box.custom_draw(box.custom_data, &frame.draw_list, box.rect)
	}
	if box.layer == layer && .Interactive in box.flags &&
	   (frame.input_root < 0 ||
	    is_descendant_of(frame, index, frame.input_root) ||
	    .Input_Passthrough in box.flags) {
		action := find_action(frame.actions[:], box.control.action)
		enabled := box.control.action == Action_ID(0) || (action != nil && action.enabled)
		if .Disabled in box.flags {enabled = false}
		append(&frame.controls, Control_Record{
			id = box.key,
			functional_name = box.control.functional_name,
			accessibility_label = box.control.accessibility_label,
			accessibility_role = box.control.accessibility_role,
			flash_label = box.control.flash_label,
			flash_anchor = box.control.flash_anchor,
			capabilities = box.control.capabilities,
			action = box.control.action,
			rect = box.rect,
			clip = box.clipped_rect,
			clip_set = box.clipped_rect != box.rect,
			layer = box.layer,
			focusable = .Click_To_Focus in box.flags,
			focus_root = focus_root_for_box(frame, index),
			enabled = enabled,
		})
	}
	for child := box.first_child; child >= 0; child = frame.boxes[child].next_sibling {
		emit_box_layer(frame, child, layer)
	}
	if box.style.clip {draw.pop_clip(&frame.draw_list)}
	if box.style.opacity < 1 {draw.pop_opacity(&frame.draw_list)}
}

layer_label :: proc(layer: Layer) -> string {
	switch layer {
	case .Base: return "layer base"
	case .Popup: return "layer popup"
	case .Tooltip: return "layer tooltip"
	case .Modal: return "layer modal"
	case .Debug: return "layer debug"
	}
	return "layer"
}

emit_layers :: proc(frame: ^Frame) {
	for layer in Layer {
		draw.begin_group(&frame.draw_list, layer_label(layer))
		emit_box_layer(frame, 0, layer)
		draw.end_group(&frame.draw_list, layer_label(layer))
	}
	for &box in frame.boxes {
		state := frame.ui.states[box.key]
		state.last_rect = box.rect
		state.last_seen_frame = frame.ui.frame
		frame.ui.states[box.key] = state
	}
}

scope_actions_to_published_controls :: proc(frame: ^Frame) {
	unpublished_interactive_actions := make(map[Action_ID]bool, frame.allocator)
	defer delete(unpublished_interactive_actions)
	for &box in frame.boxes {
		if .Interactive in box.flags {
			unpublished_interactive_actions[box.control.action] = true
		}
	}
	for &control in frame.controls {
		delete_key(&unpublished_interactive_actions, control.action)
	}
	write_index := 0
	for action in frame.actions {
		if unpublished_interactive_actions[action.id] {
			continue
		}
		frame.actions[write_index] = action
		write_index += 1
	}
	resize(&frame.actions, write_index)
}

purge_old_state :: proc(ui: ^Context, allocator: mem.Allocator) {
	cutoff := u64(0)
	if ui.frame > 120 {cutoff = ui.frame-120}
	remove := make([dynamic]Key, allocator)
	defer delete(remove)
	for key, state in ui.states {if state.last_seen_frame < cutoff {append(&remove, key)}}
	for key in remove {delete_key(&ui.states, key)}
}

end_frame :: proc(frame: ^Frame) -> Frame_Output {
	assert(frame != nil)
	assert(len(frame.parent_stack) == 1, "unclosed UI box")
	layout_measure_standalone(frame, .Horizontal)
	_ = layout_measure_upward(frame, 0, .Horizontal)
	layout_measure_standalone(frame, .Vertical)
	_ = layout_measure_upward(frame, 0, .Vertical)
	frame.boxes[0].rect = frame.input.viewport
	arrange_children(frame, 0)
	prepare_final_text_runs(frame)
	emit_layers(frame)
	process_events(frame)
	scope_actions_to_published_controls(frame)
	update_builtin_animations(
		frame.ui,
		frame.input.delta_seconds,
		frame.allocator,
	)
	purge_old_state(frame.ui, frame.allocator)
	return {
		draw_list = &frame.draw_list,
		actions = frame.actions[:],
		controls = frame.controls[:],
		signals = frame.signals[:],
		events = frame.events[:],
		frame = frame.ui.frame,
	}
}
