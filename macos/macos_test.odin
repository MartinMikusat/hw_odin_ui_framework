package macos

import "core:testing"
import ui "ui_framework:core"

published_fixture :: proc(ctx: ^ui.Context) {
	ui.context_init(ctx)
	frame := ui.begin_frame(ctx, {viewport = {0, 0, 100, 100}})
	defer ui.frame_destroy(&frame)
	action := ui.action_id_from_string("save")
	ui.register_action(&frame, {
		id = action,
		functional_name = "save",
		label = "Save",
		enabled = true,
		number_code = {1, 2, 2},
	})
	_ = ui.box_add(&frame, ui.Box{
		key = ui.key_from_string("save button"),
		layout = {position = .Absolute, absolute = {10, 10, 30, 20}},
		flags = {.Interactive},
		control = {
			functional_name = "save",
			accessibility_label = "Save changes",
			accessibility_role = .Button,
			flash_label = "save",
			action = action,
			capabilities = {.Primary_Press, .Numbered, .Accessibility, .Flash, .CLI},
		},
	})
	output := ui.end_frame(&frame)
	ui.publish(ctx, output)
}

@(test)
all_discrete_adapters_resolve_the_same_action_test :: proc(t: ^testing.T) {
	ctx: ui.Context
	published_fixture(&ctx)
	defer ui.context_destroy(&ctx)
	pointer, pointer_ok := pointer_activation(&ctx, .Primary_Press, {20, 15})
	numbered, numbered_ok := numbered_activation(&ctx, 1, 2, 2)
	cli, cli_ok := functional_activation(&ctx, "save")
	testing.expect(t, pointer_ok && numbered_ok && cli_ok)
	testing.expect_value(t, pointer.action, numbered.action)
	testing.expect_value(t, numbered.action, cli.action)
	elements := accessibility_elements(&ctx)
	defer accessibility_elements_destroy(elements)
	targets := flash_targets(&ctx)
	defer flash_targets_destroy(targets)
	testing.expect_value(t, len(elements), 1)
	testing.expect_value(t, elements[0].role, "AXButton")
	testing.expect_value(t, len(targets), 1)
	testing.expect_value(t, targets[0].label, "save")
}
