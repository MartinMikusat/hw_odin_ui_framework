package coretext

import "core:math"
import "core:strings"
import "core:testing"
import ui "ui_framework:core"
import draw "ui_framework:draw"

test_atlas_create :: proc(_: rawptr, _: Atlas_Format, _: int, _: int) -> u64 {
	return 1
}

test_atlas_bind :: proc(_: rawptr, _: u64) -> draw.Texture_Handle {
	return draw.Texture_Handle(1)
}

@(test)
coretext_measurement_and_cached_shape_share_one_line_test :: proc(t: ^testing.T) {
	value: Context
	context_init(&value)
	defer context_destroy(&value)
	register_font(&value, ui.Font_Handle(1), "Menlo-Regular")
	begin_frame(&value, 2)
	first := shape(&value, ui.Font_Handle(1), "office café 😀", 12, 0, 0, false)
	second := shape(&value, ui.Font_Handle(1), "office café 😀", 12, 0, 0, false)
	testing.expect(t, first != nil)
	testing.expect(t, second != nil)
	testing.expect(t, first == second)
	testing.expect(t, first.metrics.width > 0)
	testing.expect(t, first.metrics.ascent > 0)
	testing.expect(t, len(first.glyphs) > 0)
}

@(test)
shape_cache_reuses_a_stable_run_across_frames_test :: proc(t: ^testing.T) {
	value: Context
	context_init(&value)
	defer context_destroy(&value)
	register_font(&value, ui.Font_Handle(1), "Menlo-Regular")
	begin_frame(&value, 2)
	first := prepare_callback(&value, ui.Font_Handle(1), "persistent", 12, 0, 0, false)
	first_stats := shape_cache_stats(&value)
	begin_frame(&value, 2)
	second := prepare_callback(&value, ui.Font_Handle(1), "persistent", 12, 0, 0, false)
	second_stats := shape_cache_stats(&value)
	testing.expect(t, first.run != ui.Text_Run_ID(0))
	testing.expect_value(t, second.run, first.run)
	testing.expect_value(t, first_stats.misses, u64(1))
	testing.expect_value(t, second_stats.hits, u64(1))
	testing.expect_value(t, second_stats.entries, 1)
}

@(test)
shape_cache_key_includes_scale_and_font_generation_test :: proc(t: ^testing.T) {
	value: Context
	context_init(&value)
	defer context_destroy(&value)
	register_font(&value, ui.Font_Handle(1), "Menlo-Regular")
	begin_frame(&value, 1)
	first := prepare_callback(&value, ui.Font_Handle(1), "scaled", 12, 0, 0, false)
	begin_frame(&value, 2)
	second := prepare_callback(&value, ui.Font_Handle(1), "scaled", 12, 0, 0, false)
	testing.expect(t, first.run != second.run)
	register_font(&value, ui.Font_Handle(1), ".AppleSystemUIFont")
	testing.expect_value(t, shape_cache_stats(&value).entries, 0)
}

@(test)
shape_cache_purges_a_run_after_240_unused_rendered_frames_test :: proc(t: ^testing.T) {
	value: Context
	context_init(&value)
	defer context_destroy(&value)
	register_font(&value, ui.Font_Handle(1), "Menlo-Regular")
	begin_frame(&value, 2)
	_ = shape(&value, ui.Font_Handle(1), "stale", 12, 0, 0, false)
	value.frame = SHAPE_CACHE_STALE_FRAMES
	begin_frame(&value, 2)
	stats := shape_cache_stats(&value)
	testing.expect_value(t, stats.entries, 0)
	testing.expect_value(t, stats.evictions, u64(1))
}

