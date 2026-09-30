package directwrite

import win "core:sys/windows"

foreign import dwrite "system:dwrite.lib"
foreign dwrite {
    DWriteCreateFactory :: proc "system" (kind:u32, iid:^win.GUID, result:^rawptr)->win.HRESULT ---
}

FACTORY2_IID := win.GUID{0x0439fc60,0xca44,0x4994,{0x8d,0xee,0x3a,0x9a,0xf7,0xb7,0x32,0xec}}
TEXT_RENDERER_IID := win.GUID{0xef8a8135,0x5cc6,0x45fe,{0x88,0x25,0xc5,0xa0,0x72,0x4e,0xb8,0x19}}
PIXEL_SNAPPING_IID := win.GUID{0xeaf3a2da,0xecf4,0x4d24,{0xb6,0x44,0xb3,0x4f,0x68,0x42,0x02,0x4b}}

Matrix :: struct {m11,m12,m21,m22,dx,dy:f32}
Glyph_Offset :: struct {advance,ascender:f32}
Glyph_Run :: struct {
    font:^win.IUnknown,
    size:f32,
    count:u32,
    indices:[^]u16,
    advances:[^]f32,
    offsets:[^]Glyph_Offset,
    sideways:win.BOOL,
    bidi_level:u32,
}
Color_Glyph_Run :: struct {
    run:Glyph_Run,
    description:rawptr,
    x,y:f32,
    color:[4]f32,
    palette:u16,
}

Factory2 :: struct {using vtable:^Factory2_VTable}
Factory2_VTable :: struct {
    original:Factory_VTable,
    GetEudcFontCollection,CreateCustomRenderingParams1:rawptr,
    GetSystemFontFallback,CreateFontFallbackBuilder:rawptr,
    TranslateColorGlyphRun:proc "system" (self:^Factory2,x,y:f32,run:^Glyph_Run,description:rawptr,measuring:u32,transform:^Matrix,palette:u32,result:^^Color_Enumerator)->win.HRESULT,
    CreateCustomRenderingParams2:rawptr,
    CreateGlyphRunAnalysis:proc "system" (self:^Factory2,run:^Glyph_Run,transform:^Matrix,rendering,measuring,grid_fit,antialias:u32,x,y:f32,result:^^Glyph_Analysis)->win.HRESULT,
}

Color_Enumerator :: struct {using vtable:^Color_Enumerator_VTable}
Color_Enumerator_VTable :: struct {
    using base:win.IUnknown_VTable,
    MoveNext:proc "system" (self:^Color_Enumerator,has_run:^win.BOOL)->win.HRESULT,
    GetCurrentRun:proc "system" (self:^Color_Enumerator,run:^^Color_Glyph_Run)->win.HRESULT,
}

Glyph_Analysis :: struct {using vtable:^Glyph_Analysis_VTable}
Glyph_Analysis_VTable :: struct {
    using base:win.IUnknown_VTable,
    GetAlphaTextureBounds:proc "system" (self:^Glyph_Analysis,kind:u32,bounds:^win.RECT)->win.HRESULT,
    CreateAlphaTexture:proc "system" (self:^Glyph_Analysis,kind:u32,bounds:^win.RECT,pixels:[^]u8,bytes:u32)->win.HRESULT,
    GetAlphaBlendParams:rawptr,
}

Text_Renderer :: struct {
    using vtable:^Text_Renderer_VTable,
    references:u32,
}
Text_Renderer_VTable :: struct {
    QueryInterface:proc "system" (self:^Text_Renderer,iid:^win.GUID,result:^rawptr)->win.HRESULT,
    AddRef:proc "system" (self:^Text_Renderer)->u32,
    Release:proc "system" (self:^Text_Renderer)->u32,
    IsPixelSnappingDisabled:proc "system" (self:^Text_Renderer,data:rawptr,disabled:^win.BOOL)->win.HRESULT,
    GetCurrentTransform:proc "system" (self:^Text_Renderer,data:rawptr,transform:^Matrix)->win.HRESULT,
    GetPixelsPerDip:proc "system" (self:^Text_Renderer,data:rawptr,scale:^f32)->win.HRESULT,
    DrawGlyphRun:proc "system" (self:^Text_Renderer,data:rawptr,x,y:f32,measuring:u32,run:^Glyph_Run,description,effect:rawptr)->win.HRESULT,
    DrawUnderline:proc "system" (self:^Text_Renderer,data:rawptr,x,y:f32,line,effect:rawptr)->win.HRESULT,
    DrawStrikethrough:proc "system" (self:^Text_Renderer,data:rawptr,x,y:f32,line,effect:rawptr)->win.HRESULT,
    DrawInlineObject:proc "system" (self:^Text_Renderer,data:rawptr,x,y:f32,object:rawptr,sideways,rtl:win.BOOL,effect:rawptr)->win.HRESULT,
}

Text_Metrics :: struct {
    left,top,width,width_with_whitespace,height,layout_width,layout_height:f32,
    bidi_depth,line_count:u32,
}
Line_Metrics :: struct {
    length,trailing_whitespace,newline_length:u32,
    height,baseline:f32,
    trimmed:win.BOOL,
}
Hit_Test_Metrics :: struct {
    position,length:u32,
    left,top,width,height:f32,
    bidi_level:u32,
    text,trimmed:win.BOOL,
}

