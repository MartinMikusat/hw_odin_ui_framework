package hal_wayland

import ui "ui_framework:core"
import draw "ui_framework:draw"

Theme_ID :: enum {
	HW_Light,
	HW_Dark,
}

Accent_Role :: enum {
	Primary,
	Alternate,
	Focus,
	Positive,
	Neutral,
	Destructive,
}

Control_State :: enum {
	Idle,
	Hovered,
	Pressed,
	Selected,
	Focused,
	Disabled,
}

Palette :: struct {
	canvas, header, surface, raised, field: draw.Color,
	border, rule, row, row_hover: draw.Color,
	backdrop, modal: draw.Color,
	text, text_soft, muted, dim: draw.Color,
	primary, alternate, focus, positive, neutral, destructive: draw.Color,
}

Metrics :: struct {
	header_height:      f32,
	window_control:     f32,
	window_stride:      f32,
	window_icon:        f32,
	window_icon_inset:  f32,
	title_x:            f32,
	margin:             f32,
	gap:                f32,
	panel_header:       f32,
	control:            f32,
	dense_control:      f32,
	row:                f32,
	settings_row:       f32,
	accent_edge:        f32,
	border:             f32,
	base_font:          f32,
}

Action_Bar_Item :: struct {
	minimum_width: f32,
	section:       int,
}

Action_Bar_Config :: struct {
	bounds:      draw.Rect,
	row_height:  f32,
	item_gap:    f32,
	section_gap: f32,
	row_gap:     f32,
}

Action_Bar_Result :: struct {
	row_count:       int,
	first_row_count: int,
	required_width:  f32,
	required_height: f32,
	fits:            bool,
}

METRICS :: Metrics{
	header_height = 38,
	window_control = 30,
	window_stride = 38,
	window_icon = 20,
	window_icon_inset = 5,
	title_x = 160,
	margin = 6,
	gap = 4,
	panel_header = 34,
	control = 30,
	dense_control = 24,
	row = 34,
	settings_row = 36,
	accent_edge = 4,
	border = 1,
	base_font = 10.5,
}

color :: proc(r, g, b: u8, alpha: f32 = 1) -> draw.Color {
	return {f32(r)/255, f32(g)/255, f32(b)/255, alpha}
}

palette :: proc(
	id: Theme_ID,
	increase_contrast := false,
	reduce_transparency := false,
) -> Palette {
	result: Palette
	if id == .HW_Dark {
		result = {
			canvas = color(10, 11, 10), header = color(8, 9, 8),
			surface = color(14, 15, 14), raised = color(17, 18, 17),
			field = color(17, 18, 17), border = color(120, 125, 117),
			rule = color(17, 18, 17), row = color(14, 15, 14, 0.96),
			row_hover = color(10, 11, 10), backdrop = color(5, 6, 5, 0.80),
			modal = color(8, 9, 8), text = color(247, 242, 224),
			text_soft = color(173, 171, 158), muted = color(120, 125, 117),
			dim = color(120, 125, 117), primary = color(178, 125, 87),
			alternate = color(120, 150, 179), focus = color(125, 135, 105),
			positive = color(125, 135, 105), neutral = color(174, 147, 114),
			destructive = color(127, 75, 48),
		}
	} else {
		result = {
			canvas = color(204, 199, 184), header = color(232, 227, 209),
			surface = color(224, 219, 201), raised = color(217, 212, 194),
			field = color(212, 207, 189), border = color(122, 117, 107),
			rule = color(217, 212, 194), row = color(224, 219, 201, 0.96),
			row_hover = color(204, 199, 184), backdrop = color(5, 6, 5, 0.80),
			modal = color(232, 227, 209), text = color(38, 37, 40),
			text_soft = color(69, 66, 71), muted = color(122, 117, 107),
			dim = color(122, 117, 107), primary = color(127, 75, 48),
			alternate = color(54, 81, 111), focus = color(23, 49, 37),
			positive = color(23, 49, 37), neutral = color(125, 135, 105),
			destructive = color(127, 75, 48),
		}
	}
	if increase_contrast {
		if id == .HW_Dark {
			result.canvas = color(0, 0, 0)
			result.header = color(4, 4, 4)
			result.text = color(255, 255, 255)
			result.text_soft = color(220, 220, 208)
			result.muted = color(180, 180, 170)
			result.border = result.muted
			result.focus = color(170, 190, 130)
		} else {
			result.canvas = color(184, 180, 166)
			result.header = color(252, 248, 230)
			result.text = color(0, 0, 0)
			result.text_soft = color(30, 28, 32)
			result.muted = color(72, 68, 62)
			result.border = result.muted
			result.focus = color(10, 62, 36)
		}
	}
	if reduce_transparency {
		result.row[3] = 1
		result.backdrop[3] = 1
	}
	return result
}

accent :: proc(theme: Palette, role: Accent_Role) -> draw.Color {
	switch role {
	case .Primary: return theme.primary
	case .Alternate: return theme.alternate
	case .Focus: return theme.focus
	case .Positive: return theme.positive
	case .Neutral: return theme.neutral
	case .Destructive: return theme.destructive
	}
	return theme.primary
}

header_rect :: proc(width, height: f32) -> draw.Rect {
	return {0, height-METRICS.header_height, width, METRICS.header_height}
}

window_control_rect :: proc(index: int, height: f32) -> draw.Rect {
	return {METRICS.window_stride*f32(index), height-METRICS.window_control,
		METRICS.window_control, METRICS.window_control}
}

