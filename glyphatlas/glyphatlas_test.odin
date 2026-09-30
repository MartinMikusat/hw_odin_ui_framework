package glyphatlas

import "core:testing"

@(test)
shelf_allocator_starts_new_rows_and_rejects_oversized_glyphs_test :: proc(t: ^testing.T) {
	page := Packing{width = 16, height = 16}
	x, y, ok := allocate(&page, 10, 5)
	testing.expect(t, ok)
	testing.expect_value(t, x, 0)
	testing.expect_value(t, y, 0)
	x, y, ok = allocate(&page, 8, 6)
	testing.expect(t, ok)
	testing.expect_value(t, x, 0)
	testing.expect_value(t, y, 5)
	_, _, ok = allocate(&page, 17, 1)
	testing.expect(t, !ok)
}

@(test)
dirty_rect_unions_independent_glyph_uploads_test :: proc(t: ^testing.T) {
	dirty: Dirty_Rect
	mark_dirty(&dirty, {2, 3, 4, 5, true})
	mark_dirty(&dirty, {8, 1, 3, 4, true})
	testing.expect_value(t, dirty, Dirty_Rect{2, 1, 9, 7, true})
}

@(test)
glyph_subpixel_phase_and_pixel_snap_test :: proc(t: ^testing.T) {
	// Quantization picks the nearest of four phases and wraps 1.0 to phase 0.
	testing.expect_value(t, phase_index(2, 0.0), u8(0))
	testing.expect_value(t, phase_index(2, 0.13), u8(1))
	testing.expect_value(t, phase_index(2, 0.26), u8(2))
	testing.expect_value(t, phase_index(2, 0.40), u8(3))
	testing.expect_value(t, phase_index(2, 0.49), u8(0))
	testing.expect_value(t, phase_index(2, -0.13), u8(3))
	testing.expect_value(t, phase_offset(3), 0.75)

	// Snapping moves a coordinate to the nearest device pixel.
	testing.expect_value(t, snap_to_pixel(2, 11.1599), f32(11))
	testing.expect_value(t, snap_to_pixel(2, 11.3), f32(11.5))
	testing.expect_value(t, snap_to_pixel(1, 4.6), f32(5))
}