@(test)
prepared_run_handle_emits_without_reshaping_test :: proc(t: ^testing.T) {
	value: Context
	context_init(&value)
	defer context_destroy(&value)
	register_font(&value, ui.Font_Handle(1), "Menlo-Regular")
	begin_frame(&value, 2)
	prepared := prepare_callback(
		&value,
		ui.Font_Handle(1),
		"prepared text",
		12,
		0,
		0,
		false,
	)
	testing.expect(t, prepared.run != ui.Text_Run_ID(0))
	run_count := len(value.runs)
	list: draw.List
	draw.list_init(&list)
	defer draw.list_destroy(&list)
	emit_callback(
		&value,
		&list,
		prepared.run,
		"prepared text",
		{0, 0, 200, 30},
		{size = 12, vertical = .Center},
		{1, 1, 1, 1},
	)
	testing.expect_value(t, len(value.runs), run_count)
}

@(test)
truncation_and_hit_positions_use_the_shaped_coretext_line_test :: proc(t: ^testing.T) {
	value: Context
	context_init(&value)
	defer context_destroy(&value)
	register_font(&value, ui.Font_Handle(1), "Menlo-Regular")
	begin_frame(&value, 2)
	full := shape(&value, ui.Font_Handle(1), "a long line of text", 12, 0, 0, false)
	short := shape(&value, ui.Font_Handle(1), "a long line of text", 12, 0, 40, true)
	testing.expect(t, full != nil && short != nil)
	testing.expect(t, short.metrics.width <= 40.01)
	position := offset_for_utf16_index(full, 3, value.backing_scale)
	testing.expect(t, position > 0)
	testing.expect(t, utf16_index_for_offset(full, position, value.backing_scale) >= 2)
}

@(test)
wrapped_line_ranges_preserve_unicode_newlines_and_narrow_clusters_test :: proc(t: ^testing.T) {
	value: Context
	context_init(&value)
	defer context_destroy(&value)
	register_font(&value, ui.Font_Handle(1), "Menlo-Regular")
	begin_frame(&value, 2)
	text := "alpha beta\n\ncafé 😀 gamma\n"
	lines := wrap_line_ranges(&value, ui.Font_Handle(1), text, 12, 0, 70)
	defer delete(lines)
	testing.expect(t, len(lines) >= 5)
	testing.expect_value(t, text[lines[0].byte_start:lines[0].byte_end], "alpha ")
	found_blank, found_unicode := false, false
	previous_next := 0
	for line in lines {
		testing.expect_value(t, line.byte_start, previous_next)
		testing.expect(t, line.byte_start <= line.byte_end && line.byte_end <= line.next_byte)
		if line.byte_start == line.byte_end {found_blank = true}
		if line.byte_end > line.byte_start && strings.contains(text[line.byte_start:line.byte_end], "😀") {found_unicode = true}
		previous_next = line.next_byte
	}
	testing.expect(t, found_blank)
	testing.expect(t, found_unicode)
	testing.expect_value(t, previous_next, len(text))
	narrow := wrap_line_ranges(&value, ui.Font_Handle(1), "😀😀", 12, 0, 1)
	defer delete(narrow)
	testing.expect_value(t, len(narrow), 2)
	testing.expect_value(t, narrow[0].byte_end, len("😀"))
}

@(test)
shelf_allocator_starts_new_rows_and_rejects_oversized_glyphs_test :: proc(t: ^testing.T) {
	page := Atlas_Page{width = 16, height = 16}
	x, y, ok := page_allocate(&page, 10, 5)
	testing.expect(t, ok)
	testing.expect_value(t, x, 0)
	testing.expect_value(t, y, 0)
	x, y, ok = page_allocate(&page, 8, 6)
	testing.expect(t, ok)
	testing.expect_value(t, x, 0)
	testing.expect_value(t, y, 5)
	_, _, ok = page_allocate(&page, 17, 1)
	testing.expect(t, !ok)
}

@(test)
dirty_rect_unions_independent_glyph_uploads_test :: proc(t: ^testing.T) {
	page: Atlas_Page
	mark_dirty(&page, {2, 3, 4, 5, true})
	mark_dirty(&page, {8, 1, 3, 4, true})
	testing.expect_value(t, page.dirty, Dirty_Rect{2, 1, 9, 7, true})
}

