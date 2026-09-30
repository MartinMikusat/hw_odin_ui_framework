package directwrite

import "core:unicode/utf16"
import "core:encoding/endian"
import win "core:sys/windows"
import ui "ui_framework:core"

FONT_BYTES_MAX :: 32*1024*1024
FACTORY5_IID := win.GUID{0x958db99a,0xbe2a,0x4f09,{0xaf,0x7d,0x65,0x18,0x98,0x03,0xd1,0xd3}}

Factory5 :: struct {using vtable:^Factory5_VTable}
Factory5_VTable :: struct {
    original:Factory2_VTable,
    CreateGlyphRunAnalysis3,CreateCustomRenderingParams3,CreateFontFaceReferencePath,CreateFontFaceReferenceFile,GetSystemFontSet,CreateFontSetBuilder3:rawptr,
    CreateFontCollectionFromFontSet:proc "system" (self:^Factory5,set:^win.IUnknown,result:^^Font_Collection)->win.HRESULT,
    GetSystemFontCollection3,GetFontDownloadQueue,TranslateColorGlyphRun4,ComputeGlyphOrigins1,ComputeGlyphOrigins2:rawptr,
    CreateFontSetBuilder:proc "system" (self:^Factory5,result:^^Font_Set_Builder)->win.HRESULT,
    CreateInMemoryFontFileLoader:proc "system" (self:^Factory5,result:^^Memory_Font_Loader)->win.HRESULT,
    CreateHttpFontFileLoader,AnalyzeContainerType:rawptr,
    UnpackFontFile:proc "system" (self:^Factory5,container:u32,data:rawptr,size:u32,result:^^Font_Stream)->win.HRESULT,
}
Memory_Font_Loader :: struct {using vtable:^Memory_Font_Loader_VTable}
Memory_Font_Loader_VTable :: struct {
    using base:win.IUnknown_VTable,
    CreateStreamFromKey:rawptr,
    CreateInMemoryFontFileReference:proc "system" (self:^Memory_Font_Loader,factory:^Factory,data:rawptr,size:u32,owner:^win.IUnknown,result:^^win.IUnknown)->win.HRESULT,
    GetFileCount:rawptr,
}
Font_Stream :: struct {using vtable:^Font_Stream_VTable}
Font_Stream_VTable :: struct {
    using base:win.IUnknown_VTable,
    ReadFileFragment:proc "system" (self:^Font_Stream,data:^rawptr,offset,size:u64,fragment:^rawptr)->win.HRESULT,
    ReleaseFileFragment:proc "system" (self:^Font_Stream,fragment:rawptr),
    GetFileSize:proc "system" (self:^Font_Stream,size:^u64)->win.HRESULT,
    GetLastWriteTime:rawptr,
}
Font_Set_Builder :: struct {using vtable:^Font_Set_Builder_VTable}
Font_Set_Builder_VTable :: struct {
    using base:win.IUnknown_VTable,
    AddFontFaceReference1,AddFontFaceReference2,AddFontSet:rawptr,
    CreateFontSet:proc "system" (self:^Font_Set_Builder,result:^^win.IUnknown)->win.HRESULT,
    AddFontFile:proc "system" (self:^Font_Set_Builder,file:^win.IUnknown)->win.HRESULT,
}
Font_Collection :: struct {using vtable:^Font_Collection_VTable}
Font_Collection_VTable :: struct {
    using base:win.IUnknown_VTable,
    GetFontFamilyCount:proc "system" (self:^Font_Collection)->u32,
    GetFontFamily:proc "system" (self:^Font_Collection,index:u32,result:^^Font_Family)->win.HRESULT,
    FindFamilyName,GetFontFromFontFace:rawptr,
}
Font_Family :: struct {using vtable:^Font_Family_VTable}
Font_Family_VTable :: struct {
    using base:win.IUnknown_VTable,
    GetFontCollection,GetFontCount,GetFont:rawptr,
    GetFamilyNames:proc "system" (self:^Font_Family,result:^^Localized_Strings)->win.HRESULT,
}
Localized_Strings :: struct {using vtable:^Localized_Strings_VTable}
Localized_Strings_VTable :: struct {
    using base:win.IUnknown_VTable,
    GetCount,FindLocaleName,GetLocaleNameLength,GetLocaleName:rawptr,
    GetStringLength:proc "system" (self:^Localized_Strings,index:u32,length:^u32)->win.HRESULT,
    GetString:proc "system" (self:^Localized_Strings,index:u32,text:[^]u16,size:u32)->win.HRESULT,
}

