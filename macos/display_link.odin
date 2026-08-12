package macos

import "core:math"

Display_Link :: struct {
	native: rawptr,
	paused: bool,
}

Frame_Rate_Range :: struct {
	minimum:   f32,
	maximum:   f32,
	preferred: f32,
}

display_link_rate_range :: proc(
	minimum: f32 = 30,
	maximum: f32 = 120,
	preferred: f32 = 120,
) -> (Frame_Rate_Range, bool) {
	if minimum <= 0 || maximum < minimum || preferred < minimum || preferred > maximum ||
	   math.is_nan(minimum) || math.is_nan(maximum) || math.is_nan(preferred) ||
	   math.is_inf(minimum) || math.is_inf(maximum) || math.is_inf(preferred) {
		return {}, false
	}
	return {minimum, maximum, preferred}, true
}

display_link_msg_id_id_sel :: proc(receiver, selector, target, callback: rawptr) -> rawptr {
	send := transmute(proc "c" (_: rawptr, _: rawptr, _: rawptr, _: rawptr) -> rawptr)frame_timer_send_address
	return send(receiver, selector, target, callback)
}

display_link_msg_void_bool :: proc(receiver, selector: rawptr, value: bool) {
	send := transmute(proc "c" (_: rawptr, _: rawptr, _: bool))frame_timer_send_address
	send(receiver, selector, value)
}

display_link_msg_void_range :: proc(receiver, selector: rawptr, value: Frame_Rate_Range) {
	send := transmute(proc "c" (_: rawptr, _: rawptr, _: Frame_Rate_Range))frame_timer_send_address
	send(receiver, selector, value)
}

display_link_msg_f64 :: proc(receiver, selector: rawptr) -> f64 {
	send := transmute(proc "c" (_: rawptr, _: rawptr) -> f64)frame_timer_send_address
	return send(receiver, selector)
}

// Create a macOS 14 view-owned display link on the main run loop. The link
// starts paused and tracks the screen that presents the view.
display_link_start :: proc(
	link: ^Display_Link,
	view, target: rawptr,
	callback_name: cstring,
	rate_range: Frame_Rate_Range = {30, 120, 120},
) -> bool {
	if link == nil || link.native != nil || view == nil || target == nil || callback_name == nil {
		return false
	}
	if _, valid := display_link_rate_range(
		rate_range.minimum,
		rate_range.maximum,
		rate_range.preferred,
	); !valid {
		return false
	}
	if !frame_timer_load_objc() {return false}

	callback := sel_registerName(callback_name)
	if callback == nil {return false}
	native := display_link_msg_id_id_sel(
		view,
		sel_registerName("displayLinkWithTarget:selector:"),
		target,
		callback,
	)
	if native == nil {return false}
	frame_timer_msg_void(native, sel_registerName("retain"))
	display_link_msg_void_range(
		native,
		sel_registerName("setPreferredFrameRateRange:"),
		rate_range,
	)
	display_link_msg_void_bool(native, sel_registerName("setPaused:"), true)

	run_loop := frame_timer_msg_id(
		objc_getClass("NSRunLoop"),
		sel_registerName("mainRunLoop"),
	)
	if run_loop == nil {
		frame_timer_msg_void(native, sel_registerName("release"))
		return false
	}
	add_to_run_loop := sel_registerName("addToRunLoop:forMode:")
	frame_timer_msg_void_id_id(native, add_to_run_loop, run_loop, NSDefaultRunLoopMode)
	frame_timer_msg_void_id_id(native, add_to_run_loop, run_loop, NSEventTrackingRunLoopMode)
	link.native = native
	link.paused = true
	return true
}

display_link_set_paused :: proc(link: ^Display_Link, paused: bool) {
	if link == nil || link.native == nil || link.paused == paused {return}
	if frame_timer_load_objc() {
		display_link_msg_void_bool(link.native, sel_registerName("setPaused:"), paused)
		link.paused = paused
	}
}

display_link_timestamp :: proc(link: ^Display_Link) -> f64 {
	if link == nil || link.native == nil || !frame_timer_load_objc() {return 0}
	return display_link_msg_f64(link.native, sel_registerName("timestamp"))
}

display_link_target_timestamp :: proc(link: ^Display_Link) -> f64 {
	if link == nil || link.native == nil || !frame_timer_load_objc() {return 0}
	return display_link_msg_f64(link.native, sel_registerName("targetTimestamp"))
}

display_link_duration :: proc(link: ^Display_Link) -> f64 {
	if link == nil || link.native == nil || !frame_timer_load_objc() {return 0}
	return display_link_msg_f64(link.native, sel_registerName("duration"))
}

display_link_stop :: proc(link: ^Display_Link) {
	if link == nil || link.native == nil {return}
	if frame_timer_load_objc() {
		frame_timer_msg_void(link.native, sel_registerName("invalidate"))
		frame_timer_msg_void(link.native, sel_registerName("release"))
	}
	link^ = {}
}
