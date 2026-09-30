package directwrite

import win "core:sys/windows"

foreign import dwrite "system:dwrite.lib"
foreign dwrite {
    DWriteCreateFactory :: proc "system" (kind:u32, iid:^win.GUID, result:^rawptr)->win.HRESULT ---
}

FACTORY_IID := win.GUID{0xb859ee5a,0xd838,0x4b5b,{0xa2,0xe8,0x1a,0xdc,0x7d,0x93,0xdb,0x48}}

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
    Draw: rawptr,
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
