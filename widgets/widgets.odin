package widgets

import ui "ui_framework:core"
import draw "ui_framework:draw"

Button_Options :: struct {
	layout:  ui.Layout,
	style:   ui.Style,
	control: ui.Control_Descriptor,
}

Widget_Result :: struct {
	key:    ui.Key,
	signal: ui.Signal,
}

Virtual_List :: struct {
	key:           ui.Key,
	first:         int,
	one_past_last: int,
	row_count:     int,
	row_height:    f32,
}

mix_color :: proc(a, b: draw.Color, amount: f32) -> draw.Color {
	t := min(max(amount, 0), 1)
	result: draw.Color
	for index in 0..<len(result) {result[index] = a[index]+(b[index]-a[index])*t}
	return result
}

label :: proc(
	frame: ^ui.Frame,
	label_string: string,
	layout: ui.Layout,
	style: ui.Style,
) -> int {
	box := ui.box_from_declarations(frame, label_string, {.Draw_Text})
	box.layout = layout
	box.style = style
	return ui.box_add(frame, box)
}

spacer :: proc(frame: ^ui.Frame, label_string: string, layout: ui.Layout) -> int {
	box := ui.box_from_declarations(frame, label_string)
	box.layout = layout
	return ui.box_add(frame, box)
}

button :: proc(
	frame: ^ui.Frame,
	label_string: string,
	action: ui.Action_ID,
	options: Button_Options,
) -> Widget_Result {
	box := ui.box_from_declarations(
		frame,
		label_string,
		{.Draw_Background, .Draw_Border, .Draw_Text, .Interactive, .Click_To_Focus},
	)
	box.layout = options.layout
	box.style = options.style
	box.control = options.control
	box.control.action = action
	if len(box.control.functional_name) == 0 {box.control.functional_name = ui.display_part(label_string)}
	if len(box.control.accessibility_label) == 0 {
		box.control.accessibility_label = ui.display_part(label_string)
	}
	if box.control.accessibility_role == .None {box.control.accessibility_role = .Button}
	if card(box.control.capabilities) == 0 {
		box.control.capabilities = {
			.Hover,
			.Primary_Press,
			.Direct_Keyboard,
			.Accessibility,
			.Flash,
			.Command_Menu,
			.CLI,
		}
	}
	state := ui.get_state(frame.ui, box.key)
	if state.hot_t > 0 {
		box.style.background = mix_color(
			box.style.background,
			box.style.text,
			state.hot_t*0.08,
		)
	}
	if state.active_t > 0 {
		box.style.background = mix_color(
			box.style.background,
			box.style.text,
			state.active_t*0.14,
		)
	}
	_ = ui.box_add(frame, box)
	return {key = box.key, signal = ui.signal_for_key(frame.signals[:], box.key)}
}

pane_begin :: proc(
	frame: ^ui.Frame,
	label_string: string,
	layout: ui.Layout,
	style: ui.Style,
	clip := false,
) -> int {
	flags := ui.Box_Flags{.Draw_Background}
	if style.border_thickness > 0 {flags += {.Draw_Border}}
	if clip {flags += {.Clip}}
	box := ui.box_from_declarations(frame, label_string, flags)
	box.layout = layout
	box.style = style
	return ui.box_begin(frame, box)
}

pane_end :: proc(frame: ^ui.Frame) {ui.box_end(frame)}

scroll_area_begin :: proc(
	frame: ^ui.Frame,
	label_string: string,
	layout: ui.Layout,
	style: ui.Style,
) -> Widget_Result {
	box := ui.box_from_declarations(
		frame,
		label_string,
		{.Draw_Background, .Clip, .Scroll, .Interactive},
	)
	box.layout = layout
	box.style = style
	box.control = {
		functional_name = ui.display_part(label_string),
		capabilities = {.Scroll},
	}
	_ = ui.box_begin(frame, box)
	return {key = box.key, signal = ui.signal_for_key(frame.signals[:], box.key)}
}

scroll_area_end :: proc(frame: ^ui.Frame) {ui.box_end(frame)}

visible_row_range :: proc(
	state: ui.Persistent_State,
	row_height, viewport_height: f32,
	row_count: int,
	overscan: int = 1,
) -> (first, one_past_last: int) {
	if row_height <= 0 || viewport_height <= 0 || row_count <= 0 {return 0, 0}
	first = max(0, int(state.scroll.y/row_height)-overscan)
	visible := int(viewport_height/row_height)+2+overscan*2
	one_past_last = min(row_count, first+visible)
	return
}

virtual_list_begin :: proc(
	frame: ^ui.Frame,
	label_string: string,
	layout: ui.Layout,
	style: ui.Style,
	row_count: int,
	row_height: f32,
	overscan: int = 1,
) -> Virtual_List {
	list_layout := layout
	list_layout.flow = .Overlay
	list_layout.main_align = .End
	result := scroll_area_begin(frame, label_string, list_layout, style)
	state := ui.get_state(frame.ui, result.key)
	viewport_height := state.last_rect.h
	if viewport_height <= 0 && layout.height.kind == .Points {
		viewport_height = layout.height.value
	}
	first, one_past_last := 0, row_count
	if viewport_height > 0 {
		first, one_past_last = visible_row_range(
			state,
			row_height,
			viewport_height,
			row_count,
			overscan,
		)
	}
	content := ui.box_from_declarations(frame, "virtual list content", {})
	content.layout = {
		width = ui.percent(1),
		height = ui.points(max(f32(0), row_height*f32(row_count))),
		flow = .Column,
		cross_align = .Stretch,
	}
	_ = ui.box_begin(frame, content)
	if first > 0 {
		_ = spacer(frame, "virtual list leading space", {
			width = ui.percent(1),
			height = ui.points(row_height*f32(first)),
		})
	}
	return {
		key = result.key,
		first = first,
		one_past_last = one_past_last,
		row_count = row_count,
		row_height = row_height,
	}
}

virtual_list_end :: proc(frame: ^ui.Frame, list: Virtual_List) {
	remaining_rows := max(0, list.row_count-list.one_past_last)
	if remaining_rows > 0 {
		_ = spacer(frame, "virtual list trailing space", {
			width = ui.percent(1),
			height = ui.points(list.row_height*f32(remaining_rows)),
		})
	}
	ui.box_end(frame)
	scroll_area_end(frame)
}
