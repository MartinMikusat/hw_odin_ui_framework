package draw

import "core:testing"

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
