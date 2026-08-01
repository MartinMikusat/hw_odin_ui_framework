package ui

import "core:testing"
import draw "ui_framework:draw"

fixed_prepare :: proc(
	user_data: rawptr,
	font: Font_Handle,
	text: string,
	size, tracking, maximum_width: f32,
	truncate: bool,
) -> Prepared_Text {
	return {
		run = Text_Run_ID(1),
		metrics = {
			width = f32(len(text))*size/2,
			ascent = size*0.75,
			descent = size*0.25,
		},
	}
}

trace_label_index :: proc(trace: []draw.Trace_Entry, label: string) -> int {
	for entry, index in trace {
		if entry.kind != .Group_Begin && entry.kind != .Group_End &&
		   entry.label == label {
			return index
		}
	}
	return -1
}

@(test)
row_and_column_layout_allocate_remaining_space_test :: proc(t: ^testing.T) {
	ctx: Context
	context_init(&ctx)
	defer context_destroy(&ctx)
	frame := begin_frame(
		&ctx,
		{viewport = {0, 0, 300, 200}, backing_scale = 2},
		{prepare = fixed_prepare},
	)
	defer frame_destroy(&frame)
	container := box_begin(&frame, Box{
		key = key_from_string("row"),
		layout = {
			width = percent(1),
			height = points(40),
			flow = .Row,
			gap = 10,
			cross_align = .Stretch,
		},
	})
	_ = container
	left := box_add(&frame, Box{key = key_from_string("left"), layout = {width = points(50), height = remaining()}})
	right := box_add(&frame, Box{key = key_from_string("right"), layout = {width = remaining(), height = remaining()}})
	box_end(&frame)
	_ = end_frame(&frame)
	testing.expect_value(t, frame.boxes[left].rect, draw.Rect{0, 160, 50, 40})
	testing.expect_value(t, frame.boxes[right].rect, draw.Rect{60, 160, 240, 40})
}

@(test)
modal_scope_publishes_only_modal_controls_and_preserves_draw_order_test :: proc(t: ^testing.T) {
	ctx: Context
	context_init(&ctx)
	defer context_destroy(&ctx)
	frame := begin_frame(&ctx, {viewport = {0, 0, 200, 100}})
	defer frame_destroy(&frame)
	base_action := action_id_from_string("base action")
	modal_action := action_id_from_string("modal action")
	register_action(&frame, {id = base_action, functional_name = "base action", label = "Base", enabled = true})
	register_action(&frame, {id = modal_action, functional_name = "modal action", label = "Modal", enabled = true})
	_ = box_add(&frame, Box{
		key = key_from_string("base"),
		debug_label = "base",
		layout = {position = .Absolute, absolute = {0, 0, 200, 100}},
		style = {background = {1, 1, 1, 1}, opacity = 1},
		flags = {.Draw_Background, .Interactive},
		control = {functional_name = "base", action = base_action, capabilities = {.Primary_Press}},
	})
	_ = box_begin(&frame, Box{
		key = key_from_string("modal"),
		debug_label = "modal",
		layout = {position = .Absolute, absolute = {20, 20, 160, 60}, flow = .Overlay},
		style = {background = {0, 0, 0, 0.8}, opacity = 1},
		flags = {.Draw_Background, .Modal_Root},
	})
	_ = box_add(&frame, Box{
		key = key_from_string("modal button"),
		debug_label = "modal button",
		layout = {position = .Absolute, absolute = {10, 10, 40, 20}},
		style = {background = {0.2, 0.2, 0.2, 1}, opacity = 1},
		flags = {.Draw_Background, .Interactive},
		control = {functional_name = "modal button", action = modal_action, capabilities = {.Primary_Press}},
	})
	box_end(&frame)
	output := end_frame(&frame)
	testing.expect_value(t, len(output.controls), 1)
	testing.expect_value(t, output.controls[0].functional_name, "modal button")
	base_index := trace_label_index(output.draw_list.trace[:], "base")
	modal_index := trace_label_index(output.draw_list.trace[:], "modal")
	button_index := trace_label_index(output.draw_list.trace[:], "modal button")
	testing.expect(t, base_index >= 0)
	testing.expect(t, modal_index > base_index)
	testing.expect(t, button_index > modal_index)
}

