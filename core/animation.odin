package ui

import "core:mem"
import "core:math"
import "core:math/ease"
import "core:math/linalg"

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
	} else if value.timed || value.spring {
		value = {
			current = value.current,
			target = target,
			rate = rate,
			epsilon = epsilon,
			last_seen_frame = ui.frame,
		}
	}
	value.target = target
	value.rate = rate
	value.epsilon = epsilon
	value.timed = false
	value.spring = false
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
	if animating {request_frame(ui, .Animation)}
	return value.current, animating
}

timeline :: proc(
	ui: ^Context,
	key: Key,
	target: f32,
	delta_seconds: f32,
	duration: f32,
	delay: f32 = 0,
	initial: f32 = 0,
) -> (f32, bool) {
	assert(ui != nil)
	used_target := clamp(target, 0, 1)
	used_duration := max(duration, 0)
	used_delay := max(delay, 0)
	value, exists := ui.animations[key]
	if !exists {
		value = {
			current = clamp(initial, 0, 1),
			target = used_target,
			start = clamp(initial, 0, 1),
			delay = used_delay,
			duration = used_duration,
			timed = true,
			last_seen_frame = ui.frame,
		}
	} else if !value.timed || value.spring || value.target != used_target {
		value.start = value.current
		value.target = used_target
		value.elapsed = 0
	}
	value.delay = used_delay
	value.duration = used_duration
	value.timed = true
	value.spring = false
	value.last_seen_frame = ui.frame
	if value.current == value.target {
		ui.animations[key] = value
		return value.current, false
	}
	value.elapsed += max(delta_seconds, 0)
	if value.elapsed > value.delay {
		if value.duration <= 0 {
			value.current = value.target
		} else {
			progress := clamp((value.elapsed-value.delay)/value.duration, 0, 1)
			value.current = linalg.lerp(value.start, value.target, ease.cubic_out(progress))
			if progress >= 1 {value.current = value.target}
		}
	}
	animating := value.current != value.target
	ui.animations[key] = value
	if animating {request_frame(ui, .Animation)}
	return value.current, animating
}

spring_step :: proc(
	current, velocity, target, frequency_hz, damping_ratio, delta_seconds: f32,
) -> (next, next_velocity: f32) {
	if delta_seconds <= 0 {return current, velocity}
	if frequency_hz <= 0 {return target, 0}
	omega := f32(math.TAU)*frequency_hz
	damping := clamp(damping_ratio, 0, 1)
	displacement := current-target
	if damping >= 0.9999 {
		decay := math.exp(-omega*delta_seconds)
		coefficient := velocity+omega*displacement
		next_displacement := (displacement+coefficient*delta_seconds)*decay
		next_velocity = (velocity-omega*coefficient*delta_seconds)*decay
		return target+next_displacement, next_velocity
	}
	damped_omega := omega*math.sqrt(max(f32(0), 1-damping*damping))
	decay := math.exp(-damping*omega*delta_seconds)
	angle := damped_omega*delta_seconds
	cosine := math.cos(angle)
	sine := math.sin(angle)
	next_displacement := decay*(
		displacement*cosine+
		(velocity+damping*omega*displacement)/damped_omega*sine
	)
	next_velocity = decay*(
		velocity*cosine-
		(damping*omega*velocity+omega*omega*displacement)/damped_omega*sine
	)
	return target+next_displacement, next_velocity
}

spring :: proc(
	ui: ^Context,
	key: Key,
	target: f32,
	delta_seconds: f32,
	frequency_hz: f32,
	damping_ratio: f32,
	delay: f32 = 0,
	initial: f32 = 0,
	epsilon: f32 = 0.001,
	velocity_epsilon: f32 = 0.01,
) -> (f32, bool) {
	assert(ui != nil)
	used_delay := max(delay, 0)
	value, exists := ui.animations[key]
	if !exists {
		value = {
			current = initial,
			target = target,
			delay = used_delay,
			epsilon = epsilon,
			velocity_epsilon = velocity_epsilon,
			spring = true,
			last_seen_frame = ui.frame,
		}
	} else if !value.spring || value.target != target {
		if !value.spring {value.velocity = 0}
		value.target = target
		value.elapsed = 0
	}
	value.delay = used_delay
	value.epsilon = epsilon
	value.velocity_epsilon = velocity_epsilon
	value.timed = false
	value.spring = true
	value.last_seen_frame = ui.frame
	value.elapsed += max(delta_seconds, 0)
	if value.elapsed > value.delay {
		value.current, value.velocity = spring_step(
			value.current,
			value.velocity,
			value.target,
			frequency_hz,
			damping_ratio,
			value.elapsed-value.delay if value.elapsed-delta_seconds <= value.delay else delta_seconds,
		)
	}
	if abs(value.current-value.target) <= value.epsilon &&
	   abs(value.velocity) <= value.velocity_epsilon {
		value.current = value.target
		value.velocity = 0
	}
	animating := value.current != value.target || value.velocity != 0
	ui.animations[key] = value
	if animating {request_frame(ui, .Animation)}
	return value.current, animating
}

animation_key :: proc(box: Key, property: string) -> Key {
	return key_combine(box, property)
}

update_builtin_animations :: proc(
	ui: ^Context,
	delta_seconds: f32,
	allocator: mem.Allocator,
) {
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
	remove := make([dynamic]Key, allocator)
	defer delete(remove)
	for key, value in ui.animations {
		if value.last_seen_frame < cutoff {append(&remove, key)}
	}
	for key in remove {delete_key(&ui.animations, key)}
}

is_animating :: proc(ui: ^Context) -> bool {
	if ui == nil {return false}
	for _, value in ui.animations {
		if abs(value.current-value.target) > value.epsilon ||
		   (value.spring && abs(value.velocity) > value.velocity_epsilon) {
			return true
		}
	}
	return false
}
