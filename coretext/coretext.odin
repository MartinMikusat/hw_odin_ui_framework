package coretext

import "core:hash"
import "core:mem"
import "core:strings"
import CF "core:sys/darwin/CoreFoundation"
import ui "ui_framework:core"
import draw "ui_framework:draw"

Point :: struct {
	x, y: f64,
}

Size :: struct {
	width, height: f64,
}

Rect :: struct {
	origin: Point,
	size:   Size,
}

foreign import core_foundation "system:CoreFoundation.framework"
foreign core_foundation {
	CFStringCreateWithCString           :: proc "c" (allocator: rawptr, text: cstring, encoding: u32) -> rawptr ---
	CFStringGetLength                   :: proc "c" (value: rawptr) -> int ---
	CFAttributedStringCreateMutable     :: proc "c" (allocator: rawptr, maximum_length: int) -> rawptr ---
	CFAttributedStringReplaceString     :: proc "c" (value: rawptr, range: CF.Range, replacement: rawptr) ---
	CFAttributedStringSetAttribute      :: proc "c" (value: rawptr, range: CF.Range, name, attribute: rawptr) ---
	CFArrayGetCount                     :: proc "c" (array: rawptr) -> int ---
	CFArrayGetValueAtIndex              :: proc "c" (array: rawptr, index: int) -> rawptr ---
	CFDictionaryGetValue                :: proc "c" (dictionary, key: rawptr) -> rawptr ---
	CFNumberCreate                      :: proc "c" (allocator: rawptr, number_type: int, value: rawptr) -> rawptr ---
	CFHash                              :: proc "c" (value: rawptr) -> uint ---
	CFRetain                            :: proc "c" (value: rawptr) -> rawptr ---
	CFRelease                           :: proc "c" (value: rawptr) ---
	kCFBooleanTrue: rawptr
}

foreign import core_text "system:CoreText.framework"
foreign core_text {
	CTFontCreateWithName                 :: proc "c" (name: rawptr, size: f64, transform: rawptr) -> rawptr ---
	CTFontGetSymbolicTraits              :: proc "c" (font: rawptr) -> u32 ---
	CTFontGetBoundingRectsForGlyphs      :: proc "c" (font: rawptr, orientation: u32, glyphs: [^]u16, rects: [^]Rect, count: int) -> Rect ---
	CTFontDrawGlyphs                     :: proc "c" (font: rawptr, glyphs: [^]u16, positions: [^]Point, count: int, ctx: rawptr) ---
	CTLineCreateWithAttributedString     :: proc "c" (value: rawptr) -> rawptr ---
	CTLineCreateTruncatedLine            :: proc "c" (line: rawptr, width: f64, truncation_type: u32, token: rawptr) -> rawptr ---
	CTTypesetterCreateWithAttributedString :: proc "c" (value: rawptr) -> rawptr ---
	CTTypesetterSuggestLineBreak         :: proc "c" (typesetter: rawptr, start: CF.Index, width: f64) -> CF.Index ---
	CTTypesetterSuggestClusterBreak      :: proc "c" (typesetter: rawptr, start: CF.Index, width: f64) -> CF.Index ---
	CTLineGetTypographicBounds           :: proc "c" (line: rawptr, ascent, descent, leading: ^f64) -> f64 ---
	CTLineGetGlyphRuns                   :: proc "c" (line: rawptr) -> rawptr ---
	CTLineGetOffsetForStringIndex        :: proc "c" (line: rawptr, index: int, secondary_offset: ^f64) -> f64 ---
	CTLineGetStringIndexForPosition      :: proc "c" (line: rawptr, point: Point) -> int ---
	CTRunGetGlyphCount                   :: proc "c" (run: rawptr) -> int ---
	CTRunGetGlyphs                       :: proc "c" (run: rawptr, range: CF.Range, glyphs: [^]u16) ---
	CTRunGetPositions                    :: proc "c" (run: rawptr, range: CF.Range, positions: [^]Point) ---
	CTRunGetStringIndices                :: proc "c" (run: rawptr, range: CF.Range, indices: [^]int) ---
	CTRunGetAttributes                   :: proc "c" (run: rawptr) -> rawptr ---
	kCTFontAttributeName: rawptr
	kCTForegroundColorFromContextAttributeName: rawptr
	kCTLigatureAttributeName: rawptr
	kCTKernAttributeName: rawptr
}

