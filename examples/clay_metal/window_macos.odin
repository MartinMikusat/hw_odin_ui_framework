// A windowed macOS host for the hw_clay Metal renderer. Enabled with -window.
//
// The host owns an NSApplication, an NSWindow backed by a CAMetalLayer, and a
// display link. Each callback runs the same frame sequence as the offscreen
// harness, but encodes into the layer's drawable. Pointer events feed
// hw_clay.set_pointer_state, the wheel feeds update_scroll_containers, D toggles
// clay's debug view, and Escape quits. -frames N exits after N frames, which
// keeps the loop testable without leaving a window open.

package main

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:time"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import QC "vendor:darwin/QuartzCore"
import hw_clay "hw_clay:."
import coretext "ui_framework:coretext"
import draw "ui_framework:draw"
import macos "ui_framework:macos"
import metal "ui_framework:metal"
import hw_clay_ui "ui_framework:clay"

WINDOW_WIDTH :: 960.0
WINDOW_HEIGHT :: 640.0
WINDOW_STYLE :: NS.WindowStyleMask{.Titled, .Closable, .Miniaturizable, .Resizable}

Window_Host :: struct {
	app:          ^NS.Application,
	delegate:     ^NS.Object,
	window:       ^NS.Window,
	view:         ^NS.View,
	device:       ^MTL.Device,
	queue:        ^MTL.CommandQueue,
	layer:        ^QC.MetalLayer,
	display_link: macos.Display_Link,
	gpu:          metal.Renderer,
	text:         coretext.Context,
	draw_list:    draw.List,
	renderer:     hw_clay_ui.Renderer,
	clay:         hw_clay.Context,
	memory:       []u8,

	// Input state.
	pointer:      [2]f32,
	pointer_down: bool,
	scroll_delta: [2]f32,
	debug:        bool,
	quit:         bool,

	// Frame budget.
	frame_limit:      int,
	frames_attempted: int,
	frames_drawn:     int,
	deadline_seconds: f64,
	start_time:       time.Time,
	last_time:        f64,
	has_time:         bool,
}

host: Window_Host

add_method :: proc(class: NS.Class, name: cstring, imp: rawptr, types: cstring) -> bool {
	return bool(NS.class_addMethod(class, NS.sel_registerName(name), auto_cast imp, types))
}

pointer_from_event :: proc(host: ^Window_Host, event: ^NS.Event) -> [2]f32 {
	location := event->locationInWindow()
	point := host.view->convertPointFromView(location, nil)
	// NSView coordinates are bottom-left with y up; clay uses top-left y down.
	return {f32(point.x), f32(host.view->bounds().size.height) - f32(point.y)}
}

on_mouse_down :: proc "c" (self: NS.id, cmd: NS.SEL, event: ^NS.Event) {
	context = runtime.default_context()
	host.pointer = pointer_from_event(&host, event)
	host.pointer_down = true
}

on_mouse_up :: proc "c" (self: NS.id, cmd: NS.SEL, event: ^NS.Event) {
	context = runtime.default_context()
	host.pointer = pointer_from_event(&host, event)
	host.pointer_down = false
}

on_mouse_dragged :: proc "c" (self: NS.id, cmd: NS.SEL, event: ^NS.Event) {
	context = runtime.default_context()
	host.pointer = pointer_from_event(&host, event)
}

on_mouse_moved :: proc "c" (self: NS.id, cmd: NS.SEL, event: ^NS.Event) {
	context = runtime.default_context()
	host.pointer = pointer_from_event(&host, event)
}

on_scroll :: proc "c" (self: NS.id, cmd: NS.SEL, event: ^NS.Event) {
	context = runtime.default_context()
	// AppKit reports scrolling deltas in points; NSView y is up while clay's
	// scroll is y down.
	dx, dy := event->scrollingDelta()
	host.scroll_delta[0] += f32(dx)
	host.scroll_delta[1] += f32(-dy)
}

on_key_down :: proc "c" (self: NS.id, cmd: NS.SEL, event: ^NS.Event) {
	context = runtime.default_context()
	if event->isARepeat() {
		return
	}
	#partial switch NS.kVK(event->keyCode()) {
	case .ANSI_D:
		host.debug = !host.debug
		hw_clay.set_debug_mode_enabled(&host.clay, host.debug)
	case .Escape:
		host.quit = true
	case:
	}
}

on_accepts_first_responder :: proc "c" (self: NS.id, cmd: NS.SEL) -> bool {
	return true
}

