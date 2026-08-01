package ui

import "core:strings"

queue_event :: proc(ui: ^Context, event: Event) {
	assert(ui != nil)
	copy := event
	copy.text = strings.clone(event.text, ui.allocator)
	copy.consumed = false
	append(&ui.events, copy)
}

clear_events :: proc(ui: ^Context) {
	if ui == nil {return}
	for &event in ui.events {delete(event.text, ui.allocator)}
	clear(&ui.events)
}

button_index :: proc(button: Pointer_Button) -> int {
	return int(button)
}

control_contains :: proc(control: ^Control_Record, point: Vec2) -> bool {
	if control == nil || !contains(control.rect, point) {return false}
	return !control.clip_set || contains(control.clip, point)
}

frame_control :: proc(frame: ^Frame, key: Key) -> ^Control_Record {
	for &control in frame.controls {
		if control.id == key {return &control}
	}
	return nil
}

frame_hit_test :: proc(
	frame: ^Frame,
	point: Vec2,
	capability: Control_Capability,
) -> ^Control_Record {
	best: ^Control_Record
	best_layer := Layer.Base
	for index := len(frame.controls)-1; index >= 0; index -= 1 {
		control := &frame.controls[index]
		if !control.enabled || capability not_in control.capabilities ||
		   !control_contains(control, point) {
			continue
		}
		if best == nil || control.layer > best_layer {
			best = control
			best_layer = control.layer
		}
	}
	return best
}

frame_hover_test :: proc(frame: ^Frame, point: Vec2) -> ^Control_Record {
	best: ^Control_Record
	best_layer := Layer.Base
	for index := len(frame.controls)-1; index >= 0; index -= 1 {
		control := &frame.controls[index]
		interactive := .Hover in control.capabilities ||
		               .Primary_Press in control.capabilities ||
		               .Secondary_Press in control.capabilities ||
		               .Drag in control.capabilities ||
		               .Scroll in control.capabilities
		if !control.enabled || !interactive || !control_contains(control, point) {
			continue
		}
		if best == nil || control.layer > best_layer {
			best = control
			best_layer = control.layer
		}
	}
	return best
}

signal_add :: proc(frame: ^Frame, value: Signal) {
	for &signal in frame.signals {
		if signal.control != value.control {continue}
		signal.flags += value.flags
		if value.point.x != 0 || value.point.y != 0 {signal.point = value.point}
		signal.delta.x += value.delta.x
		signal.delta.y += value.delta.y
		signal.button = value.button
		signal.modifiers += value.modifiers
		return
	}
	append(&frame.signals, value)
}

signal_for_key :: proc(signals: []Signal, key: Key) -> Signal {
	for signal in signals {if signal.control == key {return signal}}
	return {}
}

signal_for_action :: proc(signals: []Signal, action: Action_ID) -> Signal {
	for signal in signals {if signal.action == action {return signal}}
	return {}
}

shift_press_history :: proc(ui: ^Context, button: int, key: Key, point: Vec2, timestamp_us: u64) {
	for index := 2; index > 0; index -= 1 {
		ui.press_keys[button][index] = ui.press_keys[button][index-1]
		ui.press_times_us[button][index] = ui.press_times_us[button][index-1]
		ui.press_points[button][index] = ui.press_points[button][index-1]
	}
	ui.press_keys[button][0] = key
	ui.press_times_us[button][0] = timestamp_us
	ui.press_points[button][0] = point
}

distance_squared :: proc(a, b: Vec2) -> f32 {
	dx := a.x-b.x
	dy := a.y-b.y
	return dx*dx+dy*dy
}

click_count_flags :: proc(
	ui: ^Context,
	button: int,
	key: Key,
	point: Vec2,
	timestamp_us: u64,
) -> Signal_Flags {
	result := Signal_Flags{.Pressed}
	double_interval_us :: u64(500_000)
	travel_limit_squared :: f32(100)
	if ui.press_keys[button][0] == key &&
	   timestamp_us >= ui.press_times_us[button][0] &&
	   timestamp_us-ui.press_times_us[button][0] <= double_interval_us &&
	   distance_squared(point, ui.press_points[button][0]) <= travel_limit_squared {
		result += {.Double_Clicked}
		if ui.press_keys[button][1] == key &&
		   ui.press_times_us[button][0] >= ui.press_times_us[button][1] &&
		   ui.press_times_us[button][0]-ui.press_times_us[button][1] <= double_interval_us &&
		   distance_squared(ui.press_points[button][0], ui.press_points[button][1]) <= travel_limit_squared {
			result += {.Triple_Clicked}
		}
	}
	return result
}

