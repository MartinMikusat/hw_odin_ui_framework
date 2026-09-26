package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import macos "ui_framework:macos"

foreign import objc "system:objc"
foreign objc {
	objc_getClass          :: proc "c" (name: cstring) -> rawptr ---
	sel_registerName       :: proc "c" (name: cstring) -> rawptr ---
	objc_allocateClassPair :: proc "c" (superclass: rawptr, name: cstring, extra_bytes: uint) -> rawptr ---
	objc_registerClassPair :: proc "c" (class: rawptr) ---
	class_addMethod        :: proc "c" (class, selector, implementation: rawptr, types: cstring) -> bool ---
}

send_address: rawptr
tick_count: int

msg_id :: proc(receiver, selector: rawptr) -> rawptr {
	send := cast(proc "c" (_: rawptr, _: rawptr) -> rawptr)send_address
	return send(receiver, selector)
}

msg_void :: proc(receiver, selector: rawptr) {
	send := cast(proc "c" (_: rawptr, _: rawptr))send_address
	send(receiver, selector)
}

nsstring :: proc(value: cstring) -> rawptr {
	send := cast(proc "c" (_: rawptr, _: rawptr, _: cstring) -> rawptr)send_address
	return send(objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"), value)
}

timer_tick :: proc "c" (self, command, timer: rawptr) {
	tick_count += 1
}

test_target :: proc() -> rawptr {
	class := objc_allocateClassPair(
		objc_getClass("NSObject"),
		"HWUIFrameTimerIntegrationTarget",
		0,
	)
	if class == nil {return nil}
	if !class_addMethod(
		class,
		sel_registerName("frameTimerTick:"),
		rawptr(timer_tick),
		"v@:@",
	) {
		return nil
	}
	objc_registerClassPair(class)
	return msg_id(class, sel_registerName("new"))
}

run_mode :: proc(mode: cstring, seconds: f64) {
	date_send := cast(proc "c" (_: rawptr, _: rawptr, _: f64) -> rawptr)send_address
	deadline := date_send(
		objc_getClass("NSDate"),
		sel_registerName("dateWithTimeIntervalSinceNow:"),
		seconds,
	)
	run_send := cast(proc "c" (
		_: rawptr,
		_: rawptr,
		_: rawptr,
		_: rawptr,
	) -> bool)send_address
	_ = run_send(
		msg_id(objc_getClass("NSRunLoop"), sel_registerName("mainRunLoop")),
		sel_registerName("runMode:beforeDate:"),
		nsstring(mode),
		deadline,
	)
}

fail :: proc(message: string) {
	fmt.eprintln(message)
	os.exit(1)
}

main :: proc() {
	handle, loaded := dynlib.load_library("/usr/lib/libobjc.A.dylib")
	if !loaded {fail("Could not load the Objective-C runtime")}
	send_address, loaded = dynlib.symbol_address(handle, "objc_msgSend")
	if !loaded {fail("Could not load objc_msgSend")}

	pool := msg_id(objc_getClass("NSAutoreleasePool"), sel_registerName("new"))
	defer msg_void(pool, sel_registerName("drain"))
	target := test_target()
	if target == nil {fail("Could not create the frame timer test target")}
	defer msg_void(target, sel_registerName("release"))

	timer: macos.Frame_Timer
	if !macos.frame_timer_start(&timer, target, "frameTimerTick:", 200.0) {
		fail("Could not start the frame timer")
	}
	defer macos.frame_timer_stop(&timer)

	run_mode("kCFRunLoopDefaultMode", 0.05)
	default_count := tick_count
	if default_count <= 0 {fail("The frame timer did not run in the default mode")}
	run_mode("NSEventTrackingRunLoopMode", 0.05)
	if tick_count <= default_count {fail("The frame timer did not run in event tracking mode")}

	macos.frame_timer_stop(&timer)
	stopped_count := tick_count
	run_mode("kCFRunLoopDefaultMode", 0.02)
	if tick_count != stopped_count {fail("The stopped frame timer fired again")}
	macos.frame_timer_stop(&timer)
}