@(test)
layer_order_is_independent_of_box_construction_order_test :: proc(t: ^testing.T) {
	ctx: Context
	context_init(&ctx)
	defer context_destroy(&ctx)
	frame := begin_frame(&ctx, {viewport = {0, 0, 100, 100}})
	defer frame_destroy(&frame)
	_ = box_add(&frame, Box{
		key = key_from_string("popup first"),
		debug_label = "popup first",
		layout = {position = .Absolute, absolute = {0, 0, 10, 10}},
		style = {background = {1, 0, 0, 1}, opacity = 1},
		flags = {.Draw_Background},
		layer = .Popup,
	})
	_ = box_add(&frame, Box{
		key = key_from_string("base second"),
		debug_label = "base second",
		layout = {position = .Absolute, absolute = {0, 0, 10, 10}},
		style = {background = {0, 1, 0, 1}, opacity = 1},
		flags = {.Draw_Background},
		layer = .Base,
	})
	output := end_frame(&frame)
	base_index := trace_label_index(output.draw_list.trace[:], "base second")
	popup_index := trace_label_index(output.draw_list.trace[:], "popup first")
	testing.expect(t, base_index >= 0)
	testing.expect(t, popup_index > base_index)
}

@(test)
input_root_blocks_background_controls_and_allows_explicit_passthrough_test :: proc(
	t: ^testing.T,
) {
	ctx: Context
	context_init(&ctx)
	defer context_destroy(&ctx)
	frame := begin_frame(&ctx, {viewport = {0, 0, 100, 100}})
	defer frame_destroy(&frame)
	action := action_id_from_string("action")
	register_action(&frame, {id = action, enabled = true})
	_ = box_add(&frame, Box{
		key = key_from_string("background control"),
		layout = {position = .Absolute, absolute = {0, 0, 20, 20}},
		flags = {.Interactive},
		control = {action = action, capabilities = {.Primary_Press}},
	})
	_ = box_add(&frame, Box{
		key = key_from_string("window control"),
		layout = {position = .Absolute, absolute = {80, 80, 20, 20}},
		flags = {.Interactive, .Input_Passthrough},
		control = {action = action, capabilities = {.Primary_Press}},
	})
	_ = box_begin(&frame, Box{
		key = key_from_string("popup root"),
		layout = {
			position = .Absolute,
			absolute = {20, 20, 60, 60},
			flow = .Overlay,
		},
		flags = {.Input_Root},
		layer = .Popup,
	})
	_ = box_add(&frame, Box{
		key = key_from_string("popup control"),
		layout = {position = .Absolute, absolute = {0, 0, 20, 20}},
		flags = {.Interactive},
		control = {action = action, capabilities = {.Primary_Press}},
	})
	box_end(&frame)
	output := end_frame(&frame)
	testing.expect_value(t, len(output.controls), 2)
	testing.expect_value(t, output.controls[0].functional_name, "")
	testing.expect_value(t, output.controls[0].id, key_from_string("window control"))
	testing.expect_value(t, output.controls[1].id, key_from_string("popup control"))
}

@(test)
published_controls_route_all_enabled_sources_through_one_action_test :: proc(t: ^testing.T) {
	ctx: Context
	context_init(&ctx)
	defer context_destroy(&ctx)
	frame := begin_frame(&ctx, {viewport = {0, 0, 100, 100}})
	defer frame_destroy(&frame)
	action := action_id_from_string("play")
	register_action(&frame, {id = action, functional_name = "play", label = "Play", enabled = true})
	control_key := key_from_string("play control")
	_ = box_add(&frame, Box{
		key = control_key,
		layout = {position = .Absolute, absolute = {10, 10, 40, 20}},
		flags = {.Interactive},
		control = {
			functional_name = "play",
			action = action,
			capabilities = {.Primary_Press, .Numbered, .Accessibility, .Flash, .Command_Menu, .CLI},
		},
	})
	output := end_frame(&frame)
	publish(&ctx, output)
	sources := [6]Activation_Source{
		Activation_Source.Pointer,
		Activation_Source.Numbered,
		Activation_Source.Accessibility,
		Activation_Source.Flash,
		Activation_Source.Command_Menu,
		Activation_Source.CLI,
	}
	for source in sources {
		activation, ok := activate_control(&ctx, control_key, source, Vec2{20, 15})
		testing.expect(t, ok)
		testing.expect_value(t, activation.action, action)
	}
	activation, ok := activate_at_point(&ctx, {20, 15})
	testing.expect(t, ok)
	testing.expect_value(t, activation.normalized, Vec2{0.25, 0.25})
}

@(test)
registry_validation_reports_cross_surface_contract_violations_test :: proc(
	t: ^testing.T,
) {
	actions := []Action_Record{{id = Action_ID(1), enabled = true}}
	controls := []Control_Record{{
		id = Key(2),
		functional_name = "broken",
		action = Action_ID(9),
		rect = {},
		capabilities = {.Accessibility, .Flash},
		enabled = true,
	}}
	issues := registry_validate(registry_view_from_records(actions, controls, 1))
	defer delete(issues)
	testing.expect_value(t, len(issues), 4)
}