on_frame :: proc "c" (self: NS.id, cmd: NS.SEL, timer: NS.id) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	window_host_frame(&host)
}

on_should_terminate :: proc "c" (self: NS.id, cmd: NS.SEL, sender: NS.id) -> bool {
	return true
}

register_classes :: proc() -> (delegate: ^NS.Object, view_class: NS.Class, ok: bool) {
	delegate_class := NS.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "ClayMetalDelegate", 0)
	if delegate_class == nil {
		return nil, nil, false
	}
	if !add_method(delegate_class, "clayFrame:", rawptr(on_frame), "v@:@") ||
	   !add_method(delegate_class, "applicationShouldTerminateAfterLastWindowClosed:", rawptr(on_should_terminate), "B@:@") {
		return nil, nil, false
	}
	NS.objc_registerClassPair(delegate_class)
	delegate = (^NS.Object)(NS.class_createInstance(delegate_class, 0))

	view_class = NS.objc_allocateClassPair(intrinsics.objc_find_class("NSView"), "ClayMetalView", 0)
	if view_class == nil {
		return nil, nil, false
	}
	if !add_method(view_class, "acceptsFirstResponder", rawptr(on_accepts_first_responder), "B@:") ||
	   !add_method(view_class, "mouseDown:", rawptr(on_mouse_down), "v@:@") ||
	   !add_method(view_class, "mouseUp:", rawptr(on_mouse_up), "v@:@") ||
	   !add_method(view_class, "mouseDragged:", rawptr(on_mouse_dragged), "v@:@") ||
	   !add_method(view_class, "mouseMoved:", rawptr(on_mouse_moved), "v@:@") ||
	   !add_method(view_class, "scrollWheel:", rawptr(on_scroll), "v@:@") ||
	   !add_method(view_class, "keyDown:", rawptr(on_key_down), "v@:@") {
		return nil, nil, false
	}
	NS.objc_registerClassPair(view_class)
	return delegate, view_class, true
}

window_host_init :: proc(host: ^Window_Host, frame_limit: int, deadline_seconds: f64, hidden: bool) -> bool {
	host.start_time = time.now()
	coretext.context_init(&host.text)
	host.renderer.text = &host.text
	host.renderer.viewport_height = f32(WINDOW_HEIGHT)
	hw_clay_ui.renderer_register_font(&host.renderer, FONT_UI, ".AppleSystemUIFont")
	hw_clay_ui.renderer_register_font(&host.renderer, FONT_MONO, "Menlo-Regular")
	draw.list_init(&host.draw_list, pixel_ratio = 2)
	host.renderer.list = &host.draw_list

	host.memory = make([]u8, hw_clay.min_memory_size())
	if !hw_clay.initialize(&host.clay, host.memory, {f32(WINDOW_WIDTH), f32(WINDOW_HEIGHT)}, {handler = clay_error_handler}) {
		fmt.eprintln("hw_clay_metal: clay initialize failed")
		return false
	}
	hw_clay.set_measure_text_function(&host.clay, hw_clay_ui.measure_text, &host.renderer)

	delegate, view_class, classes_ok := register_classes()
	if !classes_ok {
		fmt.eprintln("hw_clay_metal: could not register the window classes")
		return false
	}
	host.delegate = delegate

	host.app = NS.Application.sharedApplication()
	host.app->setActivationPolicy(.Regular)
	host.app->setDelegate((^NS.ApplicationDelegate)(delegate))

	frame := NS.Rect{{120, 120}, {WINDOW_WIDTH, WINDOW_HEIGHT}}
	host.window = NS.Window.alloc()->initWithContentRect(frame, WINDOW_STYLE, .Buffered, false)
	host.window->setTitle(NS.AT("hw_clay on Metal"))
	host.window->setAcceptsMouseMovedEvents(true)
	host.window->setDelegate((^NS.WindowDelegate)(delegate))

	host.view = (^NS.View)(NS.class_createInstance(view_class, 0))
	host.view = host.view->initWithFrame({{0, 0}, frame.size})
	host.window->setContentView(host.view)

	host.device = MTL.CreateSystemDefaultDevice()
	if host.device == nil {
		fmt.eprintln("hw_clay_metal: no Metal device")
		return false
	}
	host.queue = host.device->newCommandQueue()
	host.layer = QC.MetalLayer.layer()
	host.layer->setDevice(host.device)
	host.layer->setPixelFormat(.BGRA8Unorm)
	host.layer->setFramebufferOnly(true)
	host.view->setWantsLayer(true)
	host.view->setLayer((^NS.Layer)(host.layer))

	if !metal.renderer_init(
		&host.gpu,
		rawptr(host.device),
		pixel_format = uint(MTL.PixelFormat.BGRA8Unorm),
		metallib_data = UI_METALLIB,
	) {
		fmt.eprintln("hw_clay_metal: renderer_init failed")
		return false
	}
	if !macos.display_link_start(&host.display_link, rawptr(host.view), rawptr(host.delegate), "clayFrame:") {
		fmt.eprintln("hw_clay_metal: the display link did not start")
		return false
	}
	// The display link starts paused and only ticks while its view is on
	// screen, so a window ordered back may receive no callbacks.
	macos.display_link_set_paused(&host.display_link, false)
	_ = host.window->makeFirstResponder((^NS.Responder)(host.view))

	host.frame_limit = frame_limit
	fmt.printf("window host: started (%dx%d, frame limit %d)\n", i32(WINDOW_WIDTH), i32(WINDOW_HEIGHT), frame_limit)
	if hidden {
		intrinsics.objc_send(nil, host.window, "orderBack:", NS.id(nil))
	} else {
		host.window->makeKeyAndOrderFront(nil)
		host.app->activateIgnoringOtherApps(true)
	}
	return true
}

