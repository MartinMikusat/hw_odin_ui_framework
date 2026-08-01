package ui

import "core:strings"
import "core:mem"

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

hit_test_records :: proc(
	controls: []Control_Record,
	point: Vec2,
	capability := Control_Capability.Primary_Press,
) -> ^Control_Record {
	best: ^Control_Record
	best_layer := Layer.Base
	for index := len(controls)-1; index >= 0; index -= 1 {
		control := &controls[index]
		if !control.enabled || capability not_in control.capabilities ||
		   !control_contains(control, point) {continue}
		if best == nil || control.layer > best_layer {
			best = control
			best_layer = control.layer
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
) {
	assert(ui != nil)
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
}

registry_publish :: proc(ui: ^Context, registry: ^Registry_Builder) {
	assert(registry != nil)
	publish_records(ui, registry.actions[:], registry.controls[:], registry.frame)
}

control_by_name :: proc(ui: ^Context, functional_name: string) -> ^Control_Record {
	if ui == nil {return nil}
	for &control in ui.published.controls {
		if control.functional_name == functional_name {return &control}
	}
	return nil
}

control_by_key :: proc(ui: ^Context, key: Key) -> ^Control_Record {
	if ui == nil {return nil}
	for &control in ui.published.controls {if control.id == key {return &control}}
	return nil
}
