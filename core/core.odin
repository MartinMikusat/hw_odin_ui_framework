package ui

import "core:hash"
import "core:mem"
import "core:strings"
import draw "ui_framework:draw"

Key :: distinct u64
Action_ID :: distinct u64
Font_Handle :: distinct u64
Text_Run_ID :: distinct u64

Vec2 :: struct {
	x, y: f32,
}

Insets :: struct {
	left, bottom, right, top: f32,
}

Axis :: enum {
	Horizontal,
	Vertical,
}

Flow :: enum {
	Overlay,
	Row,
	Column,
}

Align :: enum {
	Start,
	Center,
	End,
	Stretch,
}

Position_Kind :: enum {
	Flow,
	Absolute,
}

Size_Kind :: enum {
	Auto,
	Points,
	Text,
	Percent,
	Remaining,
	Children_Sum,
}

Size :: struct {
	kind:   Size_Kind,
	value:  f32,
	strictness: f32,
	minimum: f32,
	maximum: f32,
}

points :: proc(value: f32) -> Size {return {kind = .Points, value = value, strictness = 1}}
text_size :: proc() -> Size {return {kind = .Text, strictness = 1}}
percent :: proc(value: f32) -> Size {return {kind = .Percent, value = value, strictness = 1}}
remaining :: proc(weight: f32 = 1) -> Size {return {kind = .Remaining, value = weight}}
children_sum :: proc() -> Size {return {kind = .Children_Sum, strictness = 1}}

flex_points :: proc(value, strictness: f32) -> Size {
	return {
		kind = .Points,
		value = value,
		strictness = min(max(strictness, 0), 1),
	}
}

Layout :: struct {
	width:       Size,
	height:      Size,
	flow:        Flow,
	position:    Position_Kind,
	absolute:    draw.Rect,
	padding:     Insets,
	gap:         f32,
	main_align:  Align,
	cross_align: Align,
	offset:      Vec2,
}

Text_Align :: enum {
	Start,
	Center,
	End,
}

Text_Style :: struct {
	font:       Font_Handle,
	size:       f32,
	tracking:   f32,
	horizontal: Text_Align,
	vertical:   Text_Align,
	inset:      f32,
	truncate:   bool,
}

Style :: struct {
	background:       draw.Color,
	border:           draw.Color,
	text:             draw.Color,
	corner_radius:    f32,
	corner_shape:     draw.Corner_Shape,
	border_thickness: f32,
	edge_softness:    f32,
	opacity:          f32,
	clip:             bool,
	text_style:       Text_Style,
}

Box_Flag :: enum {
	Draw_Background,
	Draw_Border,
	Draw_Text,
	Draw_Image,
	Interactive,
	Modal_Root,
	Surface_Dismiss,
	Input_Root,
	Input_Passthrough,
	Scroll,
	Clip,
	Allow_Overflow_X,
	Allow_Overflow_Y,
	Floating_X,
	Floating_Y,
	Click_To_Focus,
	Focus_Root,
	Focus_Navigation_X,
	Focus_Navigation_Y,
	Disabled,
	Animate_X,
	Animate_Y,
	Drop_Shadow,
}

Box_Flags :: bit_set[Box_Flag]

Control_Capability :: enum {
	Hover,
	Primary_Press,
	Secondary_Press,
	Drag,
	Scroll,
	Numbered,
	Direct_Keyboard,
	Accessibility,
	Flash,
	Command_Menu,
	CLI,
	Editable,
}

Control_Capabilities :: bit_set[Control_Capability]

Accessibility_Role :: enum {
	None,
	Button,
	Text_Field,
	Check_Box,
	Radio_Button,
	Slider,
	List,
	List_Item,
	Group,
	Link,
}

Flash_Anchor :: enum {
	Top_Left,
	Top_Right,
	Bottom_Left,
	Bottom_Right,
	Center,
}

Number_Code :: struct {
	first, second: i8,
	digits:        i8,
}

Action_Record :: struct {
	id:                 Action_ID,
	functional_name:    string,
	label:              string,
	enabled:            bool,
	unavailable_reason: string,
	number_code:        Number_Code,
}

