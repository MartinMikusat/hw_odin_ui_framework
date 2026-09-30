package directwrite

import "core:mem"
import win "core:sys/windows"
import atlas "ui_framework:glyphatlas"
import draw "ui_framework:draw"
import ui "ui_framework:core"

ATLAS_SIDE :: 2048
ATLAS_PAGES_MAX :: 4
ATLAS_ENTRIES_MAX :: 65536
ATLAS_PADDING :: 2

Atlas_Key :: struct {
    font:uintptr,
    size,scale,measuring:u32,
    index:u16,
    phase:u8,
}
Atlas_Entry :: struct {
    page:int,
    pixels:atlas.Dirty_Rect,
    offset,size:ui.Vec2,
}
Atlas_Page :: struct {
    packing:atlas.Packing,
    pixels:[]u8,
    native:u64,
    dirty:atlas.Dirty_Rect,
    bound_frame:u64,
    texture:draw.Texture_Handle,
}
Glyph_Atlas :: struct {
    allocator:mem.Allocator,
    pages,retired:[dynamic]Atlas_Page,
    entries:map[Atlas_Key]Atlas_Entry,
    io:atlas.IO,
    frame:u64,
    scale:f32,
    retired_this_frame:bool,
}

atlas_init :: proc(value:^Glyph_Atlas,allocator:mem.Allocator) {
    value^={allocator=allocator,scale=1}
    value.pages=make([dynamic]Atlas_Page,allocator)
    value.retired=make([dynamic]Atlas_Page,allocator)
    value.entries=make(map[Atlas_Key]Atlas_Entry,allocator)
}

atlas_page_destroy :: proc(value:^Glyph_Atlas,page:^Atlas_Page) {
    if page.native!=0 {value.io.destroy(value.io.user_data,page.native)}
    delete(page.pixels,value.allocator)
    page^={}
}

atlas_clear_entries :: proc(value:^Glyph_Atlas) {
    for key in value.entries {_=(cast(^win.IUnknown)key.font)->Release()}
    clear(&value.entries)
}

atlas_destroy :: proc(value:^Glyph_Atlas) {
    atlas_clear_entries(value)
    for &page in value.pages {atlas_page_destroy(value,&page)}
    for &page in value.retired {atlas_page_destroy(value,&page)}
    delete(value.pages)
    delete(value.retired)
    delete(value.entries)
    value^={}
}

begin_frame :: proc(state:^Context,scale:f32,io:atlas.IO)->win.HRESULT {
    assert(state!=nil && state.factory!=nil)
    if !(scale>=1 && scale<=8) || io.create==nil || io.upload==nil ||
       io.bind==nil || io.destroy==nil {return INVALID_ARGUMENT}
    value:=&state.atlas
    if len(value.pages)+len(value.retired)>0 {
        assert(value.io.user_data==io.user_data)
        assert(value.io.create==io.create && value.io.destroy==io.destroy)
        assert(value.io.upload==io.upload && value.io.bind==io.bind)
    }
    for &page in value.retired {atlas_page_destroy(value,&page)}
    clear(&value.retired)
    value.io=io
    value.frame+=1
    state.text_error=0
    value.scale=scale
    value.retired_this_frame=false
    return 0
}

atlas_retire :: proc(value:^Glyph_Atlas)->bool {
    if value.retired_this_frame {return false}
    assert(len(value.retired)==0)
    _,err:=append(&value.retired,..value.pages[:])
    if err!=nil {return false}
    clear(&value.pages)
    atlas_clear_entries(value)
    value.retired_this_frame=true
    return true
}

atlas_allocate :: proc(value:^Glyph_Atlas,width,height:int)->(int,int,int,win.HRESULT) {
    if width<=0 || height<=0 || width>ATLAS_SIDE || height>ATLAS_SIDE {return 0,0,0,INVALID_ARGUMENT}
    for &page,index in value.pages {
        if x,y,ok:=atlas.allocate(&page.packing,width,height);ok {return index,x,y,0}
    }
    if len(value.pages)==ATLAS_PAGES_MAX && !atlas_retire(value) {return 0,0,0,OUT_OF_MEMORY}
    page:=Atlas_Page{packing={width=ATLAS_SIDE,height=ATLAS_SIDE}}
    page.pixels=make([]u8,ATLAS_SIDE*ATLAS_SIDE,value.allocator)
    if page.pixels==nil {return 0,0,0,OUT_OF_MEMORY}
    page.native=value.io.create(value.io.user_data,.Alpha,ATLAS_SIDE,ATLAS_SIDE)
    if page.native==0 {delete(page.pixels,value.allocator);return 0,0,0,OUT_OF_MEMORY}
    _,err:=append(&value.pages,page)
    if err!=nil {atlas_page_destroy(value,&page);return 0,0,0,OUT_OF_MEMORY}
    index:=len(value.pages)-1
    x,y,ok:=atlas.allocate(&value.pages[index].packing,width,height)
    assert(ok)
    assert(len(value.pages)+len(value.retired)<=ATLAS_PAGES_MAX*2)
    return index,x,y,0
}

