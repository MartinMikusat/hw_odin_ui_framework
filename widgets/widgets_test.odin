package widgets

import "core:testing"
import ui "ui_framework:core"

@(test)
button_uses_one_box_for_drawing_and_all_interaction_surfaces_test :: proc(t: ^testing.T) {
	ctx: ui.Context
	ui.context_init(&ctx)
	defer ui.context_destroy(&ctx)
	frame := ui.begin_frame(&ctx, {viewport = {0, 0, 200, 100}})
	defer ui.frame_destroy(&frame)
	action := ui.action_id_from_string("save")
	ui.register_action(&frame, {
		id = action,
		functional_name = "save",
		label = "Save",
		enabled = true,
	})
	result := button(&frame, "Save###save", action, {
		layout = {
			position = .Absolute,
			absolute = {20, 20, 80, 28},
		},
		style = {
			background = {0.1, 0.1, 0.1, 1},
			text = {1, 1, 1, 1},
			border = {0.6, 0.4, 0.2, 1},
			border_thickness = 1,
			opacity = 1,
		},
	})
	output := ui.end_frame(&frame)
	testing.expect_value(t, len(output.controls), 1)
	testing.expect_value(t, output.controls[0].id, result.key)
	testing.expect(t, .Accessibility in output.controls[0].capabilities)
	testing.expect(t, .Flash in output.controls[0].capabilities)
	testing.expect_value(t, output.draw_list.trace[0].label, "Save")
}

@(test)
virtual_rows_include_overscan_and_clamp_to_the_data_set_test :: proc(t: ^testing.T) {
	first, last := visible_row_range({scroll = {0, 95}}, 20, 100, 12)
	testing.expect_value(t, first, 3)
	testing.expect_value(t, last, 12)
}
