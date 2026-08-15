package ui

import "core:mem"
import draw "ui_framework:draw"

is_descendant_of :: proc(frame: ^Frame, index, ancestor: int) -> bool {
	for cursor := index; cursor >= 0; cursor = frame.boxes[cursor].parent {
		if cursor == ancestor {return true}
	}
	return false
}

effective_layer :: proc(box: ^Box) -> Layer {
	if box.surface > 0 && box.layer == .Modal {return .Base}
	return box.layer
}

box_clipped_rect :: proc(frame: ^Frame, index, surface_index: int) -> draw.Rect {
	box := &frame.boxes[index]
	clipped := draw.rect_intersection(box.rect, frame.input.viewport)
	for parent := box.parent; parent >= 0; parent = frame.boxes[parent].parent {
		ancestor := &frame.boxes[parent]
		if ancestor.surface != surface_index {break}
		if ancestor.style.clip || .Clip in ancestor.flags {
			clipped = draw.rect_intersection(clipped, ancestor.rect)
		}
	}
	return clipped
}

emit_child_drop_shadow :: proc(frame: ^Frame, index, surface_index: int, layer: Layer) {
	box := &frame.boxes[index]
	if box.surface != surface_index {return}
	if .Drop_Shadow not_in box.flags || box.custom_draw == nil {return}
	box.clipped_rect = box_clipped_rect(frame, index, surface_index)
	if draw.rect_is_empty(box.clipped_rect) {return}
	if effective_layer(box) != layer {return}
	transformed := box.custom_transform != nil
	if transformed {
		draw.push_transform(
			&frame.draw_list,
			box.custom_transform(box.transform_data, box.rect),
		)
	}
	if box.style.opacity < 1 {draw.push_opacity(&frame.draw_list, box.style.opacity)}
	box.custom_draw(box.custom_data, &frame.draw_list, box.rect)
	if box.style.opacity < 1 {draw.pop_opacity(&frame.draw_list)}
	if transformed {draw.pop_transform(&frame.draw_list)}
}

