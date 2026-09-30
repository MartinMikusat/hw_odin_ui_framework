package directwrite

import "core:math"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"
import "core:unicode/utf16"
import win "core:sys/windows"

TEXT_BYTES_MAX :: 512*1024
DOCUMENT_BYTES_MAX :: 8*1024*1024
LAYOUT_EXTENT_MAX :: f32(1e9)
INVALID_ARGUMENT :: win.HRESULT(-2147024809)
OUT_OF_MEMORY :: win.HRESULT(-2147024882)

Context :: struct {
    factory:^Factory,
    factory2:^Factory2,
    allocator:mem.Allocator,
    atlas:Glyph_Atlas,
    fonts:[dynamic]Font_Entry,
    runs:[dynamic]Prepared_Run,
    run_index:map[Run_Key]int,
    run_bytes:int,
    font_generation:u64,
    text_error:win.HRESULT,
    embedded_font:Embedded_Font,
}

Layout :: struct {
    native:^Text_Layout,
    text:string,
    utf16_length:u32,
    metrics:Text_Metrics,
    allocator:mem.Allocator,
}

Line_Range :: struct {byte_start,byte_end,next_byte:int}

context_init :: proc(value:^Context, allocator:=context.allocator)->win.HRESULT {
    assert(value!=nil && value.factory==nil)
    factory:rawptr
    result:=DWriteCreateFactory(1,&FACTORY2_IID,&factory)
    if result<0 {return result}
    assert(factory!=nil)
    value^={factory=cast(^Factory)factory,factory2=cast(^Factory2)factory,allocator=allocator}
    atlas_init(&value.atlas,allocator)
    value.fonts=make([dynamic]Font_Entry,allocator)
    runs,run_error:=make([dynamic]Prepared_Run,0,RUN_LIMIT,allocator)
    if run_error!=nil {context_destroy(value);return OUT_OF_MEMORY}
    value.runs=runs
    value.run_index=make(map[Run_Key]int,allocator)
    return result
}

context_destroy :: proc(value:^Context) {
    assert(value!=nil)
    for &run in value.runs {release_prepared_run(value,&run)}
    delete(value.runs)
    delete(value.run_index)
    for font in value.fonts {delete(font.name,value.allocator)}
    delete(value.fonts)
    atlas_destroy(&value.atlas)
    embedded_font_destroy(value,&value.embedded_font)
    if value.factory!=nil {_=value.factory.Release(cast(^win.IUnknown)value.factory)}
    value^={}
}

layout_destroy :: proc(value:^Layout) {
    assert(value!=nil)
    if value.native!=nil {_=(cast(^win.IUnknown)value.native)->Release()}
    if value.text!="" {delete(value.text,value.allocator)}
    value^={}
}

// Layout owns both the native shaped text and its UTF-8 source until destroy.
layout_create :: proc(value:^Context, text,family:string, size,width:f32, wrap:bool,tracking:=f32(0),truncate:=false,collection:^Font_Collection=nil,tab_width:=f32(0))->(Layout,win.HRESULT) {
    return layout_create_bounded(value,text,family,size,width,wrap,tracking,truncate,collection,tab_width,TEXT_BYTES_MAX)
}

