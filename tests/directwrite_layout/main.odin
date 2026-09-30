package main

import "core:fmt"
import "core:mem"
import "core:strings"
import text "ui_framework:directwrite"
import atlas "ui_framework:glyphatlas"
import draw "ui_framework:draw"
import ui "ui_framework:core"

Atlas_Check :: struct {created,destroyed,uploaded,bound:int}

atlas_create :: proc(raw:rawptr,format:atlas.Format,width,height:int)->u64 {
    assert(format==.Alpha && width==text.ATLAS_SIDE && height==text.ATLAS_SIDE)
    value:=cast(^Atlas_Check)raw
    value.created+=1
    return u64(value.created)
}
atlas_destroy :: proc(raw:rawptr,native:u64) {
    assert(native>0)
    (cast(^Atlas_Check)raw).destroyed+=1
}
atlas_upload :: proc(raw:rawptr,native:u64,format:atlas.Format,x,y,width,height:int,pixels:[^]u8,stride:int) {
    assert(native>0 && format==.Alpha && pixels!=nil && stride==text.ATLAS_SIDE)
    assert(x>=0 && y>=0 && width>0 && height>0 && x+width<=stride && y+height<=stride)
    (cast(^Atlas_Check)raw).uploaded+=1
}
atlas_bind :: proc(raw:rawptr,native:u64)->draw.Texture_Handle {
    (cast(^Atlas_Check)raw).bound+=1
    return draw.Texture_Handle(native)
}

main :: proc() {
    tracking:mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking,context.allocator)
    defer mem.tracking_allocator_destroy(&tracking)
    context.allocator=mem.tracking_allocator(&tracking)
    verify_layout()
    verify_layout_style()
    verify_backend()
    verify_atlas_bounds()
    assert(len(tracking.allocation_map)==0 && len(tracking.bad_free_array)==0)
    fmt.println("DirectWrite layout, Unicode wrapping, caret positions and cleanup passed.")
}

verify_backend :: proc() {
    state:text.Context
    assert(text.context_init(&state)>=0)
    defer text.context_destroy(&state)
    assert(text.register_font(&state,ui.Font_Handle(1),"Consolas")>=0)
    fake:Atlas_Check
    io:=atlas.IO{&fake,atlas_create,atlas_upload,atlas_destroy,atlas_bind}
    assert(text.begin_frame(&state,2,io)>=0)
    backend:=text.backend(&state)
    prepared:=backend.prepare(backend.user_data,ui.Font_Handle(1),"cached text",12,0,0,false)
    assert(prepared.run!=ui.Text_Run_ID(0) && prepared.metrics.width>0 && prepared.metrics.ascent>0)
    bytes:=state.run_bytes
    same:=backend.prepare(backend.user_data,ui.Font_Handle(1),"cached text",12,0,0,false)
    assert(same==prepared && state.run_bytes==bytes && len(state.runs)==1)
    held:=text.shape(&state,ui.Font_Handle(1),"cached text",12,0,0,false)
    assert(held!=nil && held.metrics==prepared.metrics)
    unconstrained,unconstrained_status:=text.prepare_run(&state,ui.Font_Handle(1),"zero width",12,0,0,true)
    assert(unconstrained_status>=0 && unconstrained.metrics.width>0)
    tabs,tab_status:=text.prepare_run(&state,ui.Font_Handle(1),"a\tb",12,0,0,false,42)
    wider,wider_status:=text.prepare_run(&state,ui.Font_Handle(1),"a\tb",12,0,0,false,49)
    assert(tab_status>=0 && wider_status>=0 && tabs.run!=wider.run && tabs.metrics.width<wider.metrics.width)
    list:draw.List
    draw.list_init(&list)
    defer draw.list_destroy(&list)
    backend.emit(backend.user_data,&list,prepared.run,"cached",{0,0,200,40},{size=12},{1,1,1,1})
    assert(state.text_error>=0 && len(list.batches)>0)
    text.flush(&state)
    assert(fake.uploaded>0)
    for i in 4..<text.RUN_LIMIT {
        source:=fmt.tprintf("run %d",i)
        run,status:=text.prepare_run(&state,ui.Font_Handle(1),source,12,0,0,false)
        assert(status>=0 && run.run!=ui.Text_Run_ID(0))
    }
    assert(len(state.runs)==text.RUN_LIMIT && len(state.run_index)==text.RUN_LIMIT && state.run_bytes<=text.RUN_BYTES_MAX)
    assert(held==&state.runs[0] && held.layout.text=="cached text")
    text.emit_shaped_run(&state,&list,held,{0,20},{1,1,1,1})
    assert(state.text_error>=0)
    _,full_status:=text.prepare_run(&state,ui.Font_Handle(1),"one more",12,0,0,false)
    assert(full_status==text.OUT_OF_MEMORY && len(state.run_index)==text.RUN_LIMIT)
    assert(text.begin_frame(&state,2,io)>=0)
    replacement,replacement_status:=text.prepare_run(&state,ui.Font_Handle(1),"one more",12,0,0,false)
    assert(replacement_status>=0 && replacement.run!=ui.Text_Run_ID(0))
    assert(len(state.runs)==text.RUN_LIMIT && len(state.run_index)==text.RUN_LIMIT && state.run_bytes<=text.RUN_BYTES_MAX)
    backend.emit(backend.user_data,&list,ui.Text_Run_ID(text.RUN_LIMIT),"stale",{0,0,200,40},{size=12},{1,1,1,1})
    assert(state.text_error==text.INVALID_ARGUMENT)
}

