package draw

import "core:testing"
import "core:math"

@(test)
submission_order_and_adjacent_batching_test :: proc(t: ^testing.T) {
	list: List
	list_init(&list)
	defer list_destroy(&list)

	solid(&list, {0, 0, 10, 10}, {1, 0, 0, 1}, label = "background")
	solid(&list, {1, 1, 8, 8}, {0, 1, 0, 1}, label = "panel")
	image(&list, Texture_Handle(4), {2, 2, 4, 4}, {0, 0, 1, 1}, label = "text")
	solid(&list, {0, 0, 10, 10}, {0, 0, 0, 0.8}, label = "backdrop")
	image(&list, Texture_Handle(4), {3, 3, 2, 2}, {0, 0, 1, 1}, label = "modal text")

	testing.expect_value(t, len(list.batches), 4)
	testing.expect_value(t, len(list.batches[0].instances), 2)
	testing.expect_value(t, list.trace[0].label, "background")
	testing.expect_value(t, list.trace[2].label, "text")
	testing.expect_value(t, list.trace[3].label, "backdrop")
	testing.expect_value(t, list.trace[4].label, "modal text")
}

@(test)
solid_defaults_to_round_and_keeps_squircle_in_the_same_batch_test :: proc(t: ^testing.T) {
	list: List
	list_init(&list)
	defer list_destroy(&list)

	solid(&list, {0, 0, 20, 20}, {1, 1, 1, 1}, 6)
	solid(
		&list,
		{24, 0, 20, 20},
		{1, 1, 1, 1},
		6,
		corner_shape = .Squircle,
	)

	testing.expect_value(t, len(list.batches), 1)
	testing.expect_value(t, len(list.batches[0].instances), 2)
	testing.expect_value(t, list.batches[0].instances[0].corner_shape, Corner_Shape.Round)
	testing.expect_value(t, list.batches[0].instances[1].corner_shape, Corner_Shape.Squircle)
}

@(test)
y_band_records_window_and_border_test :: proc(t: ^testing.T) {
	list: List
	list_init(&list)
	defer list_destroy(&list)

	y_band(
		&list,
		{2, 3, 52, 32},
		{1, 1, 1, 0.8},
		16,
		4,
		0.5,
		1,
		0.08,
		corner_shape = .Round,
		label = "glass inner highlight",
	)

	testing.expect_value(t, len(list.batches), 1)
	instance := list.batches[0].instances[0]
	testing.expect_value(t, instance.texture_mode, Texture_Mode.Y_Band)
	testing.expect_value(t, instance.effect_offset, [2]f32{0.5, 1})
	testing.expect_value(t, instance.src.x, f32(0.08))
	testing.expect_value(t, instance.border_thickness, f32(4))
	testing.expect_value(t, instance.corner_shape, Corner_Shape.Round)
	testing.expect_value(t, list.trace[0].label, "glass inner highlight")
}

@(test)
y_ramp_records_three_stops_and_border_test :: proc(t: ^testing.T) {
	list: List
	list_init(&list)
	defer list_destroy(&list)

	y_ramp(
		&list,
		{2, 3, 52, 32},
		{1, 0, 0, 0.8},
		{0, 0, 0, 0.6},
		{1, 1, 1, 0.9},
		16,
		4,
		0.33,
		0.5,
		label = "glass inner rim",
	)

	testing.expect_value(t, len(list.batches), 1)
	instance := list.batches[0].instances[0]
	testing.expect_value(t, instance.texture_mode, Texture_Mode.Y_Ramp)
	testing.expect_value(t, instance.effect_offset, [2]f32{0.33, 0.5})
	testing.expect_value(t, instance.border_thickness, f32(4))
	testing.expect_value(t, instance.colors[0], Color{1, 0, 0, 0.8})
	testing.expect_value(t, instance.colors[1], Color{0, 0, 0, 0.6})
	testing.expect_value(t, instance.colors[2], Color{1, 1, 1, 0.9})
	testing.expect_value(t, list.trace[0].label, "glass inner rim")
}