foreign import core_graphics "system:CoreGraphics.framework"
foreign core_graphics {
	CGColorSpaceCreateDeviceGray :: proc "c" () -> rawptr ---
	CGColorSpaceCreateDeviceRGB  :: proc "c" () -> rawptr ---
	CGColorSpaceRelease          :: proc "c" (space: rawptr) ---
	CGBitmapContextCreate        :: proc "c" (data: rawptr, width, height, bits_per_component, bytes_per_row: uint, space: rawptr, bitmap_info: u32) -> rawptr ---
	CGContextRelease             :: proc "c" (ctx: rawptr) ---
	CGContextSetRGBFillColor     :: proc "c" (ctx: rawptr, red, green, blue, alpha: f64) ---
	CGContextSetGrayFillColor    :: proc "c" (ctx: rawptr, gray, alpha: f64) ---
}

UTF8_ENCODING :: u32(0x08000100)
COLOR_GLYPH_TRAIT :: u32(1 << 13)
ALPHA_PAGE_SIZE :: 2048
ALPHA_PAGE_LIMIT :: 4
COLOR_PAGE_SIZE :: 1024
COLOR_PAGE_LIMIT :: 2
GLYPH_PADDING :: 2

Atlas_Format :: enum {
	Alpha,
	Color,
}

Atlas_Create_Proc :: proc(user_data: rawptr, format: Atlas_Format, width, height: int) -> u64
Atlas_Upload_Proc :: proc(user_data: rawptr, native: u64, format: Atlas_Format, x, y, width, height: int, pixels: [^]u8, bytes_per_row: int)
Atlas_Destroy_Proc :: proc(user_data: rawptr, native: u64)
Atlas_Bind_Proc :: proc(user_data: rawptr, native: u64) -> draw.Texture_Handle

Atlas_IO :: struct {
	user_data: rawptr,
	create:    Atlas_Create_Proc,
	upload:    Atlas_Upload_Proc,
	destroy:   Atlas_Destroy_Proc,
	bind:      Atlas_Bind_Proc,
}

Dirty_Rect :: struct {
	x, y, w, h: int,
	valid:      bool,
}

Atlas_Page :: struct {
	format:        Atlas_Format,
	width, height: int,
	bytes_per_pixel: int,
	pixels:        []u8,
	graphics:      rawptr,
	native:        u64,
	cursor_x:      int,
	cursor_y:      int,
	row_height:    int,
	dirty:         Dirty_Rect,
	bound_frame:   u64,
	bound_texture: draw.Texture_Handle,
	generation:    u64,
}

Glyph_Key :: struct {
	font_hash: uint,
	glyph:     u16,
	format:    Atlas_Format,
}

Atlas_Glyph :: struct {
	page:        int,
	pixel_rect:  Dirty_Rect,
	offset:      ui.Vec2,
	size:        ui.Vec2,
	generation:  u64,
}

Shaped_Glyph :: struct {
	font:         rawptr,
	glyph:        u16,
	position:     ui.Vec2,
	string_index: int,
}

Shape_Key :: struct {
	font:          ui.Font_Handle,
	text_hash:     u64,
	size_bits:     u32,
	tracking_bits: u32,
	width_bits:    u32,
	truncate:      bool,
}

Shaped_Run :: struct {
	key:       Shape_Key,
	text:      string,
	line:      rawptr,
	glyphs:    [dynamic]Shaped_Glyph,
	metrics:   ui.Text_Metrics,
}

Wrapped_Line_Range :: struct {
	byte_start, byte_end, next_byte: int,
}

Font_Entry :: struct {
	handle: ui.Font_Handle,
	name:   string,
}

Context :: struct {
	allocator:        mem.Allocator,
	fonts:            [dynamic]Font_Entry,
	runs:             [dynamic]Shaped_Run,
	pages:            [dynamic]Atlas_Page,
	retired_pages:    [dynamic]Atlas_Page,
	glyphs:           map[Glyph_Key]Atlas_Glyph,
	io:               Atlas_IO,
	backing_scale:    f32,
	frame:            u64,
	generation:       u64,
}

