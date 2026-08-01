package widgets


import "core:fmt"
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
	found_draw := false
	for entry in output.draw_list.trace {
		if entry.label == "Save" {
			found_draw = true
			break
		}
	}
	testing.expect(t, found_draw)
}

@(test)
virtual_rows_include_overscan_and_clamp_to_the_data_set_test :: proc(t: ^testing.T) {
	first, last := visible_row_range({scroll = {0, 95}}, 20, 100, 12)
	testing.expect_value(t, first, 3)
	testing.expect_value(t, last, 12)
}

@(test)
virtual_list_emits_only_visible_rows_but_retains_full_scroll_extent_test :: proc(
	t: ^testing.T,
) {
	ctx: ui.Context
	ui.context_init(&ctx)
	defer ui.context_destroy(&ctx)
	list_key := ui.key_from_label(ui.key_from_string("framework root"), "rows")
	state := ui.get_state(&ctx, list_key)
	state.scroll = {0, 400}
	state.scroll_target = state.scroll
	ui.set_state(&ctx, list_key, state)
	frame := ui.begin_frame(&ctx, {viewport = {0, 0, 200, 100}})
	defer ui.frame_destroy(&frame)
	list := virtual_list_begin(
		&frame,
		"rows",
		{width = ui.points(200), height = ui.points(100)},
		{opacity = 1},
		100,
		20,
	)
	testing.expect(t, list.first > 0)
	testing.expect(t, list.one_past_last-list.first < 100)
	for row in list.first..<list.one_past_last {
		_ = spacer(&frame, fmt.tprintf("row %d", row), {
			width = ui.percent(1),
			height = ui.points(20),
		})
	}
	virtual_list_end(&frame, list)
	_ = ui.end_frame(&frame)
	content := &frame.boxes[2]
	testing.expect_value(t, content.rect.h, f32(2_000))
}
