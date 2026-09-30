package directwrite

import "core:strings"
import "core:unicode/utf8"
import ui "ui_framework:core"
import draw "ui_framework:draw"
import win "core:sys/windows"

RUN_LIMIT :: 4096
RUN_BYTES_MAX :: 128*1024*1024
FONT_LIMIT :: 256

Font_Entry :: struct {handle:ui.Font_Handle,name:string,collection:^Font_Collection}

font_entry :: proc(value:^Context,handle:ui.Font_Handle)->^Font_Entry {
    for &entry in value.fonts {if entry.handle==handle {return &entry}}
    return nil
}

wrap_line_ranges :: proc(value:^Context,font:ui.Font_Handle,text:string,size,tracking,maximum_width:f32,allocator:=context.allocator,tab_width:=f32(0))->([]Line_Range,win.HRESULT) {
    assert(value!=nil && value.factory!=nil)
    entry:=font_entry(value,font)
    if entry==nil {return {},INVALID_ARGUMENT}
    layout,status:=layout_create(value,text,entry.name,size,maximum_width,true,tracking,false,entry.collection,tab_width)
    if status<0 {return {},status}
    defer layout_destroy(&layout)
    return line_ranges(&layout,allocator)
}
// The document owner destroys this layout before its font context; it is not cached.
document_layout_create :: proc(value:^Context,font:ui.Font_Handle,text:string,size,tracking,maximum_width:f32,tab_width:=f32(0),wrap:bool=true)->(Layout,win.HRESULT) {
    assert(value!=nil && value.factory!=nil)
    entry:=font_entry(value,font)
    if entry==nil {return {},INVALID_ARGUMENT}
    layout,status:=layout_create_bounded(value,text,entry.name,size,maximum_width,wrap,tracking,false,entry.collection,tab_width,DOCUMENT_BYTES_MAX)
    if status>=0 {layout.document_owner=value;value.document_count+=1}
    return layout,status
}
Run_Key :: struct {
    font:ui.Font_Handle,
    generation:u64,
    text:string,
    size,tracking,width,tab_width:u32,
    truncate:bool,
}
Prepared_Run :: struct {
    key:Run_Key,
    layout:Layout,
    glyphs:Glyph_Buffer,
    metrics:ui.Text_Metrics,
    frame:u64,
    bytes:int,
    live:bool,
}

register_font :: proc(value:^Context,handle:ui.Font_Handle,name:string)->win.HRESULT {
    assert(value!=nil && value.factory!=nil)
    if handle==ui.Font_Handle(0) || len(name)==0 || len(name)>256 ||
       !utf8.valid_string(name) || strings.contains(name,"\x00") {return INVALID_ARGUMENT}
    index:=-1
    for font,i in value.fonts {
        if font.handle==handle {
            if font.name==name {return 0}
            if font.collection!=nil {return INVALID_ARGUMENT}
            index=i
            break
        }
    }
    if index<0 && len(value.fonts)>=FONT_LIMIT {return OUT_OF_MEMORY}
    owned,err:=strings.clone(name,value.allocator)
    if err!=nil {return OUT_OF_MEMORY}
    if index>=0 {
        delete(value.fonts[index].name,value.allocator)
        value.fonts[index].name=owned
        value.fonts[index].collection=nil
    } else {
        _,append_error:=append(&value.fonts,Font_Entry{handle,owned,nil})
        if append_error!=nil {delete(owned,value.allocator);return OUT_OF_MEMORY}
    }
    assert(value.font_generation<~u64(0))
    value.font_generation+=1
    return 0
}

release_prepared_run :: proc(value:^Context,run:^Prepared_Run) {
    if !run.live {return}
    delete_key(&value.run_index,run.key)
    value.run_bytes-=run.bytes
    glyph_buffer_destroy(&run.glyphs)
    layout_destroy(&run.layout)
    run^={}
}

oldest_unpinned_run :: proc(value:^Context)->int {
    oldest:=~u64(0)
    result:=-1
    // ponytail: at most 4,096 slots per eviction; add an LRU list if this becomes costly.
    for run,index in value.runs {
        if run.live && run.frame<value.atlas.frame && run.frame<oldest {
            oldest=run.frame
            result=index
        }
    }
    return result
}