Control_Descriptor :: struct {
	functional_name:     string,
	accessibility_label: string,
	accessibility_role:  Accessibility_Role,
	flash_label:         string,
	flash_anchor:        Flash_Anchor,
	capabilities:        Control_Capabilities,
	action:              Action_ID,
}

Control_Record :: struct {
	id:                  Key,
	functional_name:     string,
	accessibility_label: string,
	accessibility_role:  Accessibility_Role,
	flash_label:         string,
	flash_anchor:        Flash_Anchor,
	capabilities:        Control_Capabilities,
	action:              Action_ID,
	rect:                draw.Rect,
	clip:                draw.Rect,
	clip_set:            bool,
	layer:               Layer,
	focusable:           bool,
	focus_root:          Key,
	surface:             Key,
	input_passthrough:   bool,
	enabled:             bool,
}

Activation_Source :: enum {
	Pointer,
	Numbered,
	Direct_Keyboard,
	Accessibility,
	Flash,
	Command_Menu,
	CLI,
}

Activation :: struct {
	action:     Action_ID,
	control:    Key,
	source:     Activation_Source,
	point:      Vec2,
	normalized: Vec2,
}

Layer :: enum {
	Base,
	Popup,
	Tooltip,
	Modal,
	Debug,
}

Pointer_Button :: enum {
	Primary,
	Middle,
	Secondary,
}

Modifier :: enum {
	Shift,
	Control,
	Option,
	Command,
	Caps_Lock,
}

Modifiers :: bit_set[Modifier]

Event_Kind :: enum {
	Pointer_Move,
	Pointer_Press,
	Pointer_Release,
	Scroll,
	Key_Press,
	Key_Release,
	Dismiss_Request,
	Focus_Next,
	Focus_Previous,
	Activate_Focused,
	Text,
	File_Drop,
}

Event :: struct {
	kind:          Event_Kind,
	button:        Pointer_Button,
	key:           u32,
	modifiers:     Modifiers,
	text:          string,
	point:         Vec2,
	delta:         Vec2,
	timestamp_us:  u64,
	consumed:      bool,
}

Signal_Flag :: enum {
	Pressed,
	Released,
	Clicked,
	Double_Clicked,
	Triple_Clicked,
	Dragging,
	Hovering,
	Mouse_Over,
	Scrolled,
	Keyboard_Pressed,
	Keyboard_Released,
	Text_Input,
	Dismiss_Requested,
	Focused,
}

Signal_Flags :: bit_set[Signal_Flag]

Signal :: struct {
	control:  Key,
	action:   Action_ID,
	flags:    Signal_Flags,
	button:   Pointer_Button,
	point:    Vec2,
	delta:    Vec2,
	modifiers: Modifiers,
	key:      u32,
	text:     string,
}

Animation :: struct {
	current:         f32,
	target:          f32,
	velocity:        f32,
	start:           f32,
	elapsed:         f32,
	delay:           f32,
	duration:        f32,
	rate:            f32,
	epsilon:         f32,
	velocity_epsilon: f32,
	timed:           bool,
	spring:          bool,
	last_seen_frame: u64,
}

Declaration_Field :: enum {Layout, Style, Flags, Layer}
Declaration_Fields :: bit_set[Declaration_Field]

Declarations :: struct {
	layout: Layout,
	style:  Style,
	flags:  Box_Flags,
	layer:  Layer,
	fields: Declaration_Fields,
}

Text_Metrics :: struct {
	width, ascent, descent, leading: f32,
}

Prepared_Text :: struct {
	run:     Text_Run_ID,
	metrics: Text_Metrics,
}

Prepare_Text_Proc :: proc(
	user_data: rawptr,
	font: Font_Handle,
	text: string,
	size, tracking, maximum_width: f32,
	truncate: bool,
) -> Prepared_Text

Emit_Text_Proc :: proc(
	user_data: rawptr,
	list: ^draw.List,
	run: Text_Run_ID,
	label: string,
	rect: draw.Rect,
	style: Text_Style,
	color: draw.Color,
)

Text_Backend :: struct {
	user_data: rawptr,
	prepare:   Prepare_Text_Proc,
	emit:      Emit_Text_Proc,
}

Custom_Draw_Proc :: proc(user_data: rawptr, list: ^draw.List, rect: draw.Rect)
Custom_Transform_Proc :: proc(user_data: rawptr, rect: draw.Rect) -> draw.Transform_2D