window_host_shutdown :: proc(host: ^Window_Host) {
	macos.display_link_stop(&host.display_link)
	metal.renderer_destroy(&host.gpu)
	coretext.context_destroy(&host.text)
	draw.list_destroy(&host.draw_list)
	delete(host.memory)
}

window_host_frame :: proc(host: ^Window_Host) {
	if host.quit {
		host.app->terminate(nil)
		return
	}
	host.frames_attempted += 1
	// A window that is not composited never yields a drawable; the deadline
	// keeps the harness from waiting forever.
	if host.deadline_seconds > 0 && time.duration_seconds(time.since(host.start_time)) > host.deadline_seconds {
		fmt.eprintf("window host: deadline reached (%d callbacks, %d frames drawn, %d clay error(s))\n", host.frames_attempted, host.frames_drawn, error_count)
		host.app->terminate(nil)
		return
	}

	scale := f32(host.window->backingScaleFactor())
	bounds := host.view->bounds()
	host.layer->setContentsScale(NS.Float(scale))
	host.layer->setDrawableSize({bounds.size.width * NS.Float(scale), bounds.size.height * NS.Float(scale)})
	width := f32(bounds.size.width)
	height := f32(bounds.size.height)
	host.renderer.viewport_height = height

	timestamp := macos.display_link_timestamp(&host.display_link)
	delta: f32 = 1.0 / 60.0
	if host.has_time && timestamp > host.last_time {
		delta = f32(min(timestamp - host.last_time, 0.1))
	}
	host.last_time = timestamp
	host.has_time = true

	drawable := host.layer->nextDrawable()
	if drawable == nil {
		if host.frame_limit > 0 && host.frames_attempted >= host.frame_limit {
			host.app->terminate(nil)
		}
		return
	}

	metal.begin_texture_frame(&host.gpu)
	coretext.begin_frame(&host.text, scale, metal.atlas_io(&host.gpu))
	draw.list_reset(&host.draw_list)

	hw_clay.set_pointer_state(&host.clay, {host.pointer[0], host.pointer[1]}, host.pointer_down)
	hw_clay.update_scroll_containers(&host.clay, false, {host.scroll_delta[0], host.scroll_delta[1]}, delta)
	hw_clay.set_layout_dimensions(&host.clay, {width, height})
	host.scroll_delta = {0, 0}

	commands := create_layout(&host.clay, delta)
	hw_clay_ui.render_commands(&host.renderer, commands)
	coretext.flush(&host.text)

	command_buffer := host.queue->commandBuffer()
	if !metal.encode_to_drawable(&host.gpu, rawptr(command_buffer), rawptr(drawable->texture()), &host.draw_list, {width, height}, scale, {0.93, 0.94, 0.96, 1.0}) {
		fmt.eprintln("hw_clay_metal: encode failed")
		host.app->terminate(nil)
		return
	}
	command_buffer->presentDrawable(drawable)
	command_buffer->commit()

	host.frames_drawn += 1
	if host.frame_limit > 0 && host.frames_attempted >= host.frame_limit {
		fmt.printf("window host: %d callbacks, %d frames drawn, %d clay error(s)\n", host.frames_attempted, host.frames_drawn, error_count)
		host.app->terminate(nil)
	}
}