atlas_glyph :: proc(state:^Context,glyph:Glyph,phase:u8)->(Atlas_Entry,win.HRESULT) {
    value:=&state.atlas
    key:=Atlas_Key{uintptr(glyph.font),transmute(u32)glyph.size,transmute(u32)value.scale,glyph.measuring,glyph.index,phase}
    if entry,found:=value.entries[key];found {return entry,0}
    if len(value.entries)==ATLAS_ENTRIES_MAX && !atlas_retire(value) {return {},OUT_OF_MEMORY}
    mask,status:=glyph_mask(state,glyph,value.scale,phase)
    if status<0 {return {},status}
    defer glyph_mask_destroy(&mask)
    entry:=Atlas_Entry{page=-1}
    if len(mask.pixels)>0 {
        width:=int(mask.bounds.right-mask.bounds.left)
        height:=int(mask.bounds.bottom-mask.bounds.top)
        page_index,x,y,allocation_status:=atlas_allocate(value,width+ATLAS_PADDING*2,height+ATLAS_PADDING*2)
        if allocation_status<0 {return {},allocation_status}
        page:=&value.pages[page_index]
        for row in 0..<height {
            offset:=(y+ATLAS_PADDING+row)*ATLAS_SIDE+x+ATLAS_PADDING
            copy(page.pixels[offset:offset+width],mask.pixels[row*width:(row+1)*width])
        }
        rect:=atlas.Dirty_Rect{x,y,width+ATLAS_PADDING*2,height+ATLAS_PADDING*2,true}
        atlas.mark_dirty(&page.dirty,rect)
        entry={
            page=page_index,pixels=rect,
            offset={(f32(mask.bounds.left-ATLAS_PADDING)-f32(atlas.phase_offset(phase)))/value.scale,f32(-mask.bounds.bottom-ATLAS_PADDING)/value.scale},
            size={f32(rect.w)/value.scale,f32(rect.h)/value.scale},
        }
    }
    // Each cache key retains its font identity until that generation is retired.
    slot:=map_insert(&value.entries,key,entry)
    if slot==nil {return {},OUT_OF_MEMORY}
    _=glyph.font->AddRef()
    return entry,0
}

// On failure, discard this frame's draw list rather than presenting partial text.
emit_layout :: proc(state:^Context,list:^draw.List,layout:^Layout,glyphs:^Glyph_Buffer,rect:draw.Rect,style:ui.Text_Style,color:draw.Color,label:string="")->win.HRESULT {
    assert(state!=nil && list!=nil && layout!=nil && glyphs!=nil)
    assert(state.atlas.frame>0)
    width:=layout.metrics.width_with_whitespace
    x:=rect.x+style.inset
    switch style.horizontal {
    case .Start:
    case .Center:x=rect.x+(rect.w-width)/2
    case .End:x=rect.x+rect.w-style.inset-width
    }
    top:=rect.y+style.inset+layout.metrics.height
    switch style.vertical {
    case .Start:
    case .Center:top=rect.y+(rect.h+layout.metrics.height)/2
    case .End:top=rect.y+rect.h-style.inset
    }
    draw.push_clip(list,rect)
    defer draw.pop_clip(list)
    return emit_glyphs(state,list,glyphs,{x,top},color,label)
}

emit_glyphs :: proc(state:^Context,list:^draw.List,glyphs:^Glyph_Buffer,top_left:ui.Vec2,color:draw.Color,label:string)->win.HRESULT {
    value:=&state.atlas
    for glyph in glyphs.glyphs {
        pen_x:=top_left.x+glyph.x
        entry,status:=atlas_glyph(state,glyph,atlas.phase_index(value.scale,pen_x))
        if status<0 {return status}
        if entry.page<0 {continue}
        page:=&value.pages[entry.page]
        if page.bound_frame!=value.frame {
            page.texture=value.io.bind(value.io.user_data,page.native)
            page.bound_frame=value.frame
        }
        if page.texture==0 {return OUT_OF_MEMORY}
        ink:=color
        if glyph.colored {ink=glyph.color;ink[3]*=color[3]}
        dst:=draw.Rect{pen_x+entry.offset.x,atlas.snap_to_pixel(value.scale,top_left.y-glyph.y)+entry.offset.y,entry.size.x,entry.size.y}
        src:=draw.Rect{f32(entry.pixels.x)/ATLAS_SIDE,f32(entry.pixels.y+entry.pixels.h)/ATLAS_SIDE,f32(entry.pixels.w)/ATLAS_SIDE,-f32(entry.pixels.h)/ATLAS_SIDE}
        draw.image(list,page.texture,dst,src,ink,.Alpha_Mask,kind=.Glyph,label=label)
    }
    return 0
}

flush :: proc(state:^Context) {
    assert(state!=nil)
    value:=&state.atlas
    groups:=[2][]Atlas_Page{value.pages[:],value.retired[:]}
    for pages in groups {
        for &page in pages {
            if !page.dirty.valid {continue}
            rect:=page.dirty
            value.io.upload(value.io.user_data,page.native,.Alpha,rect.x,rect.y,rect.w,rect.h,&page.pixels[rect.y*ATLAS_SIDE+rect.x],ATLAS_SIDE)
            page.dirty={}
        }
    }
}