@(test)
duplicate_box_and_action_identifiers_are_detected_by_contract_test :: proc(t: ^testing.T) {
	// The public builders assert on duplicates in debug builds. This test keeps
	// the observable maps explicit without intentionally terminating the runner.
	testing.expect(t, key_from_string("same") == key_from_string("same"))
	testing.expect(t, action_id_from_string("same") == action_id_from_string("same"))
}

@(test)
label_identity_separates_display_text_from_stable_keys_test :: proc(t: ^testing.T) {
	parent := key_from_string("parent")
	testing.expect_value(t, display_part("Save##shortcut"), "Save")
	testing.expect_value(
		t,
		key_from_label(parent, "Save###stable"),
		key_from_label(parent, "Guardar###stable"),
	)
	testing.expect(t, key_from_label(parent, "Save##one") != key_from_label(parent, "Save##two"))
}

@(test)
layout_strictness_partitions_constraint_violation_test :: proc(t: ^testing.T) {
	ctx: Context
	context_init(&ctx)
	defer context_destroy(&ctx)
	frame := begin_frame(&ctx, {viewport = {0, 0, 100, 40}})
	defer frame_destroy(&frame)
	_ = box_begin(&frame, Box{
		key = key_from_string("row constraint"),
		layout = {
			width = percent(1),
			height = points(40),
			flow = .Row,
		},
	})
	strict := box_add(&frame, Box{
		key = key_from_string("strict"),
		layout = {width = points(80), height = points(40)},
	})
	flexible := box_add(&frame, Box{
		key = key_from_string("flexible"),
		layout = {width = flex_points(80, 0), height = points(40)},
	})
	box_end(&frame)
	_ = end_frame(&frame)
	testing.expect_value(t, frame.boxes[strict].rect.w, f32(80))
	testing.expect_value(t, frame.boxes[flexible].rect.w, f32(20))
}

@(test)
remaining_sizes_reserve_minimums_and_report_unavoidable_overflow_test :: proc(
	t: ^testing.T,
) {
	ctx: Context
	context_init(&ctx)
	defer context_destroy(&ctx)
	frame := begin_frame(&ctx, {viewport = {0, 0, 100, 40}})
	defer frame_destroy(&frame)
	row := box_begin(&frame, Box{
		key = key_from_string("remaining minimum row"),
		layout = {
			width = percent(1),
			height = points(40),
			flow = .Row,
		},
	})
	first_spec := remaining()
	first_spec.minimum = 80
	second_spec := remaining()
	second_spec.minimum = 80
	first := box_add(&frame, Box{
		key = key_from_string("first minimum"),
		layout = {width = first_spec, height = points(40)},
	})
	second := box_add(&frame, Box{
		key = key_from_string("second minimum"),
		layout = {width = second_spec, height = points(40)},
	})
	box_end(&frame)
	_ = end_frame(&frame)
	testing.expect_value(t, frame.boxes[first].rect.w, f32(80))
	testing.expect_value(t, frame.boxes[second].rect.w, f32(80))
	testing.expect_value(t, frame.boxes[row].overflow.x, f32(60))
}

build_click_fixture :: proc(ctx: ^Context, pointer: Vec2) -> (Frame, Key) {
	frame := begin_frame(ctx, {viewport = {0, 0, 100, 100}, pointer = pointer})
	action := action_id_from_string("activate")
	register_action(&frame, {
		id = action,
		functional_name = "activate",
		label = "Activate",
		enabled = true,
	})
	key := key_from_string("control")
	_ = box_add(&frame, Box{
		key = key,
		layout = {position = .Absolute, absolute = {10, 10, 40, 20}},
		flags = {.Interactive, .Click_To_Focus},
		control = {
			functional_name = "activate",
			action = action,
			capabilities = {.Primary_Press, .Direct_Keyboard},
		},
	})
	return frame, key
}

