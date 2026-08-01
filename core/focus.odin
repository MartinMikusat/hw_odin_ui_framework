package ui

import "core:mem"

Navigation_Direction :: enum {
	Previous,
	Next,
	Left,
	Right,
	Up,
	Down,
}

focus_root_for_box :: proc(frame: ^Frame, index: int) -> Key {
	for cursor := index; cursor >= 0; cursor = frame.boxes[cursor].parent {
		box := &frame.boxes[cursor]
		if .Focus_Root in box.flags {return box.key}
	}
	return frame.boxes[0].key
}

focus_set :: proc(ui: ^Context, key: Key) -> bool {
	if ui == nil {return false}
	for &control in ui.published.controls {
		if control.id != key || !control.enabled || !control.focusable {continue}
		ui.focused = key
		return true
	}
	return false
}

focus_clear :: proc(ui: ^Context) {
	if ui == nil {return}
	ui.focused = Key(0)
}

control_center :: proc(control: ^Control_Record) -> Vec2 {
	return {control.rect.x+control.rect.w/2, control.rect.y+control.rect.h/2}
}

direction_score :: proc(origin, candidate: Vec2, direction: Navigation_Direction) -> (f32, bool) {
	dx := candidate.x-origin.x
	dy := candidate.y-origin.y
	primary, secondary: f32
	switch direction {
	case .Left: primary, secondary = -dx, abs(dy)
	case .Right: primary, secondary = dx, abs(dy)
	case .Up: primary, secondary = dy, abs(dx)
	case .Down: primary, secondary = -dy, abs(dx)
	case .Previous, .Next: return 0, false
	}
	if primary <= 0 {return 0, false}
	return primary+secondary*2, true
}

focus_move :: proc(
	ui: ^Context,
	direction: Navigation_Direction,
	root: Key = Key(0),
	allocator: mem.Allocator = {},
) -> (Key, bool) {
	if ui == nil {return Key(0), false}
	use_allocator := allocator
	if use_allocator.procedure == nil {use_allocator = ui.allocator}
	candidates := make([dynamic]^Control_Record, use_allocator)
	defer delete(candidates)
	for &control in ui.published.controls {
		if !control.enabled || !control.focusable {continue}
		if root != Key(0) && control.focus_root != root {continue}
		append(&candidates, &control)
	}
	if len(candidates) == 0 {return Key(0), false}
	current_index := -1
	for candidate, index in candidates {
		if candidate.id == ui.focused {current_index = index; break}
	}
	if direction == .Previous || direction == .Next {
		next := 0
		if current_index >= 0 {
			delta := 1 if direction == .Next else -1
			next = (current_index+delta+len(candidates))%len(candidates)
		}
		ui.focused = candidates[next].id
		return ui.focused, true
	}
	if current_index < 0 {
		ui.focused = candidates[0].id
		return ui.focused, true
	}
	origin := control_center(candidates[current_index])
	best := -1
	best_score := f32(3.4028235e38)
	for candidate, index in candidates {
		if index == current_index {continue}
		score, valid := direction_score(origin, control_center(candidate), direction)
		if valid && score < best_score {best, best_score = index, score}
	}
	if best < 0 {return ui.focused, false}
	ui.focused = candidates[best].id
	return ui.focused, true
}