context_init :: proc(value: ^Context, allocator := context.allocator) {
	assert(value != nil)
	value^ = Context{allocator = allocator, backing_scale = 1, generation = 1}
	value.fonts = make([dynamic]Font_Entry, allocator)
	value.runs = make([dynamic]Shaped_Run, allocator)
	value.pages = make([dynamic]Atlas_Page, allocator)
	value.retired_pages = make([dynamic]Atlas_Page, allocator)
	value.glyphs = make(map[Glyph_Key]Atlas_Glyph, allocator)
}

release_run :: proc(value: ^Context, run: ^Shaped_Run) {
	if run.line != nil {CFRelease(run.line)}
	delete(run.text, value.allocator)
	delete(run.glyphs)
	run^ = {}
}

destroy_page :: proc(value: ^Context, page: ^Atlas_Page) {
	if page.graphics != nil {CGContextRelease(page.graphics)}
	if page.native != 0 && value.io.destroy != nil {value.io.destroy(value.io.user_data, page.native)}
	delete(page.pixels, value.allocator)
	page^ = {}
}

context_destroy :: proc(value: ^Context) {
	if value == nil {return}
	for &font in value.fonts {delete(font.name, value.allocator)}
	for &run in value.runs {release_run(value, &run)}
	for &page in value.pages {destroy_page(value, &page)}
	for &page in value.retired_pages {destroy_page(value, &page)}
	delete(value.fonts)
	delete(value.runs)
	delete(value.pages)
	delete(value.retired_pages)
	delete(value.glyphs)
	value^ = {}
}

register_font :: proc(value: ^Context, handle: ui.Font_Handle, postscript_name: string) {
	assert(value != nil && handle != ui.Font_Handle(0) && len(postscript_name) > 0)
	for &font in value.fonts {
		if font.handle != handle {continue}
		delete(font.name, value.allocator)
		font.name = strings.clone(postscript_name, value.allocator)
		return
	}
	append(&value.fonts, Font_Entry{handle, strings.clone(postscript_name, value.allocator)})
}

font_name :: proc(value: ^Context, handle: ui.Font_Handle) -> string {
	for &font in value.fonts {if font.handle == handle {return font.name}}
	return ""
}

begin_frame :: proc(value: ^Context, backing_scale: f32, io: Atlas_IO = {}) {
	assert(value != nil)
	collect_retired(value)
	for &run in value.runs {release_run(value, &run)}
	clear(&value.runs)
	value.frame += 1
	value.backing_scale = max(backing_scale, 1)
	value.io = io
}

float_bits :: proc(value: f32) -> u32 {
	return transmute(u32)value
}

shape_key :: proc(font: ui.Font_Handle, text: string, size, tracking, width: f32, truncate: bool) -> Shape_Key {
	return {
		font = font,
		text_hash = hash.fnv64a(transmute([]u8)text),
		size_bits = float_bits(size),
		tracking_bits = float_bits(tracking),
		width_bits = float_bits(width),
		truncate = truncate,
	}
}

cfstring :: proc(value: string) -> rawptr {
	if len(value) == 0 {return nil}
	text, err := strings.clone_to_cstring(value, context.temp_allocator)
	if err != nil {return nil}
	defer delete(text, context.temp_allocator)
	return CFStringCreateWithCString(nil, text, UTF8_ENCODING)
}

make_attributed_string :: proc(value: ^Context, font_handle: ui.Font_Handle, text: string, size, tracking: f32) -> rawptr {
	name := font_name(value, font_handle)
	if len(name) == 0 || len(text) == 0 {return nil}
	name_ref := cfstring(name)
	if name_ref == nil {return nil}
	defer CFRelease(name_ref)
	font := CTFontCreateWithName(name_ref, f64(size*value.backing_scale), nil)
	if font == nil {return nil}
	defer CFRelease(font)
	string_ref := cfstring(text)
	if string_ref == nil {return nil}
	defer CFRelease(string_ref)
	attributed := CFAttributedStringCreateMutable(nil, 0)
	if attributed == nil {return nil}
	CFAttributedStringReplaceString(attributed, {}, string_ref)
	range := CF.Range{0, CF.Index(CFStringGetLength(string_ref))}
	CFAttributedStringSetAttribute(attributed, range, kCTFontAttributeName, font)
	CFAttributedStringSetAttribute(attributed, range, kCTForegroundColorFromContextAttributeName, kCFBooleanTrue)
	ligatures := i32(1)
	ligature_number := CFNumberCreate(nil, 9, &ligatures)
	if ligature_number != nil {
		CFAttributedStringSetAttribute(attributed, range, kCTLigatureAttributeName, ligature_number)
		CFRelease(ligature_number)
	}
	if tracking != 0 {
		scaled_tracking := f64(tracking*value.backing_scale)
		tracking_number := CFNumberCreate(nil, 13, &scaled_tracking)
		if tracking_number != nil {
			CFAttributedStringSetAttribute(attributed, range, kCTKernAttributeName, tracking_number)
			CFRelease(tracking_number)
		}
	}
	return attributed
}