window_icon_rect :: proc(index: int, height: f32) -> draw.Rect {
	control := window_control_rect(index, height)
	return {control.x+METRICS.window_icon_inset, control.y+METRICS.window_icon_inset,
		METRICS.window_icon, METRICS.window_icon}
}

title_rect :: proc(width, height: f32, right_edge := f32(0)) -> draw.Rect {
	right := right_edge
	if right <= 0 {right = width-METRICS.margin}
	return {METRICS.title_x, height-METRICS.header_height+2,
		max(f32(0), right-METRICS.title_x-METRICS.gap), METRICS.header_height-2}
}

left_accent_rect :: proc(rect: draw.Rect) -> draw.Rect {
	return {rect.x, rect.y, min(METRICS.accent_edge, rect.w), rect.h}
}

action_bar_row_required_width :: proc(
	items: []Action_Bar_Item,
	start, count: int,
	item_gap, section_gap: f32,
) -> f32 {
	if count <= 0 {return 0}
	result: f32
	for offset in 0 ..< count {
		index := start+offset
		result += max(f32(0), items[index].minimum_width)
		if offset+1 < count {
			gap := item_gap
			if items[index].section != items[index+1].section {
				gap = section_gap
			}
			result += max(f32(0), gap)
		}
	}
	return result
}

action_bar_layout_row :: proc(
	config: Action_Bar_Config,
	items: []Action_Bar_Item,
	rects: []draw.Rect,
	start, count: int,
	y: f32,
	required_width: f32,
) {
	if count <= 0 {return}
	extra_width := max(f32(0), config.bounds.w-required_width)/f32(count)
	x := config.bounds.x
	for offset in 0 ..< count {
		index := start+offset
		width := max(f32(0), items[index].minimum_width)+extra_width
		if offset == count-1 {
			width = config.bounds.x+config.bounds.w-x
		}
		rects[index] = {x, y, width, config.row_height}
		x += width
		if offset+1 < count {
			gap := config.item_gap
			if items[index].section != items[index+1].section {
				gap = config.section_gap
			}
			x += max(f32(0), gap)
		}
	}
}

action_bar_layout :: proc(
	config: Action_Bar_Config,
	items: []Action_Bar_Item,
	rects: []draw.Rect,
) -> Action_Bar_Result {
	result := Action_Bar_Result{fits = len(items) == 0}
	if len(items) == 0 {return result}
	if len(rects) < len(items) || config.bounds.w < 0 || config.row_height <= 0 {
		return result
	}

	one_row_width := action_bar_row_required_width(
		items,
		0,
		len(items),
		config.item_gap,
		config.section_gap,
	)
	if one_row_width <= config.bounds.w {
		result = {
			row_count = 1,
			first_row_count = len(items),
			required_width = one_row_width,
			required_height = config.row_height,
			fits = true,
		}
		action_bar_layout_row(
			config,
			items,
			rects,
			0,
			len(items),
			config.bounds.y,
			one_row_width,
		)
		return result
	}
	if len(items) == 1 {
		result = {
			row_count = 1,
			first_row_count = 1,
			required_width = one_row_width,
			required_height = config.row_height,
			fits = false,
		}
		return result
	}

	first_count := (len(items)+1)/2
	second_count := len(items)-first_count
	first_width := action_bar_row_required_width(
		items,
		0,
		first_count,
		config.item_gap,
		config.section_gap,
	)
	second_width := action_bar_row_required_width(
		items,
		first_count,
		second_count,
		config.item_gap,
		config.section_gap,
	)
	result = {
		row_count = 2,
		first_row_count = first_count,
		required_width = max(first_width, second_width),
		required_height = config.row_height*2+max(f32(0), config.row_gap),
		fits = first_width <= config.bounds.w && second_width <= config.bounds.w,
	}
	if !result.fits {return result}
	action_bar_layout_row(
		config,
		items,
		rects,
		0,
		first_count,
		config.bounds.y+config.row_height+max(f32(0), config.row_gap),
		first_width,
	)
	action_bar_layout_row(
		config,
		items,
		rects,
		first_count,
		second_count,
		config.bounds.y,
		second_width,
	)
	return result
}

text_style :: proc(
	size := METRICS.base_font,
	horizontal := ui.Text_Align.Center,
	vertical := ui.Text_Align.Center,
	tracking := f32(-0.45),
) -> ui.Text_Style {
	return {font = 1, size = size, tracking = tracking,
		horizontal = horizontal, vertical = vertical}
}

panel_style :: proc(theme: Palette, raised := false) -> ui.Style {
	return {background = raised ? theme.raised : theme.surface, text = theme.text,
		opacity = 1, text_style = text_style()}
}

field_style :: proc(theme: Palette, focused := false, disabled := false) -> ui.Style {
	return {background = theme.field, border = focused ? theme.focus : theme.rule,
		text = disabled ? theme.dim : theme.text, border_thickness = focused ? METRICS.border : 0,
		opacity = disabled ? 0.62 : 1, text_style = text_style()}
}

control_style :: proc(
	theme: Palette,
	state := Control_State.Idle,
	role := Accent_Role.Primary,
) -> ui.Style {
	background := theme.raised
	border := theme.rule
	text := theme.text
	opacity: f32 = 1
	switch state {
	case .Hovered: background = theme.row_hover
	case .Pressed: background = theme.canvas
	case .Selected:
		border = accent(theme, role)
	case .Focused:
		border = theme.focus
	case .Disabled:
		background = theme.field
		text = theme.dim
		opacity = 0.62
	case .Idle:
	}
	return {background = background, border = border, text = text,
		border_thickness = (state == .Selected || state == .Focused) ? METRICS.border : 0,
		opacity = opacity, text_style = text_style()}
}