@(test)
inset_shadow_records_direction_and_contour_test :: proc(t: ^testing.T) {
	list: List
	list_init(&list)
	defer list_destroy(&list)

	inset_shadow(
		&list,
		{2, 3, 52, 32},
		{0, 0, 0, 0.12},
		16,
		{-1.25, 1.25},
		1.5,
		corner_shape = .Squircle,
	)

	testing.expect_value(t, len(list.batches), 1)
	instance := list.batches[0].instances[0]
	testing.expect_value(t, instance.texture_mode, Texture_Mode.Inset_Shadow)
	testing.expect_value(t, instance.effect_offset, [2]f32{-1.25, 1.25})
	testing.expect_value(t, instance.edge_softness, f32(1.5))
	testing.expect_value(t, instance.corner_shape, Corner_Shape.Squircle)
}

@(test)
drop_shadow_records_dest_local_hole_test :: proc(t: ^testing.T) {
	list: List
	list_init(&list)
	defer list_destroy(&list)

	drop_shadow(
		&list,
		{4, 6, 40, 28},
		{0, 0, 0, 0.4},
		8,
		3,
		{6, 8, 24, 16},
		7,
		"shadow",
		.Max,
		.Squircle_Pill,
	)

	testing.expect_value(t, len(list.batches), 1)
	instance := list.batches[0].instances[0]
	testing.expect_value(t, instance.texture_mode, Texture_Mode.Shadow)
	testing.expect_value(t, instance.effect_offset, [2]f32{6, 8})
	testing.expect_value(t, instance.src, Rect{7, 0, 24, 16})
	testing.expect_value(t, instance.corner_shape, Corner_Shape.Squircle_Pill)
	testing.expect_value(t, list.batches[0].key.combine, Combine.Max)
}

@(test)
clip_and_opacity_state_split_batches_without_reordering_test :: proc(t: ^testing.T) {
	list: List
	list_init(&list)
	defer list_destroy(&list)

	solid(&list, {0, 0, 10, 10}, {1, 1, 1, 1})
	push_clip(&list, {2, 2, 6, 6})
	push_opacity(&list, 0.5)
	solid(&list, {0, 0, 10, 10}, {1, 1, 1, 1})
	pop_opacity(&list)
	pop_clip(&list)
	solid(&list, {0, 0, 10, 10}, {1, 1, 1, 1})

	testing.expect_value(t, len(list.batches), 3)
	testing.expect(t, list.batches[1].key.clip_set)
	testing.expect_value(t, list.batches[1].key.clip, Rect{2, 2, 6, 6})
	testing.expect_value(t, list.batches[1].key.opacity, f32(0.5))
}

@(test)
nested_clips_intersect_test :: proc(t: ^testing.T) {
	list: List
	list_init(&list)
	defer list_destroy(&list)
	push_clip(&list, {0, 0, 10, 10})
	push_clip(&list, {5, -2, 10, 6})
	clip, enabled := top_clip(&list)
	testing.expect(t, enabled)
	testing.expect_value(t, clip, Rect{5, 0, 5, 4})
}

@(test)
nested_bucket_preserves_order_and_merges_only_adjacent_state_test :: proc(t: ^testing.T) {
	parent, child: Bucket
	bucket_init(&parent)
	defer bucket_destroy(&parent)
	bucket_init(&child)
	defer bucket_destroy(&child)
	solid(&parent, {0, 0, 10, 10}, {1, 0, 0, 1}, label = "before")
	solid(&child, {1, 1, 8, 8}, {0, 1, 0, 1}, label = "child")
	append_bucket(&parent, &child)
	image(&parent, Texture_Handle(8), {2, 2, 4, 4}, {0, 0, 1, 1}, label = "after")
	testing.expect_value(t, len(parent.batches), 2)
	testing.expect_value(t, len(parent.batches[0].instances), 2)
	testing.expect_value(t, parent.trace[0].label, "before")
	testing.expect_value(t, parent.trace[1].label, "child")
	testing.expect_value(t, parent.trace[2].label, "after")
}