Persistent_State :: struct {
	hot:             bool,
	active:          bool,
	focused:         bool,
	disabled:        bool,
	scroll:          Vec2,
	scroll_target:   Vec2,
	view_bounds:     Vec2,
	last_rect:       draw.Rect,
	hot_t:           f32,
	active_t:        f32,
	focus_t:         f32,
	disabled_t:      f32,
	last_seen_frame: u64,
}

Box :: struct {
	key:          Key,
	debug_label:  string,
	parent:       int,
	first_child:  int,
	last_child:   int,
	next_sibling: int,
	layout:       Layout,
	style:        Style,
	flags:        Box_Flags,
	text:         string,
	texture:      draw.Texture_Handle,
	texture_src:  draw.Rect,
	control:      Control_Descriptor,
	custom_draw:  Custom_Draw_Proc,
	custom_data:  rawptr,
	custom_transform: Custom_Transform_Proc,
	transform_data:   rawptr,
	text_run:     Text_Run_ID,
	text_metrics: Text_Metrics,
	desired:      Vec2,
	rect:         draw.Rect,
	clipped_rect: draw.Rect,
	layer:        Layer,
	surface:      int,
	overflow:     Vec2,
}

Surface_Record :: struct {
	key:             Key,
	parent:          int,
	root_box:        int,
	input_root:      int,
	dismiss_control: Key,
}

Frame_Input :: struct {
	viewport:      draw.Rect,
	backing_scale: f32,
	delta_seconds: f32,
	pointer:       Vec2,
}

Frame_Output :: struct {
	draw_list: ^draw.List,
	actions:   []Action_Record,
	controls:  []Control_Record,
	signals:   []Signal,
	events:    []Event,
	frame:     u64,
	active_surface:  Key,
	dismiss_control: Key,
}

Frame_Request_Reason :: enum {
	Input,
	State,
	Animation,
	Surface,
	Diagnostic,
}

Frame_Request_Reasons :: bit_set[Frame_Request_Reason]
Frame_Request_Proc :: proc(user_data: rawptr)

Published_Frame :: struct {
	actions:  [dynamic]Action_Record,
	controls: [dynamic]Control_Record,
	signals:  [dynamic]Signal,
	frame:    u64,
	active_surface:  Key,
	dismiss_control: Key,
}

Context :: struct {
	allocator: mem.Allocator,
	states:    map[Key]Persistent_State,
	animations: map[Key]Animation,
	surface_focus: map[Key]Key,
	events:    [dynamic]Event,
	published: Published_Frame,
	hot:       Key,
	active:    [3]Key,
	focused:   Key,
	active_surface: Key,
	press_keys: [3][3]Key,
	press_times_us: [3][3]u64,
	press_points: [3][3]Vec2,
	drag_start: Vec2,
	frame_requests: Frame_Request_Reasons,
	frame_request_proc: Frame_Request_Proc,
	frame_request_data: rawptr,
	frame:     u64,
}

Frame :: struct {
	ui:            ^Context,
	allocator:     mem.Allocator,
	input:         Frame_Input,
	text_backend:  Text_Backend,
	boxes:         [dynamic]Box,
	parent_stack:  [dynamic]int,
	declaration_stack: [dynamic]Declarations,
	next_declarations: Declarations,
	has_next_declarations: bool,
	actions:       [dynamic]Action_Record,
	action_surfaces: [dynamic]int,
	controls:      [dynamic]Control_Record,
	signals:       [dynamic]Signal,
	events:        [dynamic]Event,
	draw_list:     draw.List,
	seen_keys:     map[Key]bool,
	seen_actions:  map[Action_ID]bool,
	surfaces:      [dynamic]Surface_Record,
	surface_stack: [dynamic]int,
}

key_from_string :: proc(value: string) -> Key {
	if len(value) == 0 {return Key(0)}
	return Key(hash.fnv64a(transmute([]u8)value))
}

display_part :: proc(value: string) -> string {
	if index := strings.index(value, "##"); index >= 0 {return value[:index]}
	return value
}

identity_part :: proc(value: string) -> string {
	if index := strings.index(value, "###"); index >= 0 {return value[index:]}
	return value
}

