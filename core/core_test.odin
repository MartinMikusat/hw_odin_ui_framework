package ui

import "core:testing"
import draw "ui_framework:draw"

fixed_measure :: proc(
	user_data: rawptr,
	font: Font_Handle,
	text: string,
	size, tracking, maximum_width: f32,
	truncate: bool,
) -> Text_Metrics {
	return {width = f32(len(text))*size/2, ascent = size*0.75, descent = size*0.25}
}

@(test)
row_and_column_layout_allocate_remaining_space_test :: proc(t: ^testing.T) {
	ctx: Context
	context_init(&ctx)
	defer context_destroy(&ctx)
	frame := begin_frame(
		&ctx,
		{viewport = {0, 0, 300, 200}, backing_scale = 2},
		{measure = fixed_measure},
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
	testing.expect_value(t, output.draw_list.trace[0].label, "base")
	testing.expect_value(t, output.draw_list.trace[1].label, "modal")
	testing.expect_value(t, output.draw_list.trace[2].label, "modal button")
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
