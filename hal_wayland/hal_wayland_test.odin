package hal_wayland

import "core:testing"
import draw "ui_framework:draw"

@(test)
canonical_metrics_test :: proc(t: ^testing.T) {
	testing.expect_value(t, METRICS.header_height, f32(38))
	testing.expect_value(t, METRICS.window_control, f32(30))
	testing.expect_value(t, METRICS.window_stride, f32(38))
	testing.expect_value(t, METRICS.panel_header, f32(34))
	testing.expect_value(t, METRICS.accent_edge, f32(4))
	testing.expect_value(t, METRICS.base_font, f32(10.5))
}

@(test)
canonical_geometry_test :: proc(t: ^testing.T) {
	testing.expect_value(t, header_rect(560, 486).y, f32(448))
	testing.expect_value(t, window_control_rect(3, 486).x, f32(114))
	testing.expect_value(t, window_icon_rect(0, 486).x, f32(5))
	testing.expect_value(t, title_rect(560, 486).x, f32(160))
	testing.expect_value(t, left_accent_rect({8, 9, 100, 30}).w, f32(4))
}

@(test)
action_bar_layout_uses_one_row_when_minimum_widths_fit :: proc(t: ^testing.T) {
	items := [3]Action_Bar_Item{{50, 1}, {60, 1}, {70, 2}}
	rects: [3]draw.Rect
	result := action_bar_layout(
		{
			bounds = {10, 20, 216, 60},
			row_height = 28,
			item_gap = 4,
			section_gap = 12,
			row_gap = 6,
		},
		items[:],
		rects[:],
	)
	testing.expect(t, result.fits)
	testing.expect_value(t, result.row_count, 1)
	testing.expect_value(t, result.required_width, f32(196))
	testing.expect_value(t, result.required_height, f32(28))
	testing.expect_value(t, rects[0].y, f32(20))
	testing.expect_value(t, rects[2].x+rects[2].w, f32(226))
}

@(test)
action_bar_layout_wraps_even_items_into_equal_rows :: proc(t: ^testing.T) {
	items := [4]Action_Bar_Item{{70, 1}, {70, 1}, {70, 2}, {70, 2}}
	rects: [4]draw.Rect
	result := action_bar_layout(
		{bounds={0, 8, 150, 62}, row_height=28, item_gap=4, section_gap=12, row_gap=6},
		items[:],
		rects[:],
	)
	testing.expect(t, result.fits)
	testing.expect_value(t, result.row_count, 2)
	testing.expect_value(t, result.first_row_count, 2)
	testing.expect_value(t, result.required_height, f32(62))
	testing.expect_value(t, rects[0].y, f32(42))
	testing.expect_value(t, rects[2].y, f32(8))
}

@(test)
action_bar_layout_puts_the_larger_half_of_an_odd_count_on_top :: proc(t: ^testing.T) {
	items := [5]Action_Bar_Item{{60, 1}, {60, 1}, {60, 1}, {60, 2}, {60, 2}}
	rects: [5]draw.Rect
	result := action_bar_layout(
		{bounds={0, 0, 190, 60}, row_height=28, item_gap=4, section_gap=12, row_gap=4},
		items[:],
		rects[:],
	)
	testing.expect(t, result.fits)
	testing.expect_value(t, result.first_row_count, 3)
	testing.expect(t, rects[0].y > rects[3].y)
	testing.expect_value(t, rects[4].x+rects[4].w, f32(190))
}

@(test)
action_bar_layout_reports_two_row_minimum_that_does_not_fit :: proc(t: ^testing.T) {
	items := [3]Action_Bar_Item{{100, 1}, {100, 1}, {100, 2}}
	rects: [3]draw.Rect
	result := action_bar_layout(
		{bounds={0, 0, 150, 60}, row_height=28, item_gap=4, section_gap=12, row_gap=4},
		items[:],
		rects[:],
	)
	testing.expect(t, !result.fits)
	testing.expect_value(t, result.row_count, 2)
	testing.expect_value(t, result.required_width, f32(204))
}

@(test)
action_bar_layout_handles_empty_and_single_item_inputs :: proc(t: ^testing.T) {
	no_items: []Action_Bar_Item
	no_rects: []draw.Rect
	empty := action_bar_layout(
		{bounds={0, 0, 100, 28}, row_height=28, item_gap=4, section_gap=12, row_gap=4},
		no_items,
		no_rects,
	)
	testing.expect(t, empty.fits)
	testing.expect_value(t, empty.row_count, 0)

	item := [1]Action_Bar_Item{{120, 1}}
	rect: [1]draw.Rect
	single := action_bar_layout(
		{bounds={0, 0, 100, 28}, row_height=28, item_gap=4, section_gap=12, row_gap=4},
		item[:],
		rect[:],
	)
	testing.expect(t, !single.fits)
	testing.expect_value(t, single.row_count, 1)
	testing.expect_value(t, single.required_width, f32(120))
}

@(test)
canonical_palette_and_state_test :: proc(t: ^testing.T) {
	dark := palette(.HW_Dark)
	light := palette(.HW_Light)
	testing.expect_value(t, dark.canvas, color(10, 11, 10))
	testing.expect_value(t, dark.field, dark.raised)
	testing.expect_value(t, light.header, color(232, 227, 209))
	testing.expect_value(t, accent(dark, .Alternate), color(120, 150, 179))
	selected := control_style(dark, .Selected, .Primary)
	testing.expect_value(t, selected.border, dark.primary)
	testing.expect_value(t, selected.corner_radius, f32(0))
	disabled := control_style(dark, .Disabled)
	testing.expect(t, disabled.opacity < 1)
}