make_line :: proc(value: ^Context, font_handle: ui.Font_Handle, text: string, size, tracking: f32) -> rawptr {
	attributed := make_attributed_string(value, font_handle, text, size, tracking)
	if attributed == nil {return nil}
	defer CFRelease(attributed)
	return CTLineCreateWithAttributedString(attributed)
}

byte_offset_for_utf16_index :: proc(text: string, target_index: int) -> int {
	byte_index, utf16_index := 0, 0
	for byte_index < len(text) && utf16_index < max(0, target_index) {
		first := text[byte_index]
		byte_count, utf16_count := 1, 1
		if first&0xf8 == 0xf0 {byte_count, utf16_count = 4, 2}
		else if first&0xf0 == 0xe0 {byte_count = 3}
		else if first&0xe0 == 0xc0 {byte_count = 2}
		if utf16_index+utf16_count > target_index {break}
		byte_index += byte_count
		utf16_index += utf16_count
	}
	return min(byte_index, len(text))
}

wrap_line_ranges :: proc(
	value: ^Context,
	font: ui.Font_Handle,
	text: string,
	size, tracking, maximum_width: f32,
	allocator := context.allocator,
) -> [dynamic]Wrapped_Line_Range {
	result := make([dynamic]Wrapped_Line_Range, allocator)
	if value == nil || len(text) == 0 || maximum_width <= 0 {return result}
	attributed := make_attributed_string(value, font, text, size, tracking)
	if attributed == nil {return result}
	defer CFRelease(attributed)
	typesetter := CTTypesetterCreateWithAttributedString(attributed)
	if typesetter == nil {return result}
	defer CFRelease(typesetter)
	text_ref := cfstring(text)
	if text_ref == nil {return result}
	defer CFRelease(text_ref)
	utf16_length := CFStringGetLength(text_ref)
	utf16_start := 0
	for utf16_start < utf16_length {
		count := int(CTTypesetterSuggestLineBreak(typesetter, CF.Index(utf16_start), f64(maximum_width*value.backing_scale)))
		if count <= 0 {
			count = int(CTTypesetterSuggestClusterBreak(typesetter, CF.Index(utf16_start), f64(maximum_width*value.backing_scale)))
		}
		if count <= 0 {count = 1}
		utf16_next := min(utf16_length, utf16_start+count)
		byte_start := byte_offset_for_utf16_index(text, utf16_start)
		next_byte := byte_offset_for_utf16_index(text, utf16_next)
		byte_end := next_byte
		if byte_end > byte_start && text[byte_end-1] == '\n' {byte_end -= 1}
		if byte_end > byte_start && text[byte_end-1] == '\r' {byte_end -= 1}
		append(&result, Wrapped_Line_Range{byte_start, byte_end, next_byte})
		utf16_start = utf16_next
	}
	if len(text) > 0 && (text[len(text)-1] == '\n' || text[len(text)-1] == '\r') {
		append(&result, Wrapped_Line_Range{len(text), len(text), len(text)})
	}
	return result
}

fill_shaped_glyphs :: proc(value: ^Context, shaped: ^Shaped_Run) {
	runs := CTLineGetGlyphRuns(shaped.line)
	if runs == nil {return}
	for run_index in 0 ..< CFArrayGetCount(runs) {
		run := CFArrayGetValueAtIndex(runs, run_index)
		count := CTRunGetGlyphCount(run)
		if count <= 0 {continue}
		glyphs := make([]u16, count, context.temp_allocator)
		positions := make([]Point, count, context.temp_allocator)
		indices := make([]int, count, context.temp_allocator)
		defer delete(glyphs, context.temp_allocator)
		defer delete(positions, context.temp_allocator)
		defer delete(indices, context.temp_allocator)
		CTRunGetGlyphs(run, {}, raw_data(glyphs))
		CTRunGetPositions(run, {}, raw_data(positions))
		CTRunGetStringIndices(run, {}, raw_data(indices))
		attributes := CTRunGetAttributes(run)
		font := CFDictionaryGetValue(attributes, kCTFontAttributeName)
		for glyph, index in glyphs {
			append(&shaped.glyphs, Shaped_Glyph{
				font = font,
				glyph = glyph,
				position = {
					f32(positions[index].x)/value.backing_scale,
					f32(positions[index].y)/value.backing_scale,
				},
				string_index = indices[index],
			})
		}
	}
}

