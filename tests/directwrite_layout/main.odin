package main

import "core:fmt"
import "core:mem"
import "core:strings"
import text "ui_framework:directwrite"

main :: proc() {
    tracking:mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking,context.allocator)
    defer mem.tracking_allocator_destroy(&tracking)
    context.allocator=mem.tracking_allocator(&tracking)
    verify_layout()
    assert(len(tracking.allocation_map)==0 && len(tracking.bad_free_array)==0)
    fmt.println("DirectWrite layout, Unicode wrapping, caret positions and cleanup passed.")
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
}
