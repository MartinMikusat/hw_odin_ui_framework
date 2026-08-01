package ui

import "core:hash"
import "core:mem"
import "core:strings"
import draw "ui_framework:draw"

Key :: distinct u64
Action_ID :: distinct u64
Font_Handle :: distinct u64

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
}

Box_Flags :: bit_set[Box_Flag]

Control_Capability :: enum {
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
}

Animation :: struct {
	current:         f32,
	target:          f32,
	rate:            f32,
	epsilon:         f32,
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

Measure_Text_Proc :: proc(
	user_data: rawptr,
	font: Font_Handle,
	text: string,
	size, tracking, maximum_width: f32,
	truncate: bool,
) -> Text_Metrics

Emit_Text_Proc :: proc(
	user_data: rawptr,
	list: ^draw.List,
	font: Font_Handle,
	text: string,
	rect: draw.Rect,
	style: Text_Style,
	color: draw.Color,
)

Text_Backend :: struct {
	user_data: rawptr,
	measure:   Measure_Text_Proc,
	emit:      Emit_Text_Proc,
}

Custom_Draw_Proc :: proc(user_data: rawptr, list: ^draw.List, rect: draw.Rect)

Persistent_State :: struct {
	hot:             bool,
	active:          bool,
	focused:         bool,
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
	text_metrics: Text_Metrics,
	desired:      Vec2,
	rect:         draw.Rect,
	clipped_rect: draw.Rect,
	layer:        Layer,
	overflow:     Vec2,
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
}

Published_Frame :: struct {
	actions:  [dynamic]Action_Record,
	controls: [dynamic]Control_Record,
	signals:  [dynamic]Signal,
	frame:    u64,
}

Context :: struct {
	allocator: mem.Allocator,
	states:    map[Key]Persistent_State,
	animations: map[Key]Animation,
	events:    [dynamic]Event,
	published: Published_Frame,
	hot:       Key,
	active:    [3]Key,
	focused:   Key,
	press_keys: [3][3]Key,
	press_times_us: [3][3]u64,
	press_points: [3][3]Vec2,
	drag_start: Vec2,
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
	controls:      [dynamic]Control_Record,
	signals:       [dynamic]Signal,
	events:        [dynamic]Event,
	draw_list:     draw.List,
	seen_keys:     map[Key]bool,
	seen_actions:  map[Action_ID]bool,
	modal_root:    int,
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
	ui^ = {}
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
		modal_root = -1,
	}
	frame.boxes = make([dynamic]Box, 0, 256, allocator)
	frame.parent_stack = make([dynamic]int, 0, 32, allocator)
	frame.declaration_stack = make([dynamic]Declarations, 0, 16, allocator)
	frame.actions = make([dynamic]Action_Record, 0, 128, allocator)
	frame.controls = make([dynamic]Control_Record, 0, 128, allocator)
	frame.signals = make([dynamic]Signal, 0, 64, allocator)
	frame.events = make([dynamic]Event, 0, len(ui.events), allocator)
	for event in ui.events {
		copy := event
		copy.text = strings.clone(event.text, allocator)
		append(&frame.events, copy)
	}
	for &event in ui.events {delete(event.text, ui.allocator)}
	clear(&ui.events)
	frame.seen_keys = make(map[Key]bool, allocator)
	frame.seen_actions = make(map[Action_ID]bool, allocator)
	draw.list_init(&frame.draw_list, allocator)
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
	append(&frame.parent_stack, 0)
	append(&frame.declaration_stack, Declarations{style = default_style()})
	frame.seen_keys[root.key] = true
	if len(ui.published.controls) > 0 && len(frame.events) > 0 {
		append(&frame.controls, ..ui.published.controls[:])
		process_events(&frame)
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
	delete(frame.controls)
	delete(frame.signals)
	for &event in frame.events {delete(event.text, frame.allocator)}
	delete(frame.events)
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
	parent := frame.parent_stack[len(frame.parent_stack)-1]
	next := box
	next.parent = parent
	if next.layer == .Base && frame.boxes[parent].layer != .Base {
		next.layer = frame.boxes[parent].layer
	}
	if .Modal_Root in next.flags {next.layer = .Modal}
	if .Clip in next.flags {next.style.clip = true}
	next.first_child = -1
	next.last_child = -1
	next.next_sibling = -1
	if next.style.opacity == 0 {next.style.opacity = 1}
	index := len(frame.boxes)
	append(&frame.boxes, next)
	if frame.boxes[parent].first_child < 0 {
		frame.boxes[parent].first_child = index
	} else {
		frame.boxes[frame.boxes[parent].last_child].next_sibling = index
	}
	frame.boxes[parent].last_child = index
	touch_state(frame, next.key)
	if .Modal_Root in next.flags {frame.modal_root = index}
	return index
}

box_begin :: proc(frame: ^Frame, box: Box) -> int {
	index := append_box(frame, box)
	append(&frame.parent_stack, index)
	return index
}

box_end :: proc(frame: ^Frame) {
	assert(len(frame.parent_stack) > 1)
	resize(&frame.parent_stack, len(frame.parent_stack)-1)
}

box_add :: proc(frame: ^Frame, box: Box) -> int {
	return append_box(frame, box)
}

content_rect :: proc(box: ^Box) -> draw.Rect {
	return {
		box.rect.x + box.layout.padding.left,
		box.rect.y + box.layout.padding.bottom,
		max(f32(0), box.rect.w-box.layout.padding.left-box.layout.padding.right),
		max(f32(0), box.rect.h-box.layout.padding.bottom-box.layout.padding.top),
	}
}

clamp_size :: proc(value: f32, spec: Size) -> f32 {
	result := max(value, spec.minimum)
	if spec.maximum > 0 {result = min(result, spec.maximum)}
	return result
}

measure_text :: proc(frame: ^Frame, box: ^Box) -> Text_Metrics {
	if len(box.text) == 0 || frame.text_backend.measure == nil {return {}}
	return frame.text_backend.measure(
		frame.text_backend.user_data,
		box.style.text_style.font,
		box.text,
		box.style.text_style.size,
		box.style.text_style.tracking,
		0,
		false,
	)
}

axis_spec :: proc(box: ^Box, axis: Axis) -> Size {
	return box.layout.width if axis == .Horizontal else box.layout.height
}

axis_desired :: proc(box: ^Box, axis: Axis) -> f32 {
	return box.desired.x if axis == .Horizontal else box.desired.y
}

set_axis_desired :: proc(box: ^Box, axis: Axis, value: f32) {
	if axis == .Horizontal {box.desired.x = value} else {box.desired.y = value}
}

axis_padding :: proc(box: ^Box, axis: Axis) -> f32 {
	if axis == .Horizontal {return box.layout.padding.left+box.layout.padding.right}
	return box.layout.padding.bottom+box.layout.padding.top
}

axis_text_size :: proc(box: ^Box, axis: Axis) -> f32 {
	if axis == .Horizontal {return box.text_metrics.width+axis_padding(box, axis)}
	return box.text_metrics.ascent+box.text_metrics.descent+axis_padding(box, axis)
}

layout_measure_standalone :: proc(frame: ^Frame, axis: Axis) {
	for &box in frame.boxes {
		if axis == .Horizontal {box.text_metrics = measure_text(frame, &box)}
		spec := axis_spec(&box, axis)
		value := f32(0)
		switch spec.kind {
		case .Points: value = spec.value
		case .Text: value = axis_text_size(&box, axis)
		case .Auto: value = axis_text_size(&box, axis)
		case .Percent, .Remaining, .Children_Sum: value = spec.minimum
		}
		set_axis_desired(&box, axis, clamp_size(value, spec))
	}
}

layout_measure_upward :: proc(frame: ^Frame, index: int, axis: Axis) -> f32 {
	box := &frame.boxes[index]
	children_value := f32(0)
	child_count := 0
	flow_axis := (box.layout.flow == .Row && axis == .Horizontal) ||
	             (box.layout.flow == .Column && axis == .Vertical)
	for child := box.first_child; child >= 0; child = frame.boxes[child].next_sibling {
		if frame.boxes[child].layout.position == .Absolute {continue}
		value := layout_measure_upward(frame, child, axis)
		if child_count == 0 || flow_axis {
			children_value += value
		} else {
			children_value = max(children_value, value)
		}
		child_count += 1
	}
	if flow_axis && child_count > 1 {children_value += box.layout.gap*f32(child_count-1)}
	children_value += axis_padding(box, axis)
	spec := axis_spec(box, axis)
	value := axis_desired(box, axis)
	switch spec.kind {
	case .Children_Sum: value = children_value
	case .Auto: value = max(value, children_value)
	case .Points, .Text, .Percent, .Remaining:
	}
	value = clamp_size(value, spec)
	set_axis_desired(box, axis, value)
	return value
}

resolve_axis_size :: proc(spec: Size, desired, available, remaining_space, remaining_weight: f32) -> f32 {
	value := desired
	switch spec.kind {
	case .Points: value = spec.value
	case .Percent: value = available*spec.value
	case .Remaining:
		weight := spec.value
		if weight <= 0 {weight = 1}
		if remaining_weight > 0 {value = remaining_space*weight/remaining_weight}
	case .Text, .Children_Sum, .Auto:
	}
	return clamp_size(value, spec)
}

align_cross :: proc(container_start, container_size, child_size: f32, align: Align) -> f32 {
	switch align {
	case .Center: return container_start + (container_size-child_size)/2
	case .End: return container_start + container_size-child_size
	case .Start, .Stretch: return container_start
	}
	return container_start
}

axis_allows_overflow :: proc(box: ^Box, horizontal: bool) -> bool {
	return (.Allow_Overflow_X in box.flags) if horizontal else (.Allow_Overflow_Y in box.flags)
}

shrink_capacity :: proc(size: f32, spec: Size) -> f32 {
	return max(f32(0), size-spec.minimum)*(1-min(max(spec.strictness, 0), 1))
}

shrink_size :: proc(size: f32, spec: Size, violation, capacity: f32) -> f32 {
	if violation <= 0 || capacity <= 0 {return size}
	share := violation*shrink_capacity(size, spec)/capacity
	return max(spec.minimum, size-share)
}

translate_subtree :: proc(frame: ^Frame, index: int, delta: Vec2) {
	box := &frame.boxes[index]
	box.rect.x += delta.x
	box.rect.y += delta.y
	for child := box.first_child; child >= 0; child = frame.boxes[child].next_sibling {
		translate_subtree(frame, child, delta)
	}
}

apply_scroll_layout :: proc(frame: ^Frame, index: int, content: draw.Rect) {
	box := &frame.boxes[index]
	if .Scroll not_in box.flags || box.first_child < 0 {return}
	max_right := content.x
	min_bottom := content.y+content.h
	for child := box.first_child; child >= 0; child = frame.boxes[child].next_sibling {
		child_box := &frame.boxes[child]
		max_right = max(max_right, child_box.rect.x+child_box.rect.w)
		min_bottom = min(min_bottom, child_box.rect.y)
	}
	box.overflow = {
		max(f32(0), max_right-(content.x+content.w)),
		max(f32(0), content.y-min_bottom),
	}
	state := frame.ui.states[box.key]
	state.view_bounds = {content.w+box.overflow.x, content.h+box.overflow.y}
	state.scroll_target.x = min(max(state.scroll_target.x, 0), box.overflow.x)
	state.scroll_target.y = min(max(state.scroll_target.y, 0), box.overflow.y)
	state.scroll.x, _ = animation_step(
		state.scroll.x,
		state.scroll_target.x,
		22,
		frame.input.delta_seconds,
		0.01,
	)
	state.scroll.y, _ = animation_step(
		state.scroll.y,
		state.scroll_target.y,
		22,
		frame.input.delta_seconds,
		0.01,
	)
	frame.ui.states[box.key] = state
	if state.scroll.x == 0 && state.scroll.y == 0 {return}
	delta := Vec2{-state.scroll.x, state.scroll.y}
	for child := box.first_child; child >= 0; child = frame.boxes[child].next_sibling {
		translate_subtree(frame, child, delta)
	}
}

arrange_children :: proc(frame: ^Frame, index: int) {
	box := &frame.boxes[index]
	content := content_rect(box)
	if box.first_child < 0 {return}
	if box.layout.flow == .Overlay {
		for child_index := box.first_child; child_index >= 0; child_index = frame.boxes[child_index].next_sibling {
			child := &frame.boxes[child_index]
			if child.layout.position == .Absolute {
				child.rect = {
					content.x+child.layout.absolute.x+child.layout.offset.x,
					content.y+child.layout.absolute.y+child.layout.offset.y,
					child.layout.absolute.w,
					child.layout.absolute.h,
				}
			} else {
				width := resolve_axis_size(child.layout.width, child.desired.x, content.w, content.w, 1)
				height := resolve_axis_size(child.layout.height, child.desired.y, content.h, content.h, 1)
				if box.layout.cross_align == .Stretch {width = content.w}
				if box.layout.main_align == .Stretch {height = content.h}
				child.rect = {
					align_cross(content.x, content.w, width, box.layout.cross_align)+child.layout.offset.x,
					align_cross(content.y, content.h, height, box.layout.main_align)+child.layout.offset.y,
					width,
					height,
				}
			}
			arrange_children(frame, child_index)
		}
		apply_scroll_layout(frame, index, content)
		return
	}
	horizontal := box.layout.flow == .Row
	main_available := content.w if horizontal else content.h
	cross_available := content.h if horizontal else content.w
	fixed: f32
	shrinkable: f32
	remaining_weight: f32
	flow_count := 0
	for child_index := box.first_child; child_index >= 0; child_index = frame.boxes[child_index].next_sibling {
		child := &frame.boxes[child_index]
		if child.layout.position == .Absolute {continue}
		flow_count += 1
		spec := child.layout.width if horizontal else child.layout.height
		desired := child.desired.x if horizontal else child.desired.y
		if spec.kind == .Remaining {
			remaining_weight += max(f32(1), spec.value)
		} else {
			resolved := resolve_axis_size(spec, desired, main_available, 0, 0)
			fixed += resolved
			shrinkable += shrink_capacity(resolved, spec)
		}
	}
	gap_total := box.layout.gap*f32(max(0, flow_count-1))
	violation := max(f32(0), fixed+gap_total-main_available)
	if axis_allows_overflow(box, horizontal) {violation = 0}
	resolved_violation := min(violation, shrinkable)
	fixed -= resolved_violation
	remaining_space := max(f32(0), main_available-fixed-gap_total)
	used := fixed+gap_total
	if remaining_weight > 0 {used += remaining_space}
	main_cursor := f32(0)
	if box.layout.main_align == .Center {main_cursor = (main_available-used)/2}
	if box.layout.main_align == .End {main_cursor = main_available-used}
	for child_index := box.first_child; child_index >= 0; child_index = frame.boxes[child_index].next_sibling {
		child := &frame.boxes[child_index]
		if child.layout.position == .Absolute {
			child.rect = {
				content.x+child.layout.absolute.x+child.layout.offset.x,
				content.y+child.layout.absolute.y+child.layout.offset.y,
				child.layout.absolute.w,
				child.layout.absolute.h,
			}
			arrange_children(frame, child_index)
			continue
		}
		main_spec := child.layout.width if horizontal else child.layout.height
		cross_spec := child.layout.height if horizontal else child.layout.width
		main_desired := child.desired.x if horizontal else child.desired.y
		cross_desired := child.desired.y if horizontal else child.desired.x
		main_size := resolve_axis_size(main_spec, main_desired, main_available, remaining_space, remaining_weight)
		if main_spec.kind != .Remaining {
			main_size = shrink_size(main_size, main_spec, resolved_violation, shrinkable)
		}
		cross_size := resolve_axis_size(cross_spec, cross_desired, cross_available, cross_available, 1)
		if box.layout.cross_align == .Stretch {cross_size = cross_available}
		if !axis_allows_overflow(box, !horizontal) && cross_size > cross_available {
			capacity := shrink_capacity(cross_size, cross_spec)
			cross_size -= min(cross_size-cross_available, capacity)
		}
		cross_start := align_cross(0, cross_available, cross_size, box.layout.cross_align)
		if horizontal {
			child.rect = {
				content.x+main_cursor+child.layout.offset.x,
				content.y+cross_start+child.layout.offset.y,
				main_size,
				cross_size,
			}
		} else {
			child.rect = {
				content.x+cross_start+child.layout.offset.x,
				content.y+content.h-main_cursor-main_size+child.layout.offset.y,
				cross_size,
				main_size,
			}
		}
		main_cursor += main_size+box.layout.gap
		arrange_children(frame, child_index)
	}
	if horizontal {
		box.overflow.x = max(f32(0), used-main_available)
	} else {
		box.overflow.y = max(f32(0), used-main_available)
	}
	apply_scroll_layout(frame, index, content)
}

is_descendant_of :: proc(frame: ^Frame, index, ancestor: int) -> bool {
	for cursor := index; cursor >= 0; cursor = frame.boxes[cursor].parent {
		if cursor == ancestor {return true}
	}
	return false
}

emit_box :: proc(frame: ^Frame, index: int) {
	box := &frame.boxes[index]
	state := frame.ui.states[box.key]
	state.last_rect = box.rect
	state.last_seen_frame = frame.ui.frame
	frame.ui.states[box.key] = state
	box.clipped_rect = box.rect
	for parent := box.parent; parent >= 0; parent = frame.boxes[parent].parent {
		ancestor := &frame.boxes[parent]
		if ancestor.style.clip || .Clip in ancestor.flags {
			box.clipped_rect = draw.rect_intersection(box.clipped_rect, ancestor.rect)
		}
	}
	trace_label := box.debug_label
	if len(trace_label) == 0 {trace_label = box.text}
	if box.style.opacity < 1 {draw.push_opacity(&frame.draw_list, box.style.opacity)}
	if .Draw_Background in box.flags {
		draw.solid(
			&frame.draw_list,
			box.rect,
			box.style.background,
			box.style.corner_radius,
			0,
			box.style.edge_softness,
			trace_label,
		)
	}
	if .Draw_Border in box.flags && box.style.border_thickness > 0 {
		draw.solid(
			&frame.draw_list,
			box.rect,
			box.style.border,
			box.style.corner_radius,
			box.style.border_thickness,
			box.style.edge_softness,
			"border",
		)
	}
	if box.style.clip {draw.push_clip(&frame.draw_list, box.rect)}
	if .Draw_Image in box.flags {
		draw.image(&frame.draw_list, box.texture, box.rect, box.texture_src, label = trace_label)
	}
	if .Draw_Text in box.flags && frame.text_backend.emit != nil && len(box.text) > 0 {
		frame.text_backend.emit(
			frame.text_backend.user_data,
			&frame.draw_list,
			box.style.text_style.font,
			box.text,
			box.rect,
			box.style.text_style,
			box.style.text,
		)
	}
	if box.custom_draw != nil {box.custom_draw(box.custom_data, &frame.draw_list, box.rect)}
	if .Interactive in box.flags && (frame.modal_root < 0 || is_descendant_of(frame, index, frame.modal_root)) {
		action := find_action(frame.actions[:], box.control.action)
		enabled := box.control.action == Action_ID(0) || (action != nil && action.enabled)
		if .Disabled in box.flags {enabled = false}
		append(&frame.controls, Control_Record{
			id = box.key,
			functional_name = box.control.functional_name,
			accessibility_label = box.control.accessibility_label,
			accessibility_role = box.control.accessibility_role,
			flash_label = box.control.flash_label,
			flash_anchor = box.control.flash_anchor,
			capabilities = box.control.capabilities,
			action = box.control.action,
			rect = box.rect,
			clip = box.clipped_rect,
			clip_set = box.clipped_rect != box.rect,
			layer = box.layer,
			focusable = .Click_To_Focus in box.flags,
			focus_root = focus_root_for_box(frame, index),
			enabled = enabled,
		})
	}
	for child := box.first_child; child >= 0; child = frame.boxes[child].next_sibling {
		emit_box(frame, child)
	}
	if box.style.clip {draw.pop_clip(&frame.draw_list)}
	if box.style.opacity < 1 {draw.pop_opacity(&frame.draw_list)}
}

purge_old_state :: proc(ui: ^Context) {
	cutoff := u64(0)
	if ui.frame > 120 {cutoff = ui.frame-120}
	remove := make([dynamic]Key, context.temp_allocator)
	defer delete(remove)
	for key, state in ui.states {if state.last_seen_frame < cutoff {append(&remove, key)}}
	for key in remove {delete_key(&ui.states, key)}
}

end_frame :: proc(frame: ^Frame) -> Frame_Output {
	assert(frame != nil)
	assert(len(frame.parent_stack) == 1, "unclosed UI box")
	layout_measure_standalone(frame, .Horizontal)
	_ = layout_measure_upward(frame, 0, .Horizontal)
	layout_measure_standalone(frame, .Vertical)
	_ = layout_measure_upward(frame, 0, .Vertical)
	frame.boxes[0].rect = frame.input.viewport
	arrange_children(frame, 0)
	emit_box(frame, 0)
	process_events(frame)
	update_builtin_animations(frame.ui, frame.input.delta_seconds)
	purge_old_state(frame.ui)
	return {
		draw_list = &frame.draw_list,
		actions = frame.actions[:],
		controls = frame.controls[:],
		signals = frame.signals[:],
		events = frame.events[:],
		frame = frame.ui.frame,
	}
}

publish :: proc(ui: ^Context, output: Frame_Output) {
	assert(ui != nil)
	publish_records(ui, output.actions, output.controls, output.frame)
	for signal in output.signals {append(&ui.published.signals, signal)}
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
	capability := capability_for_source(source)
	for index := len(ui.published.controls)-1; index >= 0; index -= 1 {
		control := &ui.published.controls[index]
		if control.id != control_id || !control.enabled || capability not_in control.capabilities {continue}
		normalized := Vec2{}
		if control.rect.w > 0 {normalized.x = (point.x-control.rect.x)/control.rect.w}
		if control.rect.h > 0 {normalized.y = (point.y-control.rect.y)/control.rect.h}
		return {control.action, control.id, source, point, normalized}, true
	}
	return {}, false
}

hit_test :: proc(
	ui: ^Context,
	point: Vec2,
	capability := Control_Capability.Primary_Press,
) -> ^Control_Record {
	best: ^Control_Record
	best_layer := Layer.Base
	for index := len(ui.published.controls)-1; index >= 0; index -= 1 {
		control := &ui.published.controls[index]
		if !control.enabled || capability not_in control.capabilities ||
		   !control_contains(control, point) {continue}
		if best == nil || control.layer > best_layer {
			best = control
			best_layer = control.layer
		}
	}
	return best
}

activate_at_point :: proc(ui: ^Context, point: Vec2) -> (Activation, bool) {
	control := hit_test(ui, point)
	if control == nil {return {}, false}
	return activate_control(ui, control.id, .Pointer, point)
}

activate_action :: proc(ui: ^Context, action_id: Action_ID, source: Activation_Source) -> (Activation, bool) {
	action := find_action(ui.published.actions[:], action_id)
	if action == nil || !action.enabled {return {}, false}
	return {action = action_id, source = source}, true
}
