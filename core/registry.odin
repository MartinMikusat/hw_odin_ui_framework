package ui

import "core:strings"
import "core:mem"
import draw "ui_framework:draw"

Registry_Builder :: struct {
	allocator:    mem.Allocator,
	actions:      [dynamic]Action_Record,
	controls:     [dynamic]Control_Record,
	seen_actions: map[Action_ID]bool,
	seen_controls: map[Key]bool,
	frame:        u64,
}

Registry_View :: struct {
	actions:  []Action_Record,
	controls: []Control_Record,
	frame:    u64,
}

Registry_Issue_Kind :: enum {
	Zero_Action_ID,
	Zero_Control_ID,
	Duplicate_Action_ID,
	Duplicate_Control_ID,
	Duplicate_Functional_Name,
	Missing_Action,
	Invalid_Rect,
	Invalid_Number_Code,
	Missing_Accessibility_Label,
	Missing_Flash_Label,
}

Registry_Issue :: struct {
	kind: Registry_Issue_Kind,
	id:   Key,
	name: string,
}

registry_begin :: proc(frame: u64, allocator := context.allocator) -> Registry_Builder {
	result := Registry_Builder{allocator = allocator, frame = frame}
	result.actions = make([dynamic]Action_Record, allocator)
	result.controls = make([dynamic]Control_Record, allocator)
	result.seen_actions = make(map[Action_ID]bool, allocator)
	result.seen_controls = make(map[Key]bool, allocator)
	return result
}

registry_destroy :: proc(registry: ^Registry_Builder) {
	if registry == nil {return}
	delete(registry.actions)
	delete(registry.controls)
	delete(registry.seen_actions)
	delete(registry.seen_controls)
	registry^ = {}
}

registry_reset :: proc(registry: ^Registry_Builder, frame: u64) {
	assert(registry != nil)
	clear(&registry.actions)
	clear(&registry.controls)
	clear(&registry.seen_actions)
	clear(&registry.seen_controls)
	registry.frame = frame
}

registry_view :: proc(registry: ^Registry_Builder) -> Registry_View {
	if registry == nil {return {}}
	return {registry.actions[:], registry.controls[:], registry.frame}
}

registry_view_from_records :: proc(
	actions: []Action_Record,
	controls: []Control_Record,
	frame: u64,
) -> Registry_View {
	return {actions, controls, frame}
}

registry_validate :: proc(
	registry: Registry_View,
	allocator := context.allocator,
) -> []Registry_Issue {
	issues := make([dynamic]Registry_Issue, allocator)
	for action, index in registry.actions {
		if action.id == Action_ID(0) {
			append(&issues, Registry_Issue{
				kind = .Zero_Action_ID,
				name = action.functional_name,
			})
		}
		code := action.number_code
		if code.digits < 0 || code.digits > 2 ||
		   (code.digits > 0 && (code.first < 1 || code.first > 9)) ||
		   (code.digits == 2 && (code.second < 1 || code.second > 9)) {
			append(&issues, Registry_Issue{
				kind = .Invalid_Number_Code,
				name = action.functional_name,
			})
		}
		for other in index+1..<len(registry.actions) {
			if action.id == registry.actions[other].id {
				append(&issues, Registry_Issue{
					.Duplicate_Action_ID,
					Key(action.id),
					action.functional_name,
				})
			}
		}
	}
	for control, index in registry.controls {
		if control.id == Key(0) {
			append(&issues, Registry_Issue{
				kind = .Zero_Control_ID,
				name = control.functional_name,
			})
		}
		if draw.rect_is_empty(control.rect) {
			append(&issues, Registry_Issue{
				.Invalid_Rect,
				control.id,
				control.functional_name,
			})
		}
		if control.action != Action_ID(0) &&
		   find_action(registry.actions, control.action) == nil {
			append(&issues, Registry_Issue{
				.Missing_Action,
				control.id,
				control.functional_name,
			})
		}
		if .Accessibility in control.capabilities &&
		   len(control.accessibility_label) == 0 {
			append(&issues, Registry_Issue{
				.Missing_Accessibility_Label,
				control.id,
				control.functional_name,
			})
		}
		if .Flash in control.capabilities && len(control.flash_label) == 0 {
			append(&issues, Registry_Issue{
				.Missing_Flash_Label,
				control.id,
				control.functional_name,
			})
		}
		for other in index+1..<len(registry.controls) {
			next := registry.controls[other]
			if control.id == next.id {
				append(&issues, Registry_Issue{
					.Duplicate_Control_ID,
					control.id,
					control.functional_name,
				})
			}
			if len(control.functional_name) > 0 &&
			   control.functional_name == next.functional_name {
				append(&issues, Registry_Issue{
					.Duplicate_Functional_Name,
					control.id,
					control.functional_name,
				})
			}
		}
	}
	return issues[:]
}