#assert(offset_of(Factory5_VTable,CreateFontCollectionFromFontSet)==37*size_of(rawptr))
#assert(offset_of(Factory5_VTable,CreateFontSetBuilder)==43*size_of(rawptr))
#assert(offset_of(Factory5_VTable,UnpackFontFile)==47*size_of(rawptr))
#assert(offset_of(Memory_Font_Loader_VTable,CreateInMemoryFontFileReference)==4*size_of(rawptr))
#assert(offset_of(Font_Set_Builder_VTable,AddFontFile)==7*size_of(rawptr))
#assert(offset_of(Font_Family_VTable,GetFamilyNames)==6*size_of(rawptr))
#assert(offset_of(Localized_Strings_VTable,GetString)==8*size_of(rawptr))

Embedded_Font :: struct {collection:^Font_Collection,loader:^Memory_Font_Loader}

embedded_font_destroy :: proc(value:^Context,font:^Embedded_Font) {
    if font.collection!=nil {_=font.collection.Release(cast(^win.IUnknown)font.collection)}
    if font.loader!=nil {
        status:=value.factory->UnregisterFontFileLoader(font.loader)
        assert(status>=0)
        _=font.loader.Release(cast(^win.IUnknown)font.loader)
    }
    font^={}
}

register_embedded_font :: proc(value:^Context,handle:ui.Font_Handle,bytes:[]u8)->win.HRESULT {
    assert(value!=nil && value.factory!=nil)
    if handle==ui.Font_Handle(0) || len(bytes)<48 || len(bytes)>FONT_BYTES_MAX || value.embedded_font.loader!=nil {return INVALID_ARGUMENT}
    if string(bytes[:4])!="wOF2" {return INVALID_ARGUMENT}
    declared_size:=endian.unchecked_get_u32be(bytes[16:20])
    if endian.unchecked_get_u32be(bytes[8:12])!=u32(len(bytes)) ||
       declared_size==0 || declared_size>FONT_BYTES_MAX ||
       endian.unchecked_get_u32be(bytes[20:24])>u32(len(bytes)-48) {return INVALID_ARGUMENT}
    factory:^Factory5
    status:=(cast(^win.IUnknown)value.factory)->QueryInterface(&FACTORY5_IID,cast(^rawptr)&factory)
    if status<0 {return status}
    factory_unknown:=cast(^win.IUnknown)factory
    defer _=factory_unknown->Release()
    stream:^Font_Stream
    status=factory->UnpackFontFile(2,raw_data(bytes),u32(len(bytes)),&stream)
    if status<0 {return status}
    defer _=stream.Release(cast(^win.IUnknown)stream)
    size:u64
    status=stream->GetFileSize(&size)
    if status<0 {return status}
    if size==0 || size>FONT_BYTES_MAX {return INVALID_ARGUMENT}
    data,fragment:rawptr
    status=stream->ReadFileFragment(&data,0,size,&fragment)
    if status<0 {return status}
    defer stream->ReleaseFileFragment(fragment)
    font:Embedded_Font
    status=factory->CreateInMemoryFontFileLoader(&font.loader)
    if status<0 {return status}
    status=value.factory->RegisterFontFileLoader(font.loader)
    if status<0 {_=font.loader.Release(cast(^win.IUnknown)font.loader);return status}
    committed:=false
    defer if !committed {embedded_font_destroy(value,&font)}
    file:^win.IUnknown
    // A nil owner asks DirectWrite to copy the unpacked bytes before the fragment is released.
    status=font.loader->CreateInMemoryFontFileReference(value.factory,data,u32(size),nil,&file)
    if status<0 {return status}
    defer _=file->Release()
    builder:^Font_Set_Builder
    status=factory->CreateFontSetBuilder(&builder)
    if status<0 {return status}
    defer _=builder.Release(cast(^win.IUnknown)builder)
    status=builder->AddFontFile(file)
    if status<0 {return status}
    set:^win.IUnknown
    status=builder->CreateFontSet(&set)
    if status<0 {return status}
    defer _=set->Release()
    status=factory->CreateFontCollectionFromFontSet(set,&font.collection)
    if status<0 {return status}
    if font.collection->GetFontFamilyCount()!=1 {return INVALID_ARGUMENT}
    family:^Font_Family
    status=font.collection->GetFontFamily(0,&family)
    if status<0 {return status}
    defer _=family.Release(cast(^win.IUnknown)family)
    names:^Localized_Strings
    status=family->GetFamilyNames(&names)
    if status<0 {return status}
    defer _=names.Release(cast(^win.IUnknown)names)
    length:u32
    status=names->GetStringLength(0,&length)
    if status<0 {return status}
    if length==0 || length>256 {return INVALID_ARGUMENT}
    wide:[257]u16
    status=names->GetString(0,raw_data(wide[:]),length+1)
    if status<0 {return status}
    name:[1024]u8
    name_length:=utf16.decode_to_utf8(name[:],wide[:length])
    status=register_font(value,handle,string(name[:name_length]))
    if status<0 {return status}
    for &entry in value.fonts {if entry.handle==handle {entry.collection=font.collection;break}}
    value.embedded_font=font
    committed=true
    return 0
}