set_control_state :: proc(
	ui: ^Context,
	key: Key,
	hot, active, focused, disabled: bool,
) {
	if key == Key(0) {return}
	state := ui.states[key]
	state.hot = hot
	state.active = active
	state.focused = focused
	state.disabled = disabled
	state.last_seen_frame = ui.frame
	ui.states[key] = state
}

process_events :: proc(frame: ^Frame) {
	assert(frame != nil)
	ui := frame.ui
	for key, state_value in ui.states {
		state := state_value
		state.hot = false
		state.active = false
		state.focused = key == ui.focused
		ui.states[key] = state
	}

	for &event in frame.events {
		if event.consumed {continue}
		switch event.kind {
		case .Pointer_Move:
			for button in 0..<len(ui.active) {
				key := ui.active[button]
				control := frame_control(frame, key)
				if control == nil {continue}
				signal_add(frame, {
					control = key,
					action = control.action,
					flags = {.Dragging},
					button = Pointer_Button(button),
					point = event.point,
					delta = event.delta,
					modifiers = event.modifiers,
				})
			}
		case .Pointer_Press:
			capability := Control_Capability.Primary_Press
			if event.button == .Secondary {capability = .Secondary_Press}
			control := frame_hit_test(frame, event.point, capability)
			if control == nil {continue}
			button := button_index(event.button)
			flags := click_count_flags(ui, button, control.id, event.point, event.timestamp_us)
			ui.hot = control.id
			ui.active[button] = control.id
			ui.drag_start = event.point
			if control.focusable {ui.focused = control.id}
			signal_add(frame, {
				control = control.id,
				action = control.action,
				flags = flags,
				button = event.button,
				point = event.point,
				modifiers = event.modifiers,
			})
			shift_press_history(ui, button, control.id, event.point, event.timestamp_us)
			event.consumed = true
		case .Pointer_Release:
			button := button_index(event.button)
			key := ui.active[button]
			control := frame_control(frame, key)
			if control == nil {ui.active[button] = Key(0); continue}
			flags := Signal_Flags{.Released}
			if control_contains(control, event.point) {flags += {.Clicked}}
			signal_add(frame, {
				control = key,
				action = control.action,
				flags = flags,
				button = event.button,
				point = event.point,
				modifiers = event.modifiers,
			})
			ui.active[button] = Key(0)
			event.consumed = true
		case .Scroll:
			control := frame_hit_test(frame, event.point, .Scroll)
			if control == nil {continue}
			signal_add(frame, {
				control = control.id,
				action = control.action,
				flags = {.Scrolled},
				point = event.point,
				delta = event.delta,
				modifiers = event.modifiers,
			})
			state := ui.states[control.id]
			state.scroll_target.x += event.delta.x
			state.scroll_target.y += event.delta.y
			ui.states[control.id] = state
			event.consumed = true
		case .Key_Press:
			control := frame_control(frame, ui.focused)
			if control == nil || .Direct_Keyboard not_in control.capabilities {continue}
			signal_add(frame, {
				control = control.id,
				action = control.action,
				flags = {.Keyboard_Pressed, .Focused},
				modifiers = event.modifiers,
			})
			event.consumed = true
		case .Key_Release, .Text, .File_Drop:
		}
	}

	hovered := frame_hover_test(frame, frame.input.pointer)
	ui.hot = Key(0)
	if hovered != nil {
		ui.hot = hovered.id
		signal_add(frame, {
			control = hovered.id,
			action = hovered.action,
			flags = {.Hovering, .Mouse_Over},
			point = frame.input.pointer,
		})
	}
	for &control in frame.controls {
		active := false
		for key in ui.active {if key == control.id {active = true; break}}
		set_control_state(
			ui,
			control.id,
			control.id == ui.hot,
			active,
			control.id == ui.focused,
			!control.enabled,
		)
	}
}