@(test)
nested_transforms_and_bucket_state_compose_test :: proc(t: ^testing.T) {
	parent, child: Bucket
	bucket_init(&parent)
	defer bucket_destroy(&parent)
	bucket_init(&child)
	defer bucket_destroy(&child)
	push_transform(&parent, {m00 = 2, m11 = 2, tx = 10, ty = 20})
	push_opacity(&parent, 0.5)
	push_clip(&parent, {0, 0, 20, 20})
	push_transform(&child, {m00 = 1, m11 = 1, tx = 3, ty = 4})
	push_clip(&child, {5, 5, 20, 20})
	solid(&child, {0, 0, 4, 4}, {1, 1, 1, 1})
	append_bucket(&parent, &child)
	testing.expect_value(t, len(parent.batches), 1)
	key := parent.batches[0].key
	testing.expect_value(t, key.transform, Transform_2D{2, 0, 0, 2, 16, 28})
	testing.expect_value(t, key.opacity, f32(0.5))
	testing.expect_value(t, key.clip, Rect{26, 38, 24, 22})
}

@(test)
clip_rect_is_projected_into_render_target_coordinates_test :: proc(t: ^testing.T) {
	list: List
	list_init(&list)
	defer list_destroy(&list)
	push_transform(&list, {m00 = 0, m01 = 1, m10 = -1, m11 = 0, tx = 20})
	push_clip(&list, {2, 3, 8, 4})
	clip, set := top_clip(&list)
	testing.expect(t, set)
	testing.expect_value(t, clip, Rect{13, 2, 4, 8})
}

@(test)
solid_max_combine_starts_a_new_batch_test :: proc(t: ^testing.T) {
	list: List
	list_init(&list)
	defer list_destroy(&list)
	solid(&list, {0, 0, 10, 10}, {0, 0, 0, 0.06})
	solid(&list, {0, 0, 10, 10}, {0, 0, 0, 0.06}, combine = .Max, mode = .Shadow)
	testing.expect_value(t, len(list.batches), 2)
	testing.expect_value(t, list.batches[0].key.combine, Combine.Over)
	testing.expect_value(t, list.batches[1].key.combine, Combine.Max)
	testing.expect_value(t, list.batches[1].instances[0].texture_mode, Texture_Mode.Shadow)
}

@(test)
paths_preserve_submission_order_between_quad_batches_test :: proc(t: ^testing.T) {
	list: List
	list_init(&list, pixel_ratio = 2)
	defer list_destroy(&list)
	solid(&list, {0, 0, 20, 20}, {1, 1, 1, 1}, label = "before")
	path_begin(&list)
	path_move_to(&list, 2, 2)
	path_line_to(&list, 18, 18)
	path_stroke(&list, {1, 0, 0, 1}, 2, cap = .Round, label = "path")
	solid(&list, {20, 0, 20, 20}, {1, 1, 1, 1}, label = "after")

	testing.expect_value(t, len(list.batches), 3)
	testing.expect_value(t, list.batches[0].kind, Batch_Kind.Quad)
	testing.expect_value(t, list.batches[1].kind, Batch_Kind.Path)
	testing.expect_value(t, list.batches[1].path.kind, Path_Batch_Kind.Stroke)
	testing.expect(t, len(list.batches[1].path.fill) > 0)
	testing.expect_value(t, list.batches[2].kind, Batch_Kind.Quad)
	testing.expect_value(t, list.trace[1].label, "path")
}

@(test)
compound_fill_records_the_requested_fill_rule_test :: proc(t: ^testing.T) {
	list: List
	list_init(&list)
	defer list_destroy(&list)
	path_begin(&list)
	path_circle(&list, 20, 20, 18)
	path_circle(&list, 20, 20, 8)
	path_solidity(&list, .Hole)
	path_fill(&list, {0, 0.5, 1, 1}, .Even_Odd)

	testing.expect_value(t, len(list.batches), 1)
	testing.expect_value(t, list.batches[0].path.kind, Path_Batch_Kind.Compound_Fill)
	testing.expect_value(t, list.batches[0].path.fill_rule, Path_Fill_Rule.Even_Odd)
	testing.expect(t, len(list.batches[0].path.cover) == 6)
}

@(test)
non_finite_path_input_discards_the_pending_draw_test :: proc(t: ^testing.T) {
	list: List
	list_init(&list)
	defer list_destroy(&list)
	path_begin(&list)
	path_move_to(&list, 0, 0)
	path_line_to(&list, math.INF_F32, 10)
	path_stroke(&list, {1, 1, 1, 1}, 2)
	testing.expect_value(t, len(list.batches), 0)
}