@(private)
layout_create_bounded :: proc(value:^Context,text,family:string,size,width:f32,wrap:bool,tracking:f32,truncate:bool,collection:^Font_Collection,tab_width:f32,byte_limit:int)->(Layout,win.HRESULT) {
    assert(byte_limit==TEXT_BYTES_MAX || byte_limit==DOCUMENT_BYTES_MAX)
    assert(value!=nil && value.factory!=nil)
    if len(text)>byte_limit || len(family)==0 || len(family)>256 ||
       !utf8.valid_string(text) || !utf8.valid_string(family) || strings.contains(family,"\x00") ||
       (math.is_nan(size) || math.is_inf(size)) || size<=0 || size>1024 ||
       (math.is_nan(tracking) || math.is_inf(tracking)) || abs(tracking)>1024 ||
       (math.is_nan(tab_width) || math.is_inf(tab_width)) || tab_width<0 || tab_width>LAYOUT_EXTENT_MAX ||
       (math.is_nan(width) || math.is_inf(width)) || width<=0 || width>LAYOUT_EXTENT_MAX {return {},INVALID_ARGUMENT}
    wide:=make([]u16,len(text)+1,value.allocator)
    if wide==nil {return {},OUT_OF_MEMORY}
    defer delete(wide,value.allocator)
    length:=utf16.encode_string(wide,text)
    name:[257]u16
    _=utf16.encode_string(name[:],family)
    locale:=[1]u16{0}
    format:^Text_Format
    status:=value.factory->CreateTextFormat(raw_data(name[:]),collection,400,0,5,size,raw_data(locale[:]),&format)
    if status<0 {return {},status}
    assert(format!=nil)
    defer _=format.Release(cast(^win.IUnknown)format)
    status=format->SetWordWrapping(wrap ? 0 : 1)
    if status<0 {return {},status}
    if tab_width>0 {
        status=format->SetIncrementalTabStop(tab_width)
        if status<0 {return {},status}
    }
    if truncate {
        sign:^Inline_Object
        status=value.factory->CreateEllipsisTrimmingSign(format,&sign)
        if status<0 {return {},status}
        defer _=sign.Release(cast(^win.IUnknown)sign)
        options:=Trimming{granularity=1}
        status=format->SetTrimming(&options,sign)
        if status<0 {return {},status}
    }
    layout:=Layout{allocator=value.allocator,utf16_length=u32(length)}
    status=value.factory->CreateTextLayout(raw_data(wide),u32(length),format,width,LAYOUT_EXTENT_MAX,&layout.native)
    if status<0 {return {},status}
    assert(layout.native!=nil)
    if tracking!=0 {
        extended:^Text_Layout1
        status=(cast(^win.IUnknown)layout.native)->QueryInterface(&TEXT_LAYOUT1_IID,cast(^rawptr)&extended)
        if status<0 {layout_destroy(&layout);return {},status}
        assert(extended!=nil)
        status=extended->SetCharacterSpacing(0,tracking,0,{length=u32(length)})
        _=(cast(^win.IUnknown)extended)->Release()
        if status<0 {layout_destroy(&layout);return {},status}
    }
    status=layout.native->GetMetrics(&layout.metrics)
    if status<0 {layout_destroy(&layout);return {},status}
    if truncate {
        layout.metrics.width=min(layout.metrics.width,width)
        layout.metrics.width_with_whitespace=min(layout.metrics.width_with_whitespace,width)
    }
    if text!="" {
        copy,err:=strings.clone(text,value.allocator)
        if err!=nil {layout_destroy(&layout);return {},OUT_OF_MEMORY}
        layout.text=copy
    }
    return layout,status
}

line_ranges :: proc(value:^Layout, allocator:=context.allocator)->([]Line_Range,win.HRESULT) {
    assert(value!=nil && value.native!=nil)
    count:=value.metrics.line_count
    if count==0 || count>u32(len(value.text)+1) {return {},INVALID_ARGUMENT}
    metrics:=make([]Line_Metrics,int(count),allocator)
    if metrics==nil {return {},OUT_OF_MEMORY}
    defer delete(metrics,allocator)
    actual:u32
    status:=value.native->GetLineMetrics(raw_data(metrics),count,&actual)
    if status<0 {return {},status}
    assert(actual==count)
    ranges:=make([]Line_Range,int(count),allocator)
    if ranges==nil {return {},OUT_OF_MEMORY}
    byte_start,utf16_start:=0,u32(0)
    for line,index in metrics {
        assert(line.length<=value.utf16_length-utf16_start)
        assert(line.newline_length<=line.length)
        byte_next:=byte_start
        byte_end:=byte_start
        content_units:=line.length-line.newline_length
        units:=u32(0)
        for character,offset in value.text[byte_start:] {
            if units>=line.length {break}
            units+=character>0xffff ? 2 : 1
            byte_next=byte_start+offset+utf8.rune_size(character)
            if units<=content_units {byte_end=byte_next}
        }
        assert(units==line.length)
        ranges[index]={byte_start,byte_end,byte_next}
        byte_start=byte_next
        utf16_start+=line.length
    }
    assert(byte_start==len(value.text) && utf16_start==value.utf16_length)
    return ranges,status
}

caret_position :: proc(value:^Layout, utf16_index:u32, trailing:bool=false)->(f32,f32,win.HRESULT) {
    assert(value!=nil && value.native!=nil)
    if utf16_index>value.utf16_length {return 0,0,INVALID_ARGUMENT}
    x,y:f32
    metrics:Hit_Test_Metrics
    status:=value.native->HitTestTextPosition(utf16_index,win.BOOL(trailing),&x,&y,&metrics)
    return x,y,status
}

caret_index :: proc(value:^Layout,x,y:f32)->(u32,win.HRESULT) {
    assert(value!=nil && value.native!=nil)
    if (math.is_nan(x) || math.is_inf(x)) || (math.is_nan(y) || math.is_inf(y)) {return 0,INVALID_ARGUMENT}
    trailing,inside:win.BOOL
    metrics:Hit_Test_Metrics
    status:=value.native->HitTestPoint(x,y,&trailing,&inside,&metrics)
    if status<0 {return 0,status}
    index:=metrics.position
    if bool(trailing) {index+=metrics.length}
    assert(index<=value.utf16_length)
    return index,status
}