// The atlas must rasterize each glyph at its own bounding-box phase: with a
// grid-aligned pen the bitmap then lands on the device pixel grid, and the
// linear sampler reads the mask 1:1 instead of resampling every glyph by a
// different subpixel amount (which reads as inconsistent glyph weight).
@(test)
atlas_bakes_the_glyph_bounding_box_phase_test :: proc(t: ^testing.T) {
	value: Context
	context_init(&value)
	defer context_destroy(&value)
	register_font(&value, ui.Font_Handle(1), "Menlo-Regular")
	begin_frame(&value, 2, Atlas_IO{create = test_atlas_create, bind = test_atlas_bind})
	run := shape(&value, ui.Font_Handle(1), "0147.%M8", 12, 0, 0, false)
	testing.expect(t, run != nil)
	if run == nil {return}

	fractional := false
	for shaped in run.glyphs {
		glyph, ok := ensure_glyph(&value, shaped)
		testing.expect(t, ok)

		glyphs := [1]u16{shaped.glyph}
		bounds_array: [1]Rect
		_ = CTFontGetBoundingRectsForGlyphs(shaped.font, 0, raw_data(glyphs[:]), raw_data(bounds_array[:]), 1)
		bounds := bounds_array[0]
		origin_floor_x := math.floor(bounds.origin.x)
		origin_floor_y := math.floor(bounds.origin.y)
		phase_x := bounds.origin.x - origin_floor_x
		phase_y := bounds.origin.y - origin_floor_y
		if phase_x > 0.01 || phase_y > 0.01 {fractional = true}

		// The offset uses the floored origin, so the baked phase and the
		// bitmap placement reconstruct the glyph's exact device position.
		drawn_x := f64(shaped.position.x + glyph.offset.x) * f64(value.backing_scale)
		expected_x := f64(shaped.position.x) * f64(value.backing_scale) + bounds.origin.x
		testing.expect(t, abs(drawn_x + f64(GLYPH_PADDING) + phase_x - expected_x) < 0.01)

		drawn_y := f64(shaped.position.y + glyph.offset.y) * f64(value.backing_scale)
		expected_y := f64(shaped.position.y) * f64(value.backing_scale) + bounds.origin.y
		testing.expect(t, abs(drawn_y + f64(GLYPH_PADDING) + phase_y - expected_y) < 0.01)

		// The bitmap has room for the phase-shifted outline.
		expected_width := int(bounds.size.width + phase_x + 0.999) + GLYPH_PADDING*2
		expected_height := int(bounds.size.height + phase_y + 0.999) + GLYPH_PADDING*2
		testing.expect(t, int(glyph.size.x * value.backing_scale + 0.5) >= expected_width)
		testing.expect(t, int(glyph.size.y * value.backing_scale + 0.5) >= expected_height)
	}
	testing.expect(t, fractional, "the test string must contain a glyph with a fractional bounding-box origin")
}

@(test)
native_coretext_line_emits_glyph_commands_test :: proc(t: ^testing.T) {
	value: Context
	context_init(&value)
	defer context_destroy(&value)
	register_font(&value, ui.Font_Handle(1), "Menlo-Regular")
	begin_frame(&value, 2, Atlas_IO{create = test_atlas_create, bind = test_atlas_bind})
	run := shape(&value, ui.Font_Handle(1), "native", 12, 0, 0, false)
	testing.expect(t, run != nil)
	if run == nil {return}

	list: draw.List
	draw.list_init(&list)
	defer draw.list_destroy(&list)
	emit_native_line(&value, &list, run.line, {4, 8}, {1, 1, 1, 1}, "native")
	instance_count := 0
	for batch in list.batches {instance_count += len(batch.instances)}
	testing.expect(t, instance_count > 0)
	testing.expect(t, len(list.trace) > 0)
	for entry in list.trace {
		testing.expect_value(t, entry.kind, draw.Trace_Kind.Glyph)
		testing.expect_value(t, entry.label, "native")
	}
}
