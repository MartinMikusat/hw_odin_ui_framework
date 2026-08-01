package ui

import draw "ui_framework:draw"

scroll_limits :: proc(ui: ^Context, key: Key) -> Vec2 {
	if ui == nil || key == Key(0) {return {}}
	state := ui.states[key]
	return {
		max(f32(0), state.view_bounds.x-state.last_rect.w),
		max(f32(0), state.view_bounds.y-state.last_rect.h),
	}
}

scroll_set_target :: proc(ui: ^Context, key: Key, target: Vec2) -> Vec2 {
	if ui == nil || key == Key(0) {return {}}
	state := ui.states[key]
	limits := scroll_limits(ui, key)
	state.scroll_target = {
		min(max(target.x, 0), limits.x),
		min(max(target.y, 0), limits.y),
	}
	state.last_seen_frame = ui.frame
	ui.states[key] = state
	return state.scroll_target
}

scroll_by :: proc(ui: ^Context, key: Key, delta: Vec2) -> Vec2 {
	if ui == nil || key == Key(0) {return {}}
	state := ui.states[key]
	return scroll_set_target(ui, key, {
		state.scroll_target.x+delta.x,
		state.scroll_target.y+delta.y,
	})
}

scroll_make_visible :: proc(
	ui: ^Context,
	key: Key,
	item: draw.Rect,
	margin: f32 = 0,
) -> Vec2 {
	if ui == nil || key == Key(0) {return {}}
	state := ui.states[key]
	viewport := state.last_rect
	target := state.scroll_target
	left := viewport.x+margin
	right := viewport.x+viewport.w-margin
	bottom := viewport.y+margin
	top := viewport.y+viewport.h-margin
	if item.x < left {
		target.x += item.x-left
	} else if item.x+item.w > right {
		target.x += item.x+item.w-right
	}
	if item.y < bottom {
		target.y += bottom-item.y
	} else if item.y+item.h > top {
		target.y -= item.y+item.h-top
	}
	return scroll_set_target(ui, key, target)
}