shape :: proc(value: ^Context, font: ui.Font_Handle, text: string, size, tracking, maximum_width: f32, truncate: bool) -> ^Shaped_Run {
	key := shape_key(font, text, size, tracking, maximum_width, truncate)
	for &run in value.runs {if run.key == key && run.text == text {return &run}}
	line := make_line(value, font, text, size, tracking)
	if line == nil {return nil}
	if truncate && maximum_width > 0 {
		full_width := CTLineGetTypographicBounds(line, nil, nil, nil)
		maximum_pixels := f64(maximum_width*value.backing_scale)
		if full_width > maximum_pixels {
			token := make_line(value, font, "…", size, tracking)
			if token != nil {
				truncated := CTLineCreateTruncatedLine(line, maximum_pixels, 1, token)
				CFRelease(token)
				if truncated != nil {
					CFRelease(line)
					line = truncated
				}
			}
		}
	}
	ascent, descent, leading: f64
	advance := CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
	run := Shaped_Run{
		key = key,
		text = strings.clone(text, value.allocator),
		line = line,
		metrics = {
			f32(advance)/value.backing_scale,
			f32(ascent)/value.backing_scale,
			f32(descent)/value.backing_scale,
			f32(leading)/value.backing_scale,
		},
	}
	run.glyphs = make([dynamic]Shaped_Glyph, value.allocator)
	fill_shaped_glyphs(value, &run)
	append(&value.runs, run)
	return &value.runs[len(value.runs)-1]
}

prepare_callback :: proc(
	data: rawptr,
	font: ui.Font_Handle,
	text: string,
	size, tracking, maximum_width: f32,
	truncate: bool,
) -> ui.Prepared_Text {
	value := (^Context)(data)
	run := shape(value, font, text, size, tracking, maximum_width, truncate)
	if run == nil {return {}}
	for &candidate, index in value.runs {
		if &candidate == run {
			return {ui.Text_Run_ID(index+1), run.metrics}
		}
	}
	return {}
}

page_limit :: proc(format: Atlas_Format) -> int {
	return ALPHA_PAGE_LIMIT if format == .Alpha else COLOR_PAGE_LIMIT
}

page_size :: proc(format: Atlas_Format) -> int {
	return ALPHA_PAGE_SIZE if format == .Alpha else COLOR_PAGE_SIZE
}

make_page :: proc(value: ^Context, format: Atlas_Format) -> (Atlas_Page, bool) {
	size := page_size(format)
	bpp := 1 if format == .Alpha else 4
	pixels := make([]u8, size*size*bpp, value.allocator)
	space := CGColorSpaceCreateDeviceGray() if format == .Alpha else CGColorSpaceCreateDeviceRGB()
	if space == nil {delete(pixels, value.allocator); return {}, false}
	bitmap_info := u32(0)
	if format == .Color {bitmap_info = 0x2002}
	graphics := CGBitmapContextCreate(raw_data(pixels), uint(size), uint(size), 8, uint(size*bpp), space, bitmap_info)
	CGColorSpaceRelease(space)
	if graphics == nil {delete(pixels, value.allocator); return {}, false}
	if format == .Alpha {
		CGContextSetGrayFillColor(graphics, 1, 1)
	} else {
		CGContextSetRGBFillColor(graphics, 1, 1, 1, 1)
	}
	native: u64
	if value.io.create != nil {native = value.io.create(value.io.user_data, format, size, size)}
	return Atlas_Page{
		format = format,
		width = size,
		height = size,
		bytes_per_pixel = bpp,
		pixels = pixels,
		graphics = graphics,
		native = native,
		generation = value.generation,
	}, true
}

