package glyphatlas

import "core:math"
import draw "ui_framework:draw"

PHASES :: 4

Format :: enum {
	Alpha,
	Color,
}

Create_Proc :: proc(user_data: rawptr, format: Format, width, height: int) -> u64
Upload_Proc :: proc(user_data: rawptr, native: u64, format: Format, x, y, width, height: int, pixels: [^]u8, bytes_per_row: int)
Destroy_Proc :: proc(user_data: rawptr, native: u64)
Bind_Proc :: proc(user_data: rawptr, native: u64) -> draw.Texture_Handle

IO :: struct {
	user_data: rawptr,
	create:    Create_Proc,
	upload:    Upload_Proc,
	destroy:   Destroy_Proc,
	bind:      Bind_Proc,
}

Dirty_Rect :: struct {
	x, y, w, h: int,
	valid:      bool,
}

Packing :: struct {
	width,height:int,
	cursor_x,cursor_y,row_height:int,
}

allocate :: proc(page: ^Packing, width, height: int) -> (int, int, bool) {
	if width <= 0 || height <= 0 || width > page.width || height > page.height {return 0, 0, false}
	if page.cursor_x+width > page.width {
		page.cursor_x = 0
		page.cursor_y += page.row_height
		page.row_height = 0
	}
	if page.cursor_y+height > page.height {return 0, 0, false}
	x, y := page.cursor_x, page.cursor_y
	page.cursor_x += width
	page.row_height = max(page.row_height, height)
	return x, y, true
}

mark_dirty :: proc(dirty: ^Dirty_Rect, rect: Dirty_Rect) {
	if !dirty.valid {
		dirty^ = rect
		dirty.valid = true
		return
	}
	x0 := min(dirty.x, rect.x)
	y0 := min(dirty.y, rect.y)
	x1 := max(dirty.x+dirty.w, rect.x+rect.w)
	y1 := max(dirty.y+dirty.h, rect.y+rect.h)
	dirty^ = {x0, y0, x1-x0, y1-y0, true}
}

// phase_index quantizes a pen's horizontal subpixel phase into the glyph
// cache key, so the bitmap can be rasterized at the phase it is sampled with.
phase_index :: proc(backing_scale, pen_x: f32) -> u8 {
	scaled := f64(pen_x) * f64(max(backing_scale, 1))
	phase := scaled - math.floor(scaled)
	index := int(phase * f64(PHASES) + 0.5)
	if index == PHASES {
		index = 0 // a phase rounding up to 1.0 is the next pixel's phase 0
	}
	return u8(index)
}

// phase_offset is the cached phase index in device pixels.
phase_offset :: proc(phase: u8) -> f64 {
	return f64(phase) / f64(PHASES)
}

// snap_to_pixel rounds a logical coordinate to the device pixel grid.
snap_to_pixel :: proc(backing_scale, value: f32) -> f32 {
	scale := max(backing_scale, 1)
	return f32(math.round(f64(value) * f64(scale))) / scale
}
