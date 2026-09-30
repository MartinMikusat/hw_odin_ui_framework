package d3d11

import draw "ui_framework:draw"
import atlas "ui_framework:glyphatlas"
import dx "vendor:directx/d3d11"
import win "core:sys/windows"

TEXTURES_MAX :: 4096
TEXTURE_SIDE_MAX :: 16384
TEXTURE_BYTES_MAX :: 256*1024*1024
OUT_OF_MEMORY :: win.HRESULT(-2147024882)

Texture :: struct {
    native:^dx.ITexture2D,
    view:^dx.IShaderResourceView,
    width,height:int,
    format:atlas.Format,
    generation:u32,
}

// Handles are scoped to this renderer. Destroying a texture invalidates its
// handle even when the registry slot is reused. Returned pointers are borrowed
// until the next texture creation or renderer destruction.
texture_get :: proc(renderer:^Renderer,handle:draw.Texture_Handle)->^Texture {
    index:=int(u32(u64(handle)))-1
    generation:=u32(u64(handle)>>32)
    if renderer==nil || index<0 || index>=len(renderer.textures) {return nil}
    texture:=&renderer.textures[index]
    if texture.native==nil || texture.generation!=generation {return nil}
    return texture
}

texture_create :: proc(renderer:^Renderer,format:atlas.Format,width,height:int)->(draw.Texture_Handle,win.HRESULT) {
    assert(renderer!=nil && renderer.device!=nil)
    if width<=0 || height<=0 || width>TEXTURE_SIDE_MAX || height>TEXTURE_SIDE_MAX || (format!=.Alpha && format!=.Color) {return 0,INVALID_ARGUMENT}
    bpp:=1
    if format==.Color {bpp=4}
    bytes:=width*height*bpp
    if bytes>TEXTURE_BYTES_MAX-renderer.texture_bytes {return 0,OUT_OF_MEMORY}
    index:=-1
    // ponytail: scan at most 4096 slots; use a free list if texture churn becomes hot.
    for &slot,offset in renderer.textures {
        if slot.native==nil && slot.generation<0xffffffff {index=offset;break}
    }
    if index<0 && len(renderer.textures)>=TEXTURES_MAX {return 0,OUT_OF_MEMORY}
    descriptor:=dx.TEXTURE2D_DESC{Width=u32(width),Height=u32(height),MipLevels=1,ArraySize=1,Format=.R8_UNORM,SampleDesc={Count=1},Usage=.DEFAULT,BindFlags={.SHADER_RESOURCE}}
    if format==.Color {descriptor.Format=.R8G8B8A8_UNORM}
    texture:=Texture{width=width,height=height,format=format}
    result:=renderer.device->CreateTexture2D(&descriptor,nil,&texture.native)
    if result<0 {release(texture.native);return 0,result}
    result=renderer.device->CreateShaderResourceView(texture.native,nil,&texture.view)
    if result<0 {release(texture.view);release(texture.native);return 0,result}
    if index<0 {
        _,error:=append(&renderer.textures,Texture{})
        if error!=nil {release(texture.view);release(texture.native);return 0,OUT_OF_MEMORY}
        index=len(renderer.textures)-1
    }
    texture.generation=renderer.textures[index].generation+1
    renderer.textures[index]=texture
    renderer.texture_bytes+=bytes
    return draw.Texture_Handle(u64(texture.generation)<<32|u64(index+1)),0
}

texture_destroy :: proc(renderer:^Renderer,handle:draw.Texture_Handle)->bool {
    texture:=texture_get(renderer,handle)
    if texture==nil {return false}
    bpp:=1
    if texture.format==.Color {bpp=4}
    renderer.texture_bytes-=texture.width*texture.height*bpp
    release(texture.view)
    release(texture.native)
    generation:=texture.generation
    texture^=Texture{generation=generation}
    assert(renderer.texture_bytes>=0)
    return true
}

texture_upload :: proc(renderer:^Renderer,handle:draw.Texture_Handle,x,y,width,height:int,pixels:[]u8,stride:int)->win.HRESULT {
    texture:=texture_get(renderer,handle)
    if texture==nil || x<0 || y<0 || width<=0 || height<=0 || width>texture.width || height>texture.height || x>texture.width-width || y>texture.height-height {return INVALID_ARGUMENT}
    bpp:=1
    if texture.format==.Color {bpp=4}
    if stride<width*bpp || stride>TEXTURE_SIDE_MAX*4 || len(pixels)<(height-1)*stride+width*bpp {return INVALID_ARGUMENT}
    box:=dx.BOX{left=u32(x),top=u32(y),front=0,right=u32(x+width),bottom=u32(y+height),back=1}
    renderer.immediate->UpdateSubresource(texture.native,0,&box,raw_data(pixels),u32(stride),0)
    return renderer.device->GetDeviceRemovedReason()
}

// Atlas errors remain fatal until the text context and renderer are recreated:
// the shared upload callback cannot return an error or retain failed dirty areas.
begin_frame :: proc(renderer:^Renderer)->win.HRESULT {
    assert(renderer!=nil && renderer.device!=nil)
    if renderer.atlas_error>=0 {renderer.atlas_error=renderer.device->GetDeviceRemovedReason()}
    return renderer.atlas_error
}

atlas_io :: proc(renderer:^Renderer)->atlas.IO {
    return {user_data=renderer,create=atlas_create,upload=atlas_upload,destroy=atlas_destroy,bind=atlas_bind}
}

atlas_create :: proc(raw:rawptr,format:atlas.Format,width,height:int)->u64 {
    renderer:=cast(^Renderer)raw
    handle,result:=texture_create(renderer,format,width,height)
    if result<0 && renderer.atlas_error>=0 {renderer.atlas_error=result}
    return u64(handle)
}

atlas_upload :: proc(raw:rawptr,native:u64,format:atlas.Format,x,y,width,height:int,pixels:[^]u8,stride:int) {
    renderer:=cast(^Renderer)raw
    texture:=texture_get(renderer,draw.Texture_Handle(native))
    if texture==nil || texture.format!=format || pixels==nil || height<=0 || height>TEXTURE_SIDE_MAX || width<=0 || width>TEXTURE_SIDE_MAX || stride<=0 || stride>TEXTURE_SIDE_MAX*4 {
        if renderer.atlas_error>=0 {renderer.atlas_error=INVALID_ARGUMENT}
        return
    }
    bpp:=1
    if format==.Color {bpp=4}
    result:=texture_upload(renderer,draw.Texture_Handle(native),x,y,width,height,pixels[:(height-1)*stride+width*bpp],stride)
    if result<0 && renderer.atlas_error>=0 {renderer.atlas_error=result}
}

atlas_destroy :: proc(raw:rawptr,native:u64) {
    destroyed:=texture_destroy(cast(^Renderer)raw,draw.Texture_Handle(native))
    assert(destroyed)
}

atlas_bind :: proc(raw:rawptr,native:u64)->draw.Texture_Handle {
    renderer:=cast(^Renderer)raw
    handle:=draw.Texture_Handle(native)
    if texture_get(renderer,handle)==nil {
        if renderer.atlas_error>=0 {renderer.atlas_error=INVALID_ARGUMENT}
        return 0
    }
    return handle
}
