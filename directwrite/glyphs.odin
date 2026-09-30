package directwrite

import "core:mem"
import "base:runtime"
import win "core:sys/windows"

GLYPH_COUNT_MAX :: TEXT_BYTES_MAX
DOCUMENT_GLYPH_COUNT_MAX :: DOCUMENT_BYTES_MAX
GLYPH_SIDE_MAX :: 2048
NO_INTERFACE :: win.HRESULT(-2147467262)
NOT_IMPLEMENTED :: win.HRESULT(-2147467263)
NO_COLOR :: transmute(win.HRESULT)u32(0x8898500c)

Glyph :: struct {
    font:^win.IUnknown,
    index:u16,
    size,x,y:f32,
    color:[4]f32,
    colored:bool,
    measuring:u32,
}

Glyph_Buffer :: struct {
    glyphs:[dynamic]Glyph,
    fonts:[dynamic]^win.IUnknown,
    allocator:mem.Allocator,
    factory:^Factory2,
    inline_depth:u32,
    glyph_limit:int,
}

Glyph_Mask :: struct {
    pixels:[]u8,
    bounds:win.RECT,
    allocator:mem.Allocator,
}

glyph_buffer_destroy :: proc(value:^Glyph_Buffer) {
    assert(value!=nil)
    for font in value.fonts {_=font->Release()}
    delete(value.fonts)
    delete(value.glyphs)
    value^={}
}

glyph_mask_destroy :: proc(value:^Glyph_Mask) {
    assert(value!=nil)
    delete(value.pixels,value.allocator)
    value^={}
}

layout_glyphs :: proc(state:^Context,layout:^Layout)->(Glyph_Buffer,win.HRESULT) {
    assert(state!=nil && state.factory2!=nil)
    assert(layout!=nil && layout.native!=nil)
    return collect_layout_glyphs(state,layout,GLYPH_COUNT_MAX)
}

document_glyphs :: proc(state:^Context,layout:^Layout)->(Glyph_Buffer,win.HRESULT) {
    assert(state!=nil && layout!=nil && layout.document_owner==state)
    return collect_layout_glyphs(state,layout,DOCUMENT_GLYPH_COUNT_MAX)
}

@(private)
collect_layout_glyphs :: proc(state:^Context,layout:^Layout,limit:int)->(Glyph_Buffer,win.HRESULT) {
    assert(state!=nil && state.factory2!=nil)
    assert(layout!=nil && layout.native!=nil)
    assert(limit>0 && limit<=DOCUMENT_GLYPH_COUNT_MAX)
    buffer:=Glyph_Buffer{allocator=state.allocator,factory=state.factory2,glyph_limit=limit}
    buffer.glyphs=make([dynamic]Glyph,state.allocator)
    buffer.fonts=make([dynamic]^win.IUnknown,state.allocator)
    renderer:=Text_Renderer{vtable=&GLYPH_RENDERER_VTABLE,references=1}
    status:=layout.native->Draw(&buffer,&renderer,0,0)
    assert(renderer.references==1)
    if status<0 {glyph_buffer_destroy(&buffer);return {},status}
    return buffer,status
}

append_glyph_run :: proc(buffer:^Glyph_Buffer,x,y:f32,measuring:u32,run:^Glyph_Run,color:[4]f32,colored:bool)->win.HRESULT {
    if run==nil || run.font==nil || bool(run.sideways) {return NOT_IMPLEMENTED}
    assert(len(buffer.glyphs)<=buffer.glyph_limit)
    if run.count>u32(buffer.glyph_limit-len(buffer.glyphs)) {return OUT_OF_MEMORY}
    if run.count==0 {return 0}
    assert(run.indices!=nil && run.advances!=nil)
    _,font_error:=append(&buffer.fonts,run.font)
    if font_error!=nil {return OUT_OF_MEMORY}
    _=run.font->AddRef()
    pen_x:=x
    direction:f32=1
    if run.bidi_level&1!=0 {direction=-1}
    for index in 0..<int(run.count) {
        advance:=run.advances[index]
        offset:Glyph_Offset
        if run.offsets!=nil {offset=run.offsets[index]}
        pen:=pen_x
        if direction<0 {pen-=advance}
        glyph:=Glyph{run.font,run.indices[index],run.size,pen+direction*offset.advance,y-offset.ascender,color,colored,measuring}
        _,err:=append(&buffer.glyphs,glyph)
        if err!=nil {return OUT_OF_MEMORY}
        pen_x+=direction*advance
    }
    return 0
}

