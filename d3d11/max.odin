package d3d11

import draw "ui_framework:draw"
import data "ui_framework:renderdata"
import dx "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import win "core:sys/windows"

Max_Target :: struct {
    native:^dx.ITexture2D,
    target:^dx.IRenderTargetView,
    view:^dx.IShaderResourceView,
    width,height:u32,
    format:dxgi.FORMAT,
}

max_target_ensure :: proc(renderer:^Renderer,target:^dx.IRenderTargetView,width,height:u32)->win.HRESULT {
    assert(width>0 && height>0 && width<=TEXTURE_SIDE_MAX && height<=TEXTURE_SIDE_MAX)
    descriptor:dx.RENDER_TARGET_VIEW_DESC
    target->GetDesc(&descriptor)
    if descriptor.ViewDimension!=.TEXTURE2D || descriptor.Texture2D.MipSlice!=0 {return INVALID_ARGUMENT}
    #partial switch descriptor.Format {
    case .R8G8B8A8_UNORM,.B8G8R8A8_UNORM,.R8G8B8A8_UNORM_SRGB,.B8G8R8A8_UNORM_SRGB:
    case: return INVALID_ARGUMENT
    }
    if u64(width)*u64(height)*4>TEXTURE_BYTES_MAX {return OUT_OF_MEMORY}
    current:=&renderer.max_target
    if current.native!=nil && current.width==width && current.height==height && current.format==descriptor.Format {return 0}
    max_target_destroy(current)
    pending:=Max_Target{width=width,height=height,format=descriptor.Format}
    complete:=false
    defer if !complete {max_target_destroy(&pending)}
    texture:=dx.TEXTURE2D_DESC{Width=width,Height=height,MipLevels=1,ArraySize=1,Format=descriptor.Format,SampleDesc={Count=1},Usage=.DEFAULT,BindFlags={.RENDER_TARGET,.SHADER_RESOURCE}}
    result:=renderer.device->CreateTexture2D(&texture,nil,&pending.native)
    if result<0 {return result}
    result=renderer.device->CreateRenderTargetView(pending.native,nil,&pending.target)
    if result<0 {return result}
    result=renderer.device->CreateShaderResourceView(pending.native,nil,&pending.view)
    if result<0 {return result}
    current^=pending
    complete=true
    return 0
}

max_target_destroy :: proc(target:^Max_Target) {
    release(target.view)
    release(target.target)
    release(target.native)
    target^={}
}

max_target_bind :: proc(renderer:^Renderer) {
    views:=[1]^dx.IShaderResourceView{nil}
    renderer.immediate->PSSetShaderResources(0,1,raw_data(views[:]))
    targets:=[1]^dx.IRenderTargetView{renderer.max_target.target}
    renderer.immediate->OMSetRenderTargets(1,raw_data(targets[:]),nil)
    clear:=[4]f32{0,0,0,0}
    renderer.immediate->ClearRenderTargetView(renderer.max_target.target,&clear)
}

max_target_composite :: proc(renderer:^Renderer,viewport:[2]f32,scale:f32) {
    instance:=data.Quad_Instance{dst={0,0,viewport[0],viewport[1]},src={0,1,1,-1},colors={{1,1,1,1},{1,1,1,1},{1,1,1,1},{1,1,1,1}},edge_softness=0.5,texture_mode=u32(draw.Texture_Mode.Color)}
    renderer.immediate->UpdateSubresource(renderer.composite_quad,0,nil,&instance,0,0)
    key:=draw.Batch_Key{opacity=1,transform=draw.IDENTITY_TRANSFORM,sampler=.Nearest}
    if !encode_scissor(renderer,key,viewport,scale) {return}
    encode_quad_bind(renderer,key,renderer.composite_quad,0,1,renderer.max_target.view,viewport,renderer.over_blend)
    views:=[1]^dx.IShaderResourceView{nil}
    renderer.immediate->PSSetShaderResources(0,1,raw_data(views[:]))
}
