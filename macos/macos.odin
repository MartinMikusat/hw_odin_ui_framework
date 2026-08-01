package macos

import "core:mem"
import "core:strings"
import ui "ui_framework:core"
import draw "ui_framework:draw"

Pointer_Event_Kind :: enum {
	Primary_Press,
	Secondary_Press,
	Drag,
	Scroll,
}

Numbered_State :: struct {
	first:       i8,
	deadline_ms: i64,
}

queue_pointer_event :: proc(
	ctx: ^ui.Context,
	kind: ui.Event_Kind,
	point: ui.Vec2,
	button := ui.Pointer_Button.Primary,
	delta: ui.Vec2 = {},
	modifiers: ui.Modifiers = {},
	timestamp_us: u64 = 0,
) {
	ui.queue_event(ctx, {
		kind = kind,
		button = button,
		point = point,
		delta = delta,
		modifiers = modifiers,
		timestamp_us = timestamp_us,
	})
}

queue_key_event :: proc(
	ctx: ^ui.Context,
	kind: ui.Event_Kind,
	key: u32,
	modifiers: ui.Modifiers = {},
	timestamp_us: u64 = 0,
) {
	ui.queue_event(ctx, {
		kind = kind,
		key = key,
		modifiers = modifiers,
		timestamp_us = timestamp_us,
	})
}

consume_numbered_digit :: proc(
	state: ^Numbered_State,
	ctx: ^ui.Context,
	digit: i8,
	now_ms: i64,
	timeout_ms: i64 = 1_000,
) -> (ui.Activation, bool, bool) {
	assert(state != nil)
	if state.first != 0 && now_ms > state.deadline_ms {state^ = {}}
	if state.first == 0 {
		for &action in ctx.published.actions {
			if action.enabled && action.number_code.digits == 2 && action.number_code.first == digit {
				state.first = digit
				state.deadline_ms = now_ms+timeout_ms
				return {}, false, true
			}
			if action.enabled && action.number_code.digits == 1 && action.number_code.first == digit {
				activation, activated := ui.activate_action(ctx, action.id, .Numbered)
				return activation, activated, activated
			}
		}
		return {}, false, false
	}
	first := state.first
	state^ = {}
	activation, activated := numbered_activation(ctx, first, digit, 2)
	return activation, activated, true
}

Accessibility_Element :: struct {
	control_id: ui.Key,
	label:      string,
	role:       string,
	frame:      draw.Rect,
	enabled:    bool,
	action:     ui.Action_ID,
}

Flash_Target :: struct {
	control_id: ui.Key,
	label:      string,
	rect:       draw.Rect,
	anchor:     ui.Flash_Anchor,
}

role_name :: proc(role: ui.Accessibility_Role) -> string {
	switch role {
	case .Button: return "AXButton"
	case .Text_Field: return "AXTextField"
	case .Check_Box: return "AXCheckBox"
	case .Radio_Button: return "AXRadioButton"
	case .Slider: return "AXSlider"
	case .List: return "AXList"
	case .List_Item: return "AXRow"
	case .Group: return "AXGroup"
	case .None: return "AXUnknown"
	}
	return "AXUnknown"
}

pointer_capability :: proc(kind: Pointer_Event_Kind) -> ui.Control_Capability {
	switch kind {
	case .Primary_Press: return .Primary_Press
	case .Secondary_Press: return .Secondary_Press
	case .Drag: return .Drag
	case .Scroll: return .Scroll
	}
	return .Primary_Press
}

pointer_activation :: proc(
	ctx: ^ui.Context,
	kind: Pointer_Event_Kind,
	point: ui.Vec2,
) -> (ui.Activation, bool) {
	capability := pointer_capability(kind)
	control := ui.hit_test(ctx, point, capability)
	if control == nil {return {}, false}
	activation, ok := ui.activate_control(ctx, control.id, .Pointer, point)
	if !ok {return {}, false}
	return activation, true
}

numbered_activation :: proc(ctx: ^ui.Context, first, second, digits: i8) -> (ui.Activation, bool) {
	for &action in ctx.published.actions {
		if !action.enabled || action.number_code.digits != digits ||
		   action.number_code.first != first || action.number_code.second != second {
			continue
		}
		return ui.activate_action(ctx, action.id, .Numbered)
	}
	return {}, false
}

functional_activation :: proc(
	ctx: ^ui.Context,
	functional_name: string,
	source := ui.Activation_Source.CLI,
) -> (ui.Activation, bool) {
	for &control in ctx.published.controls {
		if control.functional_name != functional_name {continue}
		return ui.activate_control(ctx, control.id, source)
	}
	for &action in ctx.published.actions {
		if action.functional_name == functional_name {
			return ui.activate_action(ctx, action.id, source)
		}
	}
	return {}, false
}

accessibility_elements :: proc(
	ctx: ^ui.Context,
	allocator := context.allocator,
) -> []Accessibility_Element {
	count := 0
	for &control in ctx.published.controls {
		if .Accessibility in control.capabilities {count += 1}
	}
	result := make([]Accessibility_Element, count, allocator)
	next := 0
	for &control in ctx.published.controls {
		if .Accessibility not_in control.capabilities {continue}
		result[next] = {
			control_id = control.id,
			label = strings.clone(control.accessibility_label, allocator),
			role = role_name(control.accessibility_role),
			frame = control.rect,
			enabled = control.enabled,
			action = control.action,
		}
		next += 1
	}
	return result
}

accessibility_elements_destroy :: proc(elements: []Accessibility_Element, allocator := context.allocator) {
	for &element in elements {delete(element.label, allocator)}
	delete(elements, allocator)
}

flash_targets :: proc(ctx: ^ui.Context, allocator := context.allocator) -> []Flash_Target {
	count := 0
	for &control in ctx.published.controls {
		if control.enabled && .Flash in control.capabilities {count += 1}
	}
	result := make([]Flash_Target, count, allocator)
	next := 0
	for &control in ctx.published.controls {
		if !control.enabled || .Flash not_in control.capabilities {continue}
		result[next] = {
			control_id = control.id,
			label = strings.clone(control.flash_label, allocator),
			rect = control.rect,
			anchor = control.flash_anchor,
		}
		next += 1
	}
	return result
}

flash_targets_destroy :: proc(targets: []Flash_Target, allocator := context.allocator) {
	for &target in targets {delete(target.label, allocator)}
	delete(targets, allocator)
}