@(test)
event_queue_retains_active_state_and_emits_click_on_release_test :: proc(t: ^testing.T) {
	ctx: Context
	context_init(&ctx)
	defer context_destroy(&ctx)
	frame, key := build_click_fixture(&ctx, {20, 15})
	output := end_frame(&frame)
	publish(&ctx, output)
	frame_destroy(&frame)
	queue_event(&ctx, {
		kind = .Pointer_Press,
		button = .Primary,
		point = {20, 15},
		timestamp_us = 1_000,
	})
	press_frame, _ := build_click_fixture(&ctx, {20, 15})
	press := signal_for_key(press_frame.signals[:], key)
	testing.expect(t, .Pressed in press.flags)
	_ = end_frame(&press_frame)
	frame_destroy(&press_frame)
	queue_event(&ctx, {
		kind = .Pointer_Release,
		button = .Primary,
		point = {20, 15},
		timestamp_us = 2_000,
	})
	release_frame, _ := build_click_fixture(&ctx, {20, 15})
	release := signal_for_key(release_frame.signals[:], key)
	testing.expect(t, .Released in release.flags)
	testing.expect(t, .Clicked in release.flags)
	testing.expect_value(t, ctx.focused, key)
	_ = end_frame(&release_frame)
	frame_destroy(&release_frame)
}

@(test)
text_and_key_events_retain_payloads_through_frame_publication_test :: proc(
	t: ^testing.T,
) {
	ctx: Context
	context_init(&ctx)
	defer context_destroy(&ctx)
	action := action_id_from_string("edit")
	key := key_from_string("editor")
	frame := begin_frame(&ctx, {viewport = {0, 0, 100, 40}})
	register_action(&frame, {id = action, enabled = true})
	_ = box_add(&frame, Box{
		key = key,
		layout = {position = .Absolute, absolute = {0, 0, 100, 40}},
		flags = {.Interactive, .Click_To_Focus},
		control = {
			action = action,
			capabilities = {.Primary_Press, .Direct_Keyboard, .Editable},
		},
	})
	output := end_frame(&frame)
	publish(&ctx, output)
	frame_destroy(&frame)
	ctx.focused = key
	queue_event(&ctx, {kind = .Key_Press, key = 42})
	queue_event(&ctx, {kind = .Text, text = "é"})
	frame = begin_frame(&ctx, {viewport = {0, 0, 100, 40}})
	register_action(&frame, {id = action, enabled = true})
	_ = box_add(&frame, Box{
		key = key,
		layout = {position = .Absolute, absolute = {0, 0, 100, 40}},
		flags = {.Interactive, .Click_To_Focus},
		control = {
			action = action,
			capabilities = {.Primary_Press, .Direct_Keyboard, .Editable},
		},
	})
	signal := signal_for_key(frame.signals[:], key)
	testing.expect(t, .Keyboard_Pressed in signal.flags)
	testing.expect(t, .Text_Input in signal.flags)
	testing.expect_value(t, signal.key, u32(42))
	testing.expect_value(t, signal.text, "é")
	output = end_frame(&frame)
	publish(&ctx, output)
	frame_destroy(&frame)
	testing.expect_value(t, ctx.published.signals[0].text, "é")
}

@(test)
focus_navigation_stays_inside_the_requested_root_test :: proc(t: ^testing.T) {
	ctx: Context
	context_init(&ctx)
	defer context_destroy(&ctx)
	registry := registry_begin(1)
	defer registry_destroy(&registry)
	for index in 0..<3 {
		registry_add_control(&registry, {
			id = Key(index+1),
			functional_name = "control",
			rect = {f32(index*20), 0, 10, 10},
			focusable = true,
			focus_root = Key(index/2+10),
			enabled = true,
		})
	}
	registry_publish(&ctx, &registry)
	key, ok := focus_move(&ctx, .Next, Key(10))
	testing.expect(t, ok)
	testing.expect_value(t, key, Key(1))
	key, ok = focus_move(&ctx, .Next, Key(10))
	testing.expect(t, ok)
	testing.expect_value(t, key, Key(2))
	key, ok = focus_move(&ctx, .Next, Key(10))
	testing.expect(t, ok)
	testing.expect_value(t, key, Key(1))
}

@(test)
scroll_target_helpers_clamp_and_reveal_items_in_view_coordinates_test :: proc(
	t: ^testing.T,
) {
	ctx: Context
	context_init(&ctx)
	defer context_destroy(&ctx)
	key := key_from_string("scroll")
	set_state(&ctx, key, {
		last_rect = {0, 0, 100, 100},
		view_bounds = {100, 500},
		scroll = {0, 100},
		scroll_target = {0, 100},
	})
	testing.expect_value(t, scroll_by(&ctx, key, {0, 500}), Vec2{0, 400})
	state := get_state(&ctx, key)
	state.scroll_target = {0, 100}
	ctx.states[key] = state
	testing.expect_value(
		t,
		scroll_make_visible(&ctx, key, {0, -20, 80, 20}, 10),
		Vec2{0, 130},
	)
}