prepare_run :: proc(value:^Context,font:ui.Font_Handle,text:string,size,tracking,maximum_width:f32,truncate:bool,tab_width:=f32(0))->(ui.Prepared_Text,win.HRESULT) {
    assert(value!=nil && value.factory!=nil && value.atlas.frame>0)
    if len(text)>TEXT_BYTES_MAX {return {},INVALID_ARGUMENT}
    key:=Run_Key{font,value.font_generation,text,transmute(u32)size,transmute(u32)tracking,transmute(u32)maximum_width,transmute(u32)tab_width,truncate}
    if index,found:=value.run_index[key];found {
        run:=&value.runs[index]
        assert(run.live)
        run.frame=value.atlas.frame
        return {ui.Text_Run_ID(index+1),run.metrics},0
    }
    entry:=font_entry(value,font)
    if entry==nil {return {},INVALID_ARGUMENT}
    width:=maximum_width
    if width==0 {width=LAYOUT_EXTENT_MAX}
    layout,status:=layout_create(value,text,entry.name,size,width,false,tracking,truncate && maximum_width>0,entry.collection,tab_width)
    if status<0 {return {},status}
    glyphs,glyph_status:=layout_glyphs(value,&layout)
    if glyph_status<0 {layout_destroy(&layout);return {},glyph_status}
    bytes:=len(layout.text)+cap(glyphs.glyphs)*size_of(Glyph)+cap(glyphs.fonts)*size_of(^win.IUnknown)
    if bytes>RUN_BYTES_MAX {
        glyph_buffer_destroy(&glyphs)
        layout_destroy(&layout)
        return {},OUT_OF_MEMORY
    }
    count:u32
    _=layout.native->GetLineMetrics(nil,0,&count)
    if count==0 || count>TEXT_BYTES_MAX+1 {
        glyph_buffer_destroy(&glyphs)
        layout_destroy(&layout)
        return {},INVALID_ARGUMENT
    }
    lines:=make([]Line_Metrics,int(count),value.allocator)
    if lines==nil {glyph_buffer_destroy(&glyphs);layout_destroy(&layout);return {},OUT_OF_MEMORY}
    line_status:=layout.native->GetLineMetrics(raw_data(lines),count,&count)
    line:=lines[0]
    delete(lines,value.allocator)
    if line_status<0 {glyph_buffer_destroy(&glyphs);layout_destroy(&layout);return {},line_status}
    index:=-1
    for run,i in value.runs {if !run.live {index=i;break}}
    for value.run_bytes>RUN_BYTES_MAX-bytes || (index<0 && len(value.runs)>=RUN_LIMIT) {
        victim:=oldest_unpinned_run(value)
        if victim<0 {
            glyph_buffer_destroy(&glyphs)
            layout_destroy(&layout)
            return {},OUT_OF_MEMORY
        }
        release_prepared_run(value,&value.runs[victim])
        if index<0 {index=victim}
    }
    if index<0 {
        index=len(value.runs)
        _,err:=append(&value.runs,Prepared_Run{})
        if err!=nil {
            glyph_buffer_destroy(&glyphs)
            layout_destroy(&layout)
            return {},OUT_OF_MEMORY
        }
    }
    key.text=layout.text
    metrics:=ui.Text_Metrics{layout.metrics.width_with_whitespace,line.baseline,layout.metrics.height-line.baseline,0}
    value.runs[index]={key,layout,glyphs,metrics,value.atlas.frame,bytes,true}
    value.run_index[key]=index
    value.run_bytes+=bytes
    return {ui.Text_Run_ID(index+1),metrics},0
}

prepare_callback :: proc(data:rawptr,font:ui.Font_Handle,text:string,size,tracking,maximum_width:f32,truncate:bool)->ui.Prepared_Text {
    value:=cast(^Context)data
    result,status:=prepare_run(value,font,text,size,tracking,maximum_width,truncate)
    if status<0 && value.text_error>=0 {value.text_error=status}
    return result
}

// Runs stay at fixed addresses and remain pinned until the next begin_frame.
shape :: proc(value:^Context,font:ui.Font_Handle,text:string,size,tracking,maximum_width:f32,truncate:bool,tab_width:=f32(0))->^Prepared_Run {
    prepared,status:=prepare_run(value,font,text,size,tracking,maximum_width,truncate,tab_width)
    if status<0 {
        if value.text_error>=0 {value.text_error=status}
        return nil
    }
    return &value.runs[int(prepared.run)-1]
}

emit_shaped_run :: proc(value:^Context,list:^draw.List,run:^Prepared_Run,origin:ui.Vec2,color:draw.Color,label:string="") {
    assert(value!=nil && list!=nil)
    if run==nil || !run.live || run.frame!=value.atlas.frame {
        if value.text_error>=0 {value.text_error=INVALID_ARGUMENT}
        return
    }
    status:=emit_glyphs(value,list,&run.glyphs,{origin.x,origin.y+run.metrics.ascent},color,label)
    if status<0 && value.text_error>=0 {value.text_error=status}
}

emit_callback :: proc(data:rawptr,list:^draw.List,id:ui.Text_Run_ID,label:string,rect:draw.Rect,style:ui.Text_Style,color:draw.Color) {
    value:=cast(^Context)data
    if id==ui.Text_Run_ID(0) || u64(id)>u64(len(value.runs)) {
        if value.text_error>=0 {value.text_error=INVALID_ARGUMENT}
        return
    }
    run:=&value.runs[int(id)-1]
    if !run.live || run.frame!=value.atlas.frame {
        if value.text_error>=0 {value.text_error=INVALID_ARGUMENT}
        return
    }
    status:=emit_layout(value,list,&run.layout,&run.glyphs,rect,style,color,label)
    if status<0 && value.text_error>=0 {value.text_error=status}
}

backend :: proc(value:^Context)->ui.Text_Backend {
    return {value,prepare_callback,emit_callback}
}