registry_assert_valid :: proc(
	registry: Registry_View,
	allocator := context.allocator,
) {
	when ODIN_DEBUG {
		issues := registry_validate(registry, allocator)
		defer delete(issues, allocator)
		assert(len(issues) == 0, "published control registry is invalid")
	}
}

hit_test_records :: proc(
	controls: []Control_Record,
	point: Vec2,
	capability := Control_Capability.Primary_Press,
) -> ^Control_Record {
	best: ^Control_Record
	for index := len(controls)-1; index >= 0; index -= 1 {
		control := &controls[index]
		if !control.enabled || capability not_in control.capabilities ||
		   !control_contains(control, point) {continue}
		if control_has_hit_priority(control, best) {
			best = control
		}
	}
	return best
}

hit_test_view :: proc(
	registry: Registry_View,
	point: Vec2,
	capability := Control_Capability.Primary_Press,
) -> ^Control_Record {
	return hit_test_records(registry.controls, point, capability)
}

action_in_view :: proc(registry: Registry_View, id: Action_ID) -> ^Action_Record {
	return find_action(registry.actions, id)
}

control_in_view :: proc(registry: Registry_View, id: Key) -> ^Control_Record {
	for &control in registry.controls {if control.id == id {return &control}}
	return nil
}

activate_control_with_capability_in_view :: proc(
	registry: Registry_View,
	control_id: Key,
	source: Activation_Source,
	capability: Control_Capability,
	point: Vec2 = {},
) -> (Activation, bool) {
	control := control_in_view(registry, control_id)
	if control == nil || !control.enabled || capability not_in control.capabilities {
		return {}, false
	}
	normalized: Vec2
	if control.rect.w > 0 {normalized.x = (point.x-control.rect.x)/control.rect.w}
	if control.rect.h > 0 {normalized.y = (point.y-control.rect.y)/control.rect.h}
	return {
		action = control.action,
		control = control.id,
		source = source,
		point = point,
		normalized = normalized,
	}, true
}

activate_control_in_view :: proc(
	registry: Registry_View,
	control_id: Key,
	source: Activation_Source,
	point: Vec2 = {},
) -> (Activation, bool) {
	return activate_control_with_capability_in_view(
		registry,
		control_id,
		source,
		capability_for_source(source),
		point,
	)
}

activate_action_in_view :: proc(
	registry: Registry_View,
	action_id: Action_ID,
	source: Activation_Source,
) -> (Activation, bool) {
	action := action_in_view(registry, action_id)
	if action == nil || !action.enabled {return {}, false}
	return {action = action_id, source = source}, true
}

activate_at_point_in_view :: proc(
	registry: Registry_View,
	point: Vec2,
	capability := Control_Capability.Primary_Press,
) -> (Activation, bool) {
	control := hit_test_view(registry, point, capability)
	if control == nil {return {}, false}
	return activate_control_with_capability_in_view(
		registry,
		control.id,
		.Pointer,
		capability,
		point,
	)
}