key_from_label :: proc(parent: Key, value: string) -> Key {
	return key_combine(parent, identity_part(value))
}

key_combine :: proc(parent: Key, value: string) -> Key {
	hash_value := u64(parent)
	if hash_value == 0 {hash_value = 14695981039346656037}
	for byte in transmute([]u8)value {
		hash_value = (hash_value ~ u64(byte))*1099511628211
	}
	return Key(hash_value)
}

action_id_from_string :: proc(value: string) -> Action_ID {
	return Action_ID(key_from_string(value))
}

context_init :: proc(ui: ^Context, allocator := context.allocator) {
	assert(ui != nil)
	ui^ = Context{allocator = allocator}
	ui.states = make(map[Key]Persistent_State, allocator)
	ui.animations = make(map[Key]Animation, allocator)
	ui.surface_focus = make(map[Key]Key, allocator)
	ui.events = make([dynamic]Event, allocator)
	ui.published.actions = make([dynamic]Action_Record, allocator)
	ui.published.controls = make([dynamic]Control_Record, allocator)
	ui.published.signals = make([dynamic]Signal, allocator)
}

clear_published :: proc(ui: ^Context) {
	for &action in ui.published.actions {
		delete(action.functional_name, ui.allocator)
		delete(action.label, ui.allocator)
		delete(action.unavailable_reason, ui.allocator)
	}
	for &control in ui.published.controls {
		delete(control.functional_name, ui.allocator)
		delete(control.accessibility_label, ui.allocator)
		delete(control.flash_label, ui.allocator)
	}
	for &signal in ui.published.signals {
		delete(signal.text, ui.allocator)
	}
	clear(&ui.published.actions)
	clear(&ui.published.controls)
	clear(&ui.published.signals)
}

context_destroy :: proc(ui: ^Context) {
	if ui == nil {return}
	clear_published(ui)
	delete(ui.published.actions)
	delete(ui.published.controls)
	delete(ui.published.signals)
	for &event in ui.events {delete(event.text, ui.allocator)}
	delete(ui.events)
	delete(ui.states)
	delete(ui.animations)
	delete(ui.surface_focus)
	ui^ = {}
}

set_frame_request_callback :: proc(
	ui: ^Context,
	callback: Frame_Request_Proc,
	user_data: rawptr = nil,
) {
	assert(ui != nil)
	ui.frame_request_proc = callback
	ui.frame_request_data = user_data
}

request_frame :: proc(ui: ^Context, reason: Frame_Request_Reason) {
	assert(ui != nil)
	was_empty := card(ui.frame_requests) == 0
	ui.frame_requests += {reason}
	if was_empty && ui.frame_request_proc != nil {
		ui.frame_request_proc(ui.frame_request_data)
	}
}

take_frame_requests :: proc(ui: ^Context) -> Frame_Request_Reasons {
	assert(ui != nil)
	result := ui.frame_requests
	ui.frame_requests = {}
	return result
}

has_frame_requests :: proc(ui: ^Context) -> bool {
	return ui != nil && card(ui.frame_requests) > 0
}

default_style :: proc() -> Style {
	return {
		text = {1, 1, 1, 1},
		edge_softness = 1,
		opacity = 1,
		text_style = {size = 12, vertical = .Center},
	}
}