page_allocate :: proc(page: ^Atlas_Page, width, height: int) -> (int, int, bool) {
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

mark_dirty :: proc(page: ^Atlas_Page, rect: Dirty_Rect) {
	if !page.dirty.valid {
		page.dirty = rect
		page.dirty.valid = true
		return
	}
	x0 := min(page.dirty.x, rect.x)
	y0 := min(page.dirty.y, rect.y)
	x1 := max(page.dirty.x+page.dirty.w, rect.x+rect.w)
	y1 := max(page.dirty.y+page.dirty.h, rect.y+rect.h)
	page.dirty = {x0, y0, x1-x0, y1-y0, true}
}

retire_generation :: proc(value: ^Context) {
	for page in value.pages {append(&value.retired_pages, page)}
	clear(&value.pages)
	clear(&value.glyphs)
	value.generation += 1
}

find_page :: proc(value: ^Context, format: Atlas_Format, width, height: int) -> (int, int, int, bool) {
	format_count := 0
	for &page, index in value.pages {
		if page.format != format {continue}
		format_count += 1
		if x, y, ok := page_allocate(&page, width, height); ok {return index, x, y, true}
	}
	if format_count >= page_limit(format) {
		retire_generation(value)
	}
	page, ok := make_page(value, format)
	if !ok {return 0, 0, 0, false}
	append(&value.pages, page)
	index := len(value.pages)-1
	x, y, allocated := page_allocate(&value.pages[index], width, height)
	return index, x, y, allocated
}

ensure_glyph :: proc(value: ^Context, shaped: Shaped_Glyph) -> (Atlas_Glyph, bool) {
	format := Atlas_Format.Alpha
	if CTFontGetSymbolicTraits(shaped.font) & COLOR_GLYPH_TRAIT != 0 {format = .Color}
	key := Glyph_Key{CFHash(shaped.font), shaped.glyph, format}
	if glyph, ok := value.glyphs[key]; ok && glyph.generation == value.generation {return glyph, true}
	glyphs := [1]u16{shaped.glyph}
	bounds_array: [1]Rect
	_ = CTFontGetBoundingRectsForGlyphs(shaped.font, 0, raw_data(glyphs[:]), raw_data(bounds_array[:]), 1)
	bounds := bounds_array[0]
	width := max(1, int(bounds.size.width+0.999))+GLYPH_PADDING*2
	height := max(1, int(bounds.size.height+0.999))+GLYPH_PADDING*2
	page_index, x, y, ok := find_page(value, format, width, height)
	if !ok {return {}, false}
	page := &value.pages[page_index]
	positions := [1]Point{{
		f64(x+GLYPH_PADDING)-bounds.origin.x,
		f64(y+GLYPH_PADDING)-bounds.origin.y,
	}}
	CTFontDrawGlyphs(shaped.font, raw_data(glyphs[:]), raw_data(positions[:]), 1, page.graphics)
	// Quartz bitmap memory stores the top row first while its default user
	// coordinates start at the bottom. Mirror the allocated Y coordinate when
	// the bytes enter the Metal texture, then sample the rectangle bottom-up.
	pixel_rect := Dirty_Rect{x, page.height-y-height, width, height, true}
	mark_dirty(page, pixel_rect)
	glyph := Atlas_Glyph{
		page = page_index,
		pixel_rect = pixel_rect,
		offset = {
			f32(bounds.origin.x-f64(GLYPH_PADDING))/value.backing_scale,
			f32(bounds.origin.y-f64(GLYPH_PADDING))/value.backing_scale,
		},
		size = {f32(width)/value.backing_scale, f32(height)/value.backing_scale},
		generation = value.generation,
	}
	value.glyphs[key] = glyph
	return glyph, true
}

bind_page :: proc(value: ^Context, page: ^Atlas_Page) -> draw.Texture_Handle {
	if page.bound_frame == value.frame {return page.bound_texture}
	page.bound_frame = value.frame
	page.bound_texture = draw.Texture_Handle(0)
	if page.native != 0 && value.io.bind != nil {
		page.bound_texture = value.io.bind(value.io.user_data, page.native)
	}
	return page.bound_texture
}

text_origin :: proc(rect: draw.Rect, metrics: ui.Text_Metrics, style: ui.Text_Style) -> ui.Vec2 {
	x := rect.x+style.inset
	switch style.horizontal {
	case .Center: x = rect.x+(rect.w-metrics.width)/2
	case .End: x = rect.x+rect.w-style.inset-metrics.width
	case .Start:
	}
	y := rect.y+style.inset+metrics.descent
	switch style.vertical {
	case .Center: y = rect.y+(rect.h-(metrics.ascent+metrics.descent))/2+metrics.descent
	case .End: y = rect.y+rect.h-style.inset-metrics.ascent
	case .Start:
	}
	return {x, y}
}

emit_callback :: proc(
	data: rawptr,
	list: ^draw.List,
	run_id: ui.Text_Run_ID,
	label: string,
	rect: draw.Rect,
	style: ui.Text_Style,
	color: draw.Color,
) {
	value := (^Context)(data)
	index := int(run_id)-1
	if index < 0 || index >= len(value.runs) {return}
	run := &value.runs[index]
	origin := text_origin(rect, run.metrics, style)
	draw.push_clip(list, rect)
	defer draw.pop_clip(list)
	emit_shaped_run(value, list, run, origin, color, label)
}

emit_shaped_run :: proc(
	value: ^Context,
	list: ^draw.List,
	run: ^Shaped_Run,
	origin: ui.Vec2,
	color: draw.Color,
	label: string,
) {
	if value == nil || list == nil || run == nil {return}
	for shaped in run.glyphs {
		glyph, ok := ensure_glyph(value, shaped)
		if !ok || glyph.page < 0 || glyph.page >= len(value.pages) {continue}
		page := &value.pages[glyph.page]
		texture := bind_page(value, page)
		if texture == draw.Texture_Handle(0) {continue}
		mode := draw.Texture_Mode.Alpha_Mask
		if page.format == .Color {mode = .Color}
		dst := draw.Rect{
			origin.x+shaped.position.x+glyph.offset.x,
			origin.y+shaped.position.y+glyph.offset.y,
			glyph.size.x,
			glyph.size.y,
		}
		src := draw.Rect{
			f32(glyph.pixel_rect.x)/f32(page.width),
			f32(glyph.pixel_rect.y+glyph.pixel_rect.h)/f32(page.height),
			f32(glyph.pixel_rect.w)/f32(page.width),
			-f32(glyph.pixel_rect.h)/f32(page.height),
		}
		draw.image(list, texture, dst, src, color, mode, kind = .Glyph, label = label)
	}
}

// Emit a CoreText line that the application shaped. The line's font sizes and
// baseline use backing pixels. The destination origin uses logical points.
emit_native_line :: proc(
	value: ^Context,
	list: ^draw.List,
	line: rawptr,
	origin: ui.Vec2,
	color: draw.Color,
	label: string = "",
) {
	if value == nil || list == nil || line == nil {return}
	run := Shaped_Run{line = line}
	run.glyphs = make([dynamic]Shaped_Glyph, context.temp_allocator)
	defer delete(run.glyphs)
	fill_shaped_glyphs(value, &run)
	emit_shaped_run(value, list, &run, origin, color, label)
}

backend :: proc(value: ^Context) -> ui.Text_Backend {
	return {user_data = value, prepare = prepare_callback, emit = emit_callback}
}

flush :: proc(value: ^Context) {
	if value == nil || value.io.upload == nil {return}
	for &page in value.pages {
		if !page.dirty.valid || page.native == 0 {continue}
		dirty := page.dirty
		offset := (dirty.y*page.width+dirty.x)*page.bytes_per_pixel
		value.io.upload(
			value.io.user_data,
			page.native,
			page.format,
			dirty.x,
			dirty.y,
			dirty.w,
			dirty.h,
			&raw_data(page.pixels)[offset],
			page.width*page.bytes_per_pixel,
		)
		page.dirty = {}
	}
}

collect_retired :: proc(value: ^Context) {
	if value == nil {return}
	for &page in value.retired_pages {destroy_page(value, &page)}
	clear(&value.retired_pages)
}

offset_for_utf16_index :: proc(run: ^Shaped_Run, index: int, backing_scale: f32) -> f32 {
	if run == nil || run.line == nil {return 0}
	return f32(CTLineGetOffsetForStringIndex(run.line, index, nil))/max(backing_scale, 1)
}

utf16_index_for_offset :: proc(run: ^Shaped_Run, x: f32, backing_scale: f32) -> int {
	if run == nil || run.line == nil {return 0}
	return CTLineGetStringIndexForPosition(run.line, {f64(x*max(backing_scale, 1)), 0})
}