verify_layout_style :: proc() {
    state:text.Context
    assert(text.context_init(&state)>=0)
    defer text.context_destroy(&state)
    plain,status:=text.layout_create(&state,"ABCDEFGHIJKLMNOPQRSTUVWXYZ","Consolas",12,1000,false)
    assert(status>=0)
    defer text.layout_destroy(&plain)
    spaced,spacing_status:=text.layout_create(&state,plain.text,"Consolas",12,1000,false,2)
    assert(spacing_status>=0 && spaced.metrics.width>plain.metrics.width)
    defer text.layout_destroy(&spaced)
    tabs,tab_status:=text.layout_create(&state,"a\tb\tc","Consolas",12,1000,false,tab_width=42)
    assert(tab_status>=0)
    defer text.layout_destroy(&tabs)
    first,_,first_status:=text.caret_position(&tabs,2)
    second,_,second_status:=text.caret_position(&tabs,4)
    assert(first_status>=0 && second_status>=0 && abs(first-42)<0.01 && abs(second-84)<0.01)
    trimmed,trimming_status:=text.layout_create(&state,plain.text,"Consolas",12,40,false,0,true)
    assert(trimming_status>=0)
    defer text.layout_destroy(&trimmed)
    line:text.Line_Metrics
    count:u32
    assert(trimmed.native->GetLineMetrics(&line,1,&count)>=0 && count==1 && bool(line.trimmed))
    full_glyphs,full_status:=text.layout_glyphs(&state,&plain)
    assert(full_status>=0)
    defer text.glyph_buffer_destroy(&full_glyphs)
    glyphs,glyph_status:=text.layout_glyphs(&state,&trimmed)
    assert(glyph_status>=0 && len(glyphs.glyphs)>0 && len(glyphs.glyphs)<len(full_glyphs.glyphs))
    defer text.glyph_buffer_destroy(&glyphs)
}

