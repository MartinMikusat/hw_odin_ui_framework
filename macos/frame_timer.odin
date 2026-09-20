package macos

import "core:dynlib"
import "core:math"

Frame_Timer :: struct {
	native: rawptr,
}

// Foundation reexports the Objective-C runtime (as in Odin's Foundation bindings).
foreign import frame_timer_objc "system:Foundation.framework"
foreign frame_timer_objc {
	objc_getClass    :: proc "c" (name: cstring) -> rawptr ---
	sel_registerName :: proc "c" (name: cstring) -> rawptr ---
}

foreign import frame_timer_foundation "system:Foundation.framework"
foreign frame_timer_foundation {
	NSDefaultRunLoopMode: rawptr
}

foreign import frame_timer_appkit "system:AppKit.framework"
foreign frame_timer_appkit {
	NSEventTrackingRunLoopMode: rawptr
}

frame_timer_send_address: rawptr

frame_timer_load_objc :: proc() -> bool {
	if frame_timer_send_address != nil {return true}
	handle, loaded := dynlib.load_library("/usr/lib/libobjc.A.dylib")
	if !loaded {return false}
	frame_timer_send_address, loaded = dynlib.symbol_address(handle, "objc_msgSend")
	return loaded
}

frame_timer_msg_id :: proc(receiver, selector: rawptr) -> rawptr {
	send := transmute(proc "c" (_: rawptr, _: rawptr) -> rawptr)frame_timer_send_address
	return send(receiver, selector)
}

frame_timer_msg_void :: proc(receiver, selector: rawptr) {
	send := transmute(proc "c" (_: rawptr, _: rawptr))frame_timer_send_address
	send(receiver, selector)
}

frame_timer_msg_void_id_id :: proc(receiver, selector, first, second: rawptr) {
	send := transmute(proc "c" (_: rawptr, _: rawptr, _: rawptr, _: rawptr))frame_timer_send_address
	send(receiver, selector, first, second)
}

// Start one main-run-loop timer for normal event processing and live event tracking.
// Stop the timer before the application releases the callback target.
frame_timer_start :: proc(
	timer: ^Frame_Timer,
	target: rawptr,
	callback_name: cstring,
	frames_per_second: f64 = 60.0,
) -> bool {
	if timer == nil || timer.native != nil || target == nil || callback_name == nil ||
	   frames_per_second <= 0 || math.is_nan(frames_per_second) ||
	   math.is_inf(frames_per_second) {
		return false
	}
	if !frame_timer_load_objc() {return false}

	callback := sel_registerName(callback_name)
	if callback == nil {return false}
	timer_send := transmute(proc "c" (
		_: rawptr,
		_: rawptr,
		_: f64,
		_: rawptr,
		_: rawptr,
		_: rawptr,
		_: bool,
	) -> rawptr)frame_timer_send_address
	native := timer_send(
		objc_getClass("NSTimer"),
		sel_registerName("timerWithTimeInterval:target:selector:userInfo:repeats:"),
		1.0/frames_per_second,
		target,
		callback,
		nil,
		true,
	)
	if native == nil {return false}
	frame_timer_msg_void(native, sel_registerName("retain"))

	run_loop := frame_timer_msg_id(
		objc_getClass("NSRunLoop"),
		sel_registerName("mainRunLoop"),
	)
	if run_loop == nil {
		frame_timer_msg_void(native, sel_registerName("release"))
		return false
	}
	add_timer := sel_registerName("addTimer:forMode:")
	frame_timer_msg_void_id_id(
		run_loop,
		add_timer,
		native,
		NSDefaultRunLoopMode,
	)
	frame_timer_msg_void_id_id(
		run_loop,
		add_timer,
		native,
		NSEventTrackingRunLoopMode,
	)
	timer.native = native
	return true
}

frame_timer_stop :: proc(timer: ^Frame_Timer) {
	if timer == nil || timer.native == nil {return}
	if frame_timer_load_objc() {
		frame_timer_msg_void(timer.native, sel_registerName("invalidate"))
		frame_timer_msg_void(timer.native, sel_registerName("release"))
	}
	timer.native = nil
}