registry_add_action :: proc(registry: ^Registry_Builder, action: Action_Record) {
	assert(registry != nil && action.id != Action_ID(0))
	assert(!registry.seen_actions[action.id], "duplicate action identifier")
	registry.seen_actions[action.id] = true
	append(&registry.actions, action)
}

registry_add_control :: proc(registry: ^Registry_Builder, control: Control_Record) {
	assert(registry != nil && control.id != Key(0))
	assert(!registry.seen_controls[control.id], "duplicate control identifier")
	registry.seen_controls[control.id] = true
	append(&registry.controls, control)
}

publish_records :: proc(
	ui: ^Context,
	actions: []Action_Record,
	controls: []Control_Record,
	frame: u64,
	active_surface: Key = Key(0),
	dismiss_control: Key = Key(0),
) {
	assert(ui != nil)
	previous_surface := ui.published.active_surface
	previous_focus := ui.focused
	if previous_surface != Key(0) && previous_surface != active_surface {
		ui.surface_focus[previous_surface] = previous_focus
	}
	clear_published(ui)
	for action in actions {
		copy := action
		copy.functional_name = strings.clone(action.functional_name, ui.allocator)
		copy.label = strings.clone(action.label, ui.allocator)
		copy.unavailable_reason = strings.clone(action.unavailable_reason, ui.allocator)
		append(&ui.published.actions, copy)
	}
	for control in controls {
		copy := control
		copy.functional_name = strings.clone(control.functional_name, ui.allocator)
		copy.accessibility_label = strings.clone(control.accessibility_label, ui.allocator)
		copy.flash_label = strings.clone(control.flash_label, ui.allocator)
		append(&ui.published.controls, copy)
	}
	ui.published.frame = frame
	ui.published.active_surface = active_surface
	ui.published.dismiss_control = dismiss_control
	ui.active_surface = active_surface
	if active_surface == Key(0) {return}

	focus_is_valid := false
	for &control in ui.published.controls {
		if control.id == ui.focused && control.surface == active_surface &&
		   control.enabled && control.focusable {
			focus_is_valid = true
			break
		}
	}
	if previous_surface == active_surface {
		if previous_focus != Key(0) && !focus_is_valid {ui.focused = Key(0)}
		if ui.focused != previous_focus {request_frame(ui, .State)}
		return
	}

	if previous_surface != active_surface {
		next_focus := Key(0)
		saved, has_saved := ui.surface_focus[active_surface]
		restored := has_saved && saved == Key(0)
		if has_saved && saved != Key(0) {
			for &control in ui.published.controls {
				if control.id == saved && control.surface == active_surface &&
				   control.enabled && control.focusable {
					next_focus = saved
					restored = true
					break
				}
			}
		}
		if !restored && previous_surface != Key(0) {
			for &control in ui.published.controls {
				if control.surface == active_surface && control.enabled && control.focusable {
					next_focus = control.id
					break
				}
			}
		}
		ui.focused = next_focus
	}
	if ui.focused != previous_focus {request_frame(ui, .State)}
}

registry_publish :: proc(ui: ^Context, registry: ^Registry_Builder) {
	assert(registry != nil)
	publish_records(ui, registry.actions[:], registry.controls[:], registry.frame)
}

control_by_name :: proc(ui: ^Context, functional_name: string) -> ^Control_Record {
	if ui == nil {return nil}
	return control_by_name_in_view(
		registry_view_from_records(
			ui.published.actions[:],
			ui.published.controls[:],
			ui.published.frame,
		),
		functional_name,
	)
}

control_by_name_in_view :: proc(
	registry: Registry_View,
	functional_name: string,
) -> ^Control_Record {
	for &control in registry.controls {
		if control.functional_name == functional_name {return &control}
	}
	return nil
}

control_by_key :: proc(ui: ^Context, key: Key) -> ^Control_Record {
	if ui == nil {return nil}
	for &control in ui.published.controls {if control.id == key {return &control}}
	return nil
}
