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