// Vtable order follows Microsoft's SDK dwrite.h. Uncalled slots remain opaque.
// https://github.com/microsoft/win32metadata/blob/main/generation/WinSDK/RecompiledIdlHeaders/um/dwrite.h
Factory :: struct {using vtable:^Factory_VTable}
Factory_VTable :: struct {
    using base: win.IUnknown_VTable,
    GetSystemFontCollection: rawptr,
    CreateCustomFontCollection: rawptr,
    RegisterFontCollectionLoader: rawptr,
    UnregisterFontCollectionLoader: rawptr,
    CreateFontFileReference: rawptr,
    CreateCustomFontFileReference: rawptr,
    CreateFontFace: rawptr,
    CreateRenderingParams: rawptr,
    CreateMonitorRenderingParams: rawptr,
    CreateCustomRenderingParams: rawptr,
    RegisterFontFileLoader: rawptr,
    UnregisterFontFileLoader: rawptr,
    CreateTextFormat: proc "system" (self:^Factory, family:[^]u16, collection:rawptr, weight,style,stretch:u32, size:f32, locale:[^]u16, result:^^Text_Format)->win.HRESULT,
    CreateTypography: rawptr,
    GetGdiInterop: rawptr,
    CreateTextLayout: proc "system" (self:^Factory, text:[^]u16, length:u32, format:^Text_Format, width,height:f32, result:^^Text_Layout)->win.HRESULT,
    CreateGdiCompatibleTextLayout: rawptr,
    CreateEllipsisTrimmingSign: rawptr,
    CreateTextAnalyzer: rawptr,
    CreateNumberSubstitution: rawptr,
    CreateGlyphRunAnalysis: rawptr,
}

Text_Format :: struct {using vtable:^Text_Format_VTable}
Text_Format_VTable :: struct {
    using base: win.IUnknown_VTable,
    SetTextAlignment: rawptr,
    SetParagraphAlignment: rawptr,
    SetWordWrapping: proc "system" (self:^Text_Format, wrapping:u32)->win.HRESULT,
    SetReadingDirection: rawptr,
    SetFlowDirection: rawptr,
    SetIncrementalTabStop: rawptr,
    SetTrimming: rawptr,
    SetLineSpacing: rawptr,
    GetTextAlignment: rawptr,
    GetParagraphAlignment: rawptr,
    GetWordWrapping: rawptr,
    GetReadingDirection: rawptr,
    GetFlowDirection: rawptr,
    GetIncrementalTabStop: rawptr,
    GetTrimming: rawptr,
    GetLineSpacing: rawptr,
    GetFontCollection: rawptr,
    GetFontFamilyNameLength: rawptr,
    GetFontFamilyName: rawptr,
    GetFontWeight: rawptr,
    GetFontStyle: rawptr,
    GetFontStretch: rawptr,
    GetFontSize: rawptr,
    GetLocaleNameLength: rawptr,
    GetLocaleName: rawptr,
}

Text_Layout :: struct {using vtable:^Text_Layout_VTable}
Text_Layout_VTable :: struct {
    format: Text_Format_VTable,
    SetMaxWidth: rawptr,
    SetMaxHeight: rawptr,
    SetFontCollection: rawptr,
    SetFontFamilyName: rawptr,
    SetFontWeight: rawptr,
    SetFontStyle: rawptr,
    SetFontStretch: rawptr,
    SetFontSize: rawptr,
    SetUnderline: rawptr,
    SetStrikethrough: rawptr,
    SetDrawingEffect: rawptr,
    SetInlineObject: rawptr,
    SetTypography: rawptr,
    SetLocaleName: rawptr,
    GetMaxWidth: rawptr,
    GetMaxHeight: rawptr,
    GetFontCollection: rawptr,
    GetFontFamilyNameLength: rawptr,
    GetFontFamilyName: rawptr,
    GetFontWeight: rawptr,
    GetFontStyle: rawptr,
    GetFontStretch: rawptr,
    GetFontSize: rawptr,
    GetUnderline: rawptr,
    GetStrikethrough: rawptr,
    GetDrawingEffect: rawptr,
    GetInlineObject: rawptr,
    GetTypography: rawptr,
    GetLocaleNameLength: rawptr,
    GetLocaleName: rawptr,
    Draw: proc "system" (self:^Text_Layout,data:rawptr,renderer:^Text_Renderer,x,y:f32)->win.HRESULT,
    GetLineMetrics: proc "system" (self:^Text_Layout, lines:[^]Line_Metrics, capacity:u32, count:^u32)->win.HRESULT,
    GetMetrics: proc "system" (self:^Text_Layout, metrics:^Text_Metrics)->win.HRESULT,
    GetOverhangMetrics: rawptr,
    GetClusterMetrics: rawptr,
    DetermineMinWidth: rawptr,
    HitTestPoint: proc "system" (self:^Text_Layout, x,y:f32, trailing,inside:^win.BOOL, metrics:^Hit_Test_Metrics)->win.HRESULT,
    HitTestTextPosition: proc "system" (self:^Text_Layout, position:u32, trailing:win.BOOL, x,y:^f32, metrics:^Hit_Test_Metrics)->win.HRESULT,
    HitTestTextRange: rawptr,
}

#assert(size_of(Text_Metrics)==36)
#assert(size_of(Line_Metrics)==24)
#assert(size_of(Hit_Test_Metrics)==36)
#assert(offset_of(Factory_VTable,CreateTextFormat)==15*size_of(rawptr))
#assert(offset_of(Factory_VTable,CreateTextLayout)==18*size_of(rawptr))
#assert(offset_of(Text_Layout_VTable,GetMetrics)==60*size_of(rawptr))
#assert(offset_of(Text_Layout_VTable,HitTestTextPosition)==65*size_of(rawptr))
#assert(offset_of(Factory2_VTable,CreateGlyphRunAnalysis)==30*size_of(rawptr))
#assert(offset_of(Text_Renderer_VTable,DrawGlyphRun)==6*size_of(rawptr))
#assert(size_of(Glyph_Run)==48)
#assert(size_of(Matrix)==24)
#assert(size_of(Color_Glyph_Run)==88)
