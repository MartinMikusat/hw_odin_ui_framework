package ui

animation_step :: proc(current, target, rate, delta_seconds, epsilon: f32) -> (f32, bool) {
	if abs(target-current) <= epsilon {return target, false}
	if delta_seconds <= 0 || rate <= 0 {return current, true}
	factor := min(f32(1), rate*delta_seconds/(1+rate*delta_seconds))
	next := current+(target-current)*factor
	if abs(target-next) <= epsilon {return target, false}
	return next, true
}

animate :: proc(
	ui: ^Context,
	key: Key,
	target: f32,
	delta_seconds: f32,
	initial: f32 = 0,
	rate: f32 = 18,
	epsilon: f32 = 0.001,
) -> (f32, bool) {
	assert(ui != nil)
	value, exists := ui.animations[key]
	if !exists {
		value = {
			current = initial,
			target = target,
			rate = rate,
			epsilon = epsilon,
			last_seen_frame = ui.frame,
		}
	}
	value.target = target
	value.rate = rate
	value.epsilon = epsilon
	value.last_seen_frame = ui.frame
	animating: bool
	value.current, animating = animation_step(
		value.current,
		value.target,
		value.rate,
		delta_seconds,
		value.epsilon,
	)
	ui.animations[key] = value
	return value.current, animating
}

animation_key :: proc(box: Key, property: string) -> Key {
	return key_combine(box, property)
}

update_builtin_animations :: proc(ui: ^Context, delta_seconds: f32) {
	for key, state_value in ui.states {
		state := state_value
		state.hot_t, _ = animate(
			ui,
			animation_key(key, "hot"),
			state.hot ? 1 : 0,
			delta_seconds,
			state.hot_t,
		)
		state.active_t, _ = animate(
			ui,
			animation_key(key, "active"),
			state.active ? 1 : 0,
			delta_seconds,
			state.active_t,
		)
		state.focus_t, _ = animate(
			ui,
			animation_key(key, "focus"),
			state.focused ? 1 : 0,
			delta_seconds,
			state.focus_t,
		)
		state.disabled_t, _ = animate(
			ui,
			animation_key(key, "disabled"),
			state.disabled ? 1 : 0,
			delta_seconds,
			state.disabled_t,
		)
		ui.states[key] = state
	}

	cutoff := u64(0)
	if ui.frame > 240 {cutoff = ui.frame-240}
	remove := make([dynamic]Key, context.temp_allocator)
	defer delete(remove)
	for key, value in ui.animations {
		if value.last_seen_frame < cutoff {append(&remove, key)}
	}
	for key in remove {delete_key(&ui.animations, key)}
}

is_animating :: proc(ui: ^Context) -> bool {
	if ui == nil {return false}
	for _, value in ui.animations {
		if abs(value.current-value.target) > value.epsilon {return true}
	}
	return false
}