renderer_query :: proc "system" (self:^Text_Renderer,iid:^win.GUID,result:^rawptr)->win.HRESULT {
    if result==nil || iid==nil {return INVALID_ARGUMENT}
    result^=nil
    if iid^!=win.IUnknown_UUID^ && iid^!=TEXT_RENDERER_IID && iid^!=PIXEL_SNAPPING_IID {return NO_INTERFACE}
    result^=self
    _=self->AddRef()
    return 0
}
renderer_add_ref :: proc "system" (self:^Text_Renderer)->u32 {
    context=runtime.default_context()
    assert(self.references<max(u32))
    self.references+=1
    return self.references
}
renderer_release :: proc "system" (self:^Text_Renderer)->u32 {
    context=runtime.default_context()
    assert(self.references>1)
    self.references-=1
    return self.references
}
renderer_disable_snapping :: proc "system" (_:^Text_Renderer,_:rawptr,disabled:^win.BOOL)->win.HRESULT {
    disabled^=true
    return 0
}
renderer_transform :: proc "system" (_:^Text_Renderer,_:rawptr,transform:^Matrix)->win.HRESULT {
    transform^={m11=1,m22=1}
    return 0
}
renderer_scale :: proc "system" (_:^Text_Renderer,_:rawptr,scale:^f32)->win.HRESULT {
    scale^=1
    return 0
}
renderer_glyphs :: proc "system" (_:^Text_Renderer,data:rawptr,x,y:f32,measuring:u32,run:^Glyph_Run,description,effect:rawptr)->win.HRESULT {
    context=runtime.default_context()
    buffer:=cast(^Glyph_Buffer)data
    layers:^Color_Enumerator
    status:=buffer.factory->TranslateColorGlyphRun(x,y,run,description,measuring,nil,0,&layers)
    if status==NO_COLOR {return append_glyph_run(buffer,x,y,measuring,run,{},false)}
    if status<0 {return status}
    assert(layers!=nil)
    defer _=layers.Release(cast(^win.IUnknown)layers)
    for _ in 0..<buffer.glyph_limit {
        has_run:win.BOOL
        status=layers->MoveNext(&has_run)
        if status<0 {return status}
        if !bool(has_run) {return 0}
        layer:^Color_Glyph_Run
        status=layers->GetCurrentRun(&layer)
        if status<0 {return status}
        assert(layer!=nil)
        status=append_glyph_run(buffer,layer.x,layer.y,measuring,&layer.run,layer.color,layer.palette!=0xffff)
        if status<0 {return status}
    }
    return OUT_OF_MEMORY
}
renderer_line :: proc "system" (_:^Text_Renderer,_:rawptr,_:f32,_:f32,_:rawptr,_:rawptr)->win.HRESULT {
    return NOT_IMPLEMENTED
}
renderer_inline :: proc "system" (self:^Text_Renderer,data:rawptr,x,y:f32,object:^Inline_Object,sideways,rtl:win.BOOL,effect:rawptr)->win.HRESULT {
    context=runtime.default_context()
    if object==nil || data==nil {return INVALID_ARGUMENT}
    if bool(sideways) {return NOT_IMPLEMENTED}
    buffer:=cast(^Glyph_Buffer)data
    if buffer.inline_depth>=4 {return OUT_OF_MEMORY}
    buffer.inline_depth+=1
    defer buffer.inline_depth-=1
    return object->Draw(data,self,x,y,sideways,rtl,cast(^win.IUnknown)effect)
}

GLYPH_RENDERER_VTABLE:=Text_Renderer_VTable{
    renderer_query,renderer_add_ref,renderer_release,
    renderer_disable_snapping,renderer_transform,renderer_scale,
    renderer_glyphs,renderer_line,renderer_line,renderer_inline,
}

glyph_mask :: proc(state:^Context,glyph:Glyph,scale:f32,phase:u8)->(Glyph_Mask,win.HRESULT) {
    assert(state!=nil && state.factory2!=nil && glyph.font!=nil)
    if !(scale>0 && scale<=8) || !(glyph.size>0 && glyph.size<=1024) ||
       glyph.measuring>2 || phase>=4 {return {},INVALID_ARGUMENT}
    indices:=[1]u16{glyph.index}
    advances:=[1]f32{0}
    run:=Glyph_Run{font=glyph.font,size=glyph.size*scale,count=1,indices=raw_data(indices[:]),advances=raw_data(advances[:])}
    analysis:^Glyph_Analysis
    status:=state.factory2->CreateGlyphRunAnalysis(&run,nil,5,glyph.measuring,2,1,f32(phase)/4,0,&analysis)
    if status<0 {return {},status}
    assert(analysis!=nil)
    defer _=analysis.Release(cast(^win.IUnknown)analysis)
    mask:=Glyph_Mask{allocator=state.allocator}
    status=analysis->GetAlphaTextureBounds(0,&mask.bounds)
    if status<0 {return {},status}
    width:=i64(mask.bounds.right)-i64(mask.bounds.left)
    height:=i64(mask.bounds.bottom)-i64(mask.bounds.top)
    if width<0 || height<0 || width>GLYPH_SIDE_MAX || height>GLYPH_SIDE_MAX {return {},INVALID_ARGUMENT}
    if width==0 || height==0 {return mask,status}
    mask.pixels=make([]u8,int(width*height),state.allocator)
    if mask.pixels==nil {return {},OUT_OF_MEMORY}
    status=analysis->CreateAlphaTexture(0,&mask.bounds,raw_data(mask.pixels),u32(len(mask.pixels)))
    if status<0 {glyph_mask_destroy(&mask);return {},status}
    return mask,status
}