begin_frame :: proc(
	ui: ^Context,
	input: Frame_Input,
	text_backend: Text_Backend = {},
	allocator := context.allocator,
) -> Frame {
	assert(ui != nil)
	ui.frame += 1
	frame := Frame{
		ui = ui,
		allocator = allocator,
		input = input,
		text_backend = text_backend,
	}
	frame.boxes = make([dynamic]Box, 0, 256, allocator)
	frame.parent_stack = make([dynamic]int, 0, 32, allocator)
	frame.declaration_stack = make([dynamic]Declarations, 0, 16, allocator)
	frame.actions = make([dynamic]Action_Record, 0, 128, allocator)
	frame.action_surfaces = make([dynamic]int, 0, 128, allocator)
	frame.controls = make([dynamic]Control_Record, 0, 128, allocator)
	frame.signals = make([dynamic]Signal, 0, 64, allocator)
	frame.events = make([dynamic]Event, 0, len(ui.events), allocator)
	frame.surfaces = make([dynamic]Surface_Record, 0, 8, allocator)
	frame.surface_stack = make([dynamic]int, 0, 8, allocator)
	for event in ui.events {
		copy := event
		copy.text = strings.clone(event.text, allocator)
		append(&frame.events, copy)
	}
	for &event in ui.events {delete(event.text, ui.allocator)}
	clear(&ui.events)
	frame.seen_keys = make(map[Key]bool, allocator)
	frame.seen_actions = make(map[Action_ID]bool, allocator)
	draw.list_init(&frame.draw_list, allocator, input.backing_scale)
	root := Box{
		key = key_from_string("framework root"),
		parent = -1,
		first_child = -1,
		last_child = -1,
		next_sibling = -1,
		layout = {
			width = points(input.viewport.w),
			height = points(input.viewport.h),
			flow = .Overlay,
			main_align = .End,
		},
		style = default_style(),
		rect = input.viewport,
	}
	append(&frame.boxes, root)
	append(&frame.surfaces, Surface_Record{
		key = root.key,
		parent = -1,
		root_box = 0,
		input_root = -1,
	})
	append(&frame.surface_stack, 0)
	append(&frame.parent_stack, 0)
	append(&frame.declaration_stack, Declarations{style = default_style()})
	frame.seen_keys[root.key] = true
	if len(ui.published.controls) > 0 && len(frame.events) > 0 {
		append(&frame.controls, ..ui.published.controls[:])
		process_events(&frame, false)
		clear(&frame.controls)
	}
	return frame
}

frame_destroy :: proc(frame: ^Frame) {
	if frame == nil {return}
	draw.list_destroy(&frame.draw_list)
	delete(frame.boxes)
	delete(frame.parent_stack)
	delete(frame.declaration_stack)
	delete(frame.actions)
	delete(frame.action_surfaces)
	delete(frame.controls)
	delete(frame.signals)
	for &event in frame.events {delete(event.text, frame.allocator)}
	delete(frame.events)
	delete(frame.surfaces)
	delete(frame.surface_stack)
	delete(frame.seen_keys)
	delete(frame.seen_actions)
	frame^ = {}
}

touch_state :: proc(frame: ^Frame, key: Key) {
	state := frame.ui.states[key]
	state.last_seen_frame = frame.ui.frame
	frame.ui.states[key] = state
}

get_state :: proc(ui: ^Context, key: Key) -> Persistent_State {
	return ui.states[key]
}

set_state :: proc(ui: ^Context, key: Key, state: Persistent_State) {
	next := state
	next.last_seen_frame = ui.frame
	ui.states[key] = next
}

register_action :: proc(frame: ^Frame, action: Action_Record) {
	assert(frame != nil)
	assert(action.id != Action_ID(0))
	assert(!frame.seen_actions[action.id], "duplicate action identifier")
	frame.seen_actions[action.id] = true
	append(&frame.actions, action)
	append(&frame.action_surfaces, frame.surface_stack[len(frame.surface_stack)-1])
}

find_action :: proc(actions: []Action_Record, id: Action_ID) -> ^Action_Record {
	for &action in actions {if action.id == id {return &action}}
	return nil
}