verify_layout :: proc() {
    state:text.Context
    assert(text.context_init(&state)>=0)
    defer text.context_destroy(&state)
    source:="alpha beta\r\n\ncafé 😀 gamma\n"
    layout,status:=text.layout_create(&state,source,"Consolas",12,70,true)
    assert(status>=0 && layout.native!=nil)
    defer text.layout_destroy(&layout)
    assert(layout.metrics.width>0 && layout.metrics.height>0)
    ranges,line_status:=text.line_ranges(&layout)
    assert(line_status>=0 && len(ranges)>=4)
    defer delete(ranges)
    next:=0
    blank,unicode:=false,false
    for line in ranges {
        assert(line.byte_start==next)
        assert(line.byte_start<=line.byte_end && line.byte_end<=line.next_byte)
        if line.byte_start==line.byte_end {blank=true}
        if strings.contains(layout.text[line.byte_start:line.byte_end],"😀") {unicode=true}
        next=line.next_byte
    }
    assert(next==len(source) && blank && unicode)
    separators,separators_status:=text.layout_create(&state,"a\u2028b\r\nc\n","Consolas",12,1000,true)
    assert(separators_status>=0)
    defer text.layout_destroy(&separators)
    separated,separated_status:=text.line_ranges(&separators)
    assert(separated_status>=0 && len(separated)==4)
    defer delete(separated)
    assert(separators.text[separated[0].byte_start:separated[0].byte_end]=="a")
    assert(separators.text[separated[1].byte_start:separated[1].byte_end]=="b")
    assert(separators.text[separated[2].byte_start:separated[2].byte_end]=="c")
    assert(separated[3].byte_start==len(separators.text) && separated[3].byte_end==len(separators.text))
    x,y,position_status:=text.caret_position(&layout,3)
    assert(position_status>=0 && x>0)
    index,index_status:=text.caret_index(&layout,x,y)
    assert(index_status>=0 && index==3)
    _,_,invalid_position:=text.caret_position(&layout,layout.utf16_length+1)
    assert(invalid_position==text.INVALID_ARGUMENT)
    empty,empty_status:=text.layout_create(&state,"","Consolas",12,70,true)
    assert(empty_status>=0)
    text.layout_destroy(&empty)
    text.layout_destroy(&empty)
    assert(empty.native==nil && empty.text=="")
    narrow,narrow_status:=text.layout_create(&state,"😀😀","Consolas",12,1,true)
    assert(narrow_status>=0)
    defer text.layout_destroy(&narrow)
    narrow_ranges,narrow_lines_status:=text.line_ranges(&narrow)
    assert(narrow_lines_status>=0 && len(narrow_ranges)==2)
    defer delete(narrow_ranges)
    assert(narrow_ranges[0].byte_end==len("😀"))
    bad,bad_status:=text.layout_create(&state,"\xff","Consolas",12,70,true)
    assert(bad_status==text.INVALID_ARGUMENT && bad.native==nil)
    bad_font,bad_font_status:=text.layout_create(&state,"hello","bad\x00font",12,70,true)
    assert(bad_font_status==text.INVALID_ARGUMENT && bad_font.native==nil)
    bad_width,bad_width_status:=text.layout_create(&state,"hello","Consolas",12,0,true)
    assert(bad_width_status==text.INVALID_ARGUMENT && bad_width.native==nil)
    oversized:=strings.repeat("x",text.TEXT_BYTES_MAX+1) or_else ""
    assert(len(oversized)==text.TEXT_BYTES_MAX+1)
    defer delete(oversized)
    bad_size,bad_size_status:=text.layout_create(&state,oversized,"Consolas",12,70,true)
    assert(bad_size_status==text.INVALID_ARGUMENT && bad_size.native==nil)
    glyph_layout,glyph_layout_status:=text.layout_create(&state,"office café 😀 العربية","Consolas",12,1000,false)
    assert(glyph_layout_status>=0)
    glyphs,glyph_status:=text.layout_glyphs(&state,&glyph_layout)
    assert(glyph_status>=0 && len(glyphs.glyphs)>0 && len(glyphs.fonts)>0)
    defer text.glyph_buffer_destroy(&glyphs)
    text.layout_destroy(&glyph_layout)
    ink,antialias:=false,false
    for glyph in glyphs.glyphs {
        mask,mask_status:=text.glyph_mask(&state,glyph,2,1)
        assert(mask_status>=0)
        for pixel in mask.pixels {
            if pixel>0 {ink=true}
            if pixel>0 && pixel<255 {antialias=true}
        }
        text.glyph_mask_destroy(&mask)
        assert(mask.pixels==nil)
    }
    assert(ink && antialias)
    bad_scale,bad_scale_status:=text.glyph_mask(&state,glyphs.glyphs[0],0,0)
    assert(bad_scale_status==text.INVALID_ARGUMENT && bad_scale.pixels==nil)
    output:draw.List
    draw.list_init(&output)
    defer draw.list_destroy(&output)
    fake:Atlas_Check
    io:=atlas.IO{&fake,atlas_create,atlas_upload,atlas_destroy,atlas_bind}
    assert(text.begin_frame(&state,2,io)>=0)
    emit_layout,emit_layout_status:=text.layout_create(&state,"office café 😀 العربية","Consolas",12,1000,false)
    assert(emit_layout_status>=0)
    defer text.layout_destroy(&emit_layout)
    assert(text.emit_layout(&state,&output,&emit_layout,&glyphs,{0,0,1000,40},{size=12,vertical=.Center},{1,1,1,1})>=0)
    assert(len(output.batches)>0 && len(output.trace)>0 && fake.created==1 && fake.bound==1)
    cache_count:=len(state.atlas.entries)
    assert(cache_count>0)
    text.flush(&state)
    assert(fake.uploaded==1)
    draw.list_reset(&output)
    assert(text.begin_frame(&state,2,io)>=0)
    assert(text.emit_layout(&state,&output,&emit_layout,&glyphs,{0,0,1000,40},{size=12,vertical=.Center},{1,1,1,1})>=0)
    text.flush(&state)
    assert(fake.created==1 && fake.uploaded==1 && fake.bound==2)
    assert(len(state.atlas.entries)==cache_count)
    text.context_destroy(&state)
    assert(fake.destroyed==fake.created)
}

verify_atlas_bounds :: proc() {
    state:text.Context
    assert(text.context_init(&state)>=0)
    defer text.context_destroy(&state)
    fake:Atlas_Check
    io:=atlas.IO{&fake,atlas_create,atlas_upload,atlas_destroy,atlas_bind}
    assert(text.begin_frame(&state,2,io)>=0)
    for _ in 0..<text.ATLAS_PAGES_MAX*2 {
        _,_,_,status:=text.atlas_allocate(&state.atlas,text.ATLAS_SIDE,text.ATLAS_SIDE)
        assert(status>=0)
    }
    _,_,_,exhausted:=text.atlas_allocate(&state.atlas,text.ATLAS_SIDE,text.ATLAS_SIDE)
    assert(exhausted==text.OUT_OF_MEMORY && fake.created==text.ATLAS_PAGES_MAX*2)
    assert(len(state.atlas.pages)==text.ATLAS_PAGES_MAX && len(state.atlas.retired)==text.ATLAS_PAGES_MAX)
    assert(text.begin_frame(&state,2,io)>=0 && fake.destroyed==text.ATLAS_PAGES_MAX)
    _,_,_,retry:=text.atlas_allocate(&state.atlas,text.ATLAS_SIDE,text.ATLAS_SIDE)
    assert(retry>=0)
    text.context_destroy(&state)
    assert(fake.destroyed==fake.created)
}