emit_box_surface_layer :: proc(
	frame: ^Frame,
	index, surface_index: int,
	layer: Layer,
) {
	box := &frame.boxes[index]
	if box.surface != surface_index {return}
	box.clipped_rect = box_clipped_rect(frame, index, surface_index)
	visible := !draw.rect_is_empty(box.clipped_rect)
	if !visible && box.style.clip {return}
	transformed := box.custom_transform != nil
	if transformed {
		draw.push_transform(
			&frame.draw_list,
			box.custom_transform(box.transform_data, box.rect),
		)
	}
	trace_label := box.debug_label
	if len(trace_label) == 0 {trace_label = box.text}
	if box.style.opacity < 1 {draw.push_opacity(&frame.draw_list, box.style.opacity)}
	box_layer := effective_layer(box)
	on_layer := visible && box_layer == layer
	if on_layer && .Draw_Background in box.flags {
		draw.solid(
			&frame.draw_list,
			box.rect,
			box.style.background,
			box.style.corner_radius,
			0,
			box.style.edge_softness,
			trace_label,
			corner_shape = box.style.corner_shape,
		)
	}
	if on_layer && .Draw_Border in box.flags && box.style.border_thickness > 0 {
		draw.solid(
			&frame.draw_list,
			box.rect,
			box.style.border,
			box.style.corner_radius,
			box.style.border_thickness,
			box.style.edge_softness,
			"border",
			corner_shape = box.style.corner_shape,
		)
	}
	if box.style.clip {draw.push_clip(&frame.draw_list, box.rect)}
	if on_layer {
		for child := box.first_child; child >= 0; child = frame.boxes[child].next_sibling {
			emit_child_drop_shadow(frame, child, surface_index, layer)
		}
		if .Draw_Image in box.flags {
			draw.image(&frame.draw_list, box.texture, box.rect, box.texture_src, label = trace_label)
		}
		if .Draw_Text in box.flags && frame.text_backend.emit != nil &&
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
		if box.custom_draw != nil && .Drop_Shadow not_in box.flags {
			box.custom_draw(box.custom_data, &frame.draw_list, box.rect)
		}
		surface := &frame.surfaces[surface_index]
		active_surface := len(frame.surfaces)-1
		input_allowed := surface.input_root < 0 ||
		                 is_descendant_of(frame, index, surface.input_root)
		passthrough := .Input_Passthrough in box.flags
		if .Interactive in box.flags &&
		   ((surface_index == active_surface && input_allowed) || passthrough) {
			action := find_action(frame.actions[:], box.control.action)
			enabled := box.control.action == Action_ID(0) || (action != nil && action.enabled)
			if .Disabled in box.flags {enabled = false}
			control_rect := draw.transform_rect_bounds(draw.top_transform(&frame.draw_list), box.rect)
			control_clip := draw.transform_rect_bounds(
				draw.top_transform(&frame.draw_list),
				box.clipped_rect,
			)
			append(&frame.controls, Control_Record{
				id = box.key,
				functional_name = box.control.functional_name,
				accessibility_label = box.control.accessibility_label,
				accessibility_role = box.control.accessibility_role,
				flash_label = box.control.flash_label,
				flash_anchor = box.control.flash_anchor,
				capabilities = box.control.capabilities,
				action = box.control.action,
				rect = control_rect,
				clip = control_clip,
				clip_set = control_clip != control_rect,
				layer = box_layer,
				focusable = .Click_To_Focus in box.flags,
				focus_root = focus_root_for_box(frame, index),
				surface = surface.key,
				input_passthrough = passthrough,
				enabled = enabled,
			})
		}
	}
	for child := box.first_child; child >= 0; child = frame.boxes[child].next_sibling {
		if .Drop_Shadow in frame.boxes[child].flags {continue}
		emit_box_surface_layer(frame, child, surface_index, layer)
	}
	if box.style.clip {draw.pop_clip(&frame.draw_list)}
	if box.style.opacity < 1 {draw.pop_opacity(&frame.draw_list)}
	if transformed {draw.pop_transform(&frame.draw_list)}
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
	local_layers := [?]Layer{.Base, .Popup, .Tooltip, .Modal}
	for &surface, surface_index in frame.surfaces {
		for layer in local_layers {
			draw.begin_group(&frame.draw_list, layer_label(layer))
			emit_box_surface_layer(frame, surface.root_box, surface_index, layer)
			draw.end_group(&frame.draw_list, layer_label(layer))
		}
	}
	draw.begin_group(&frame.draw_list, layer_label(.Debug))
	for &surface, surface_index in frame.surfaces {
		emit_box_surface_layer(frame, surface.root_box, surface_index, .Debug)
	}
	draw.end_group(&frame.draw_list, layer_label(.Debug))
	for &box in frame.boxes {
		state := frame.ui.states[box.key]
		state.last_rect = box.rect
		state.last_seen_frame = frame.ui.frame
		frame.ui.states[box.key] = state
	}
}

scope_actions_to_published_controls :: proc(frame: ^Frame) {
	unpublished_interactive_actions := make(map[Action_ID]bool, frame.allocator)
	published_actions := make(map[Action_ID]bool, frame.allocator)
	defer delete(unpublished_interactive_actions)
	defer delete(published_actions)
	for &box in frame.boxes {
		if .Interactive in box.flags {
			unpublished_interactive_actions[box.control.action] = true
		}
	}
	for &control in frame.controls {
		delete_key(&unpublished_interactive_actions, control.action)
		published_actions[control.action] = true
	}
	active_surface := len(frame.surfaces)-1
	write_index := 0
	for action, index in frame.actions {
		if unpublished_interactive_actions[action.id] {
			continue
		}
		action_surface := 0
		if index < len(frame.action_surfaces) {action_surface = frame.action_surfaces[index]}
		if action_surface != active_surface && !published_actions[action.id] {continue}
		frame.actions[write_index] = action
		if write_index < len(frame.action_surfaces) {
			frame.action_surfaces[write_index] = action_surface
		}
		write_index += 1
	}
	resize(&frame.actions, write_index)
	if len(frame.action_surfaces) > write_index {resize(&frame.action_surfaces, write_index)}
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
	assert(len(frame.surface_stack) == 1, "unclosed UI surface")
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
	active_surface := &frame.surfaces[len(frame.surfaces)-1]
	return {
		draw_list = &frame.draw_list,
		actions = frame.actions[:],
		controls = frame.controls[:],
		signals = frame.signals[:],
		events = frame.events[:],
		frame = frame.ui.frame,
		active_surface = active_surface.key,
		dismiss_control = active_surface.dismiss_control,
	}
}