append_box :: proc(frame: ^Frame, box: Box) -> int {
	assert(frame != nil)
	assert(box.key != Key(0))
	assert(!frame.seen_keys[box.key], "duplicate visible box key")
	frame.seen_keys[box.key] = true
	logical_parent := frame.parent_stack[len(frame.parent_stack)-1]
	parent := logical_parent
	current_surface := frame.surface_stack[len(frame.surface_stack)-1]
	next := box
	if .Modal_Root in next.flags {
		parent = 0
		next.flags += {.Focus_Root, .Input_Root}
	}
	next.parent = parent
	if next.layer == .Base && frame.boxes[parent].layer != .Base {
		next.layer = frame.boxes[parent].layer
	}
	if .Clip in next.flags {next.style.clip = true}
	next.first_child = -1
	next.last_child = -1
	next.next_sibling = -1
	if next.style.opacity == 0 {next.style.opacity = 1}
	index := len(frame.boxes)
	if .Modal_Root in next.flags {
		next.surface = len(frame.surfaces)
		append(&frame.surfaces, Surface_Record{
			key = next.key,
			parent = current_surface,
			root_box = index,
			input_root = index,
		})
	} else {
		next.surface = current_surface
	}
	append(&frame.boxes, next)
	if frame.boxes[parent].first_child < 0 {
		frame.boxes[parent].first_child = index
	} else {
		frame.boxes[frame.boxes[parent].last_child].next_sibling = index
	}
	frame.boxes[parent].last_child = index
	touch_state(frame, next.key)
	surface := &frame.surfaces[next.surface]
	if .Input_Root in next.flags {
		candidate_layer := next.layer
		if next.surface > 0 && candidate_layer == .Modal {candidate_layer = .Base}
		current_layer := Layer.Base
		if surface.input_root >= 0 {
			current_layer = frame.boxes[surface.input_root].layer
			if next.surface > 0 && current_layer == .Modal {current_layer = .Base}
		}
		if surface.input_root < 0 || candidate_layer >= current_layer {
			surface.input_root = index
		}
	}
	if .Surface_Dismiss in next.flags {
		assert(surface.dismiss_control == Key(0), "duplicate surface dismiss control")
		surface.dismiss_control = next.key
	}
	return index
}

box_begin :: proc(frame: ^Frame, box: Box) -> int {
	index := append_box(frame, box)
	append(&frame.parent_stack, index)
	if .Modal_Root in frame.boxes[index].flags {
		append(&frame.surface_stack, frame.boxes[index].surface)
	}
	return index
}

box_end :: proc(frame: ^Frame) {
	assert(len(frame.parent_stack) > 1)
	index := frame.parent_stack[len(frame.parent_stack)-1]
	if .Modal_Root in frame.boxes[index].flags {
		assert(len(frame.surface_stack) > 1)
		resize(&frame.surface_stack, len(frame.surface_stack)-1)
	}
	resize(&frame.parent_stack, len(frame.parent_stack)-1)
}

box_add :: proc(frame: ^Frame, box: Box) -> int {
	assert(.Modal_Root not_in box.flags, "a modal root must use box_begin")
	return append_box(frame, box)
}

publish :: proc(ui: ^Context, output: Frame_Output) {
	assert(ui != nil)
	publish_records(
		ui,
		output.actions,
		output.controls,
		output.frame,
		output.active_surface,
		output.dismiss_control,
	)
	for signal in output.signals {
		copy := signal
		copy.text = strings.clone(signal.text, ui.allocator)
		append(&ui.published.signals, copy)
	}
}

contains :: proc(rect: draw.Rect, point: Vec2) -> bool {
	return point.x >= rect.x && point.x < rect.x+rect.w &&
	       point.y >= rect.y && point.y < rect.y+rect.h
}

capability_for_source :: proc(source: Activation_Source) -> Control_Capability {
	switch source {
	case .Pointer: return .Primary_Press
	case .Numbered: return .Numbered
	case .Direct_Keyboard: return .Direct_Keyboard
	case .Accessibility: return .Accessibility
	case .Flash: return .Flash
	case .Command_Menu: return .Command_Menu
	case .CLI: return .CLI
	}
	return .Primary_Press
}

activate_control :: proc(
	ui: ^Context,
	control_id: Key,
	source: Activation_Source,
	point: Vec2 = {},
) -> (Activation, bool) {
	return activate_control_in_view(
		registry_view_from_records(
			ui.published.actions[:],
			ui.published.controls[:],
			ui.published.frame,
		),
		control_id,
		source,
		point,
	)
}

hit_test :: proc(
	ui: ^Context,
	point: Vec2,
	capability := Control_Capability.Primary_Press,
) -> ^Control_Record {
	return hit_test_records(ui.published.controls[:], point, capability)
}

activate_at_point :: proc(ui: ^Context, point: Vec2) -> (Activation, bool) {
	control := hit_test(ui, point)
	if control == nil {return {}, false}
	return activate_control(ui, control.id, .Pointer, point)
}

activate_action :: proc(ui: ^Context, action_id: Action_ID, source: Activation_Source) -> (Activation, bool) {
	return activate_action_in_view(
		registry_view_from_records(
			ui.published.actions[:],
			ui.published.controls[:],
			ui.published.frame,
		),
		action_id,
		source,
	)
}
