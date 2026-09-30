package d3d11

import win "core:sys/windows"
import dx "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"

HOST_CONTROL_ENABLED :: !#config(UI_FRAMEWORK_TEST_MODE,false)
HOST_CONTROL_DISABLED :: win.HRESULT(-2147467263)
SURFACE_BYTES_MAX :: 256*1024*1024
SURFACE_FLAGS :: dxgi.SWAP_CHAIN{.FRAME_LATENCY_WAITABLE_OBJECT}

Window_Surface :: struct {
    chain:^dxgi.ISwapChain2,
    factory:^dxgi.IFactory2,
    occlusion_cookie:u32,
    waitable:win.HANDLE,
    color:^dx.IRenderTargetView,
    depth:^dx.ITexture2D,
    stencil:^dx.IDepthStencilView,
    width,height:u32,
    suspended:bool,
}

surface_size_valid :: proc(width,height:int)->bool {
    return width>=0 && height>=0 && width<=TEXTURE_SIDE_MAX && height<=TEXTURE_SIDE_MAX && u64(width)*u64(height)*12<=SURFACE_BYTES_MAX
}

// The HWND is borrowed and must outlive the surface. The host uses a private
// WM_APP message for occlusion changes and waits on waitable before every frame,
// including the first. Destroy the surface before its window and renderer.
window_surface_init :: proc(surface:^Window_Surface,renderer:^Renderer,window:win.HWND,width,height:int,occlusion_message:u32)->win.HRESULT {
    if !HOST_CONTROL_ENABLED {return HOST_CONTROL_DISABLED}
    assert(surface!=nil && surface^==Window_Surface{})
    assert(renderer!=nil && renderer.device!=nil)
    if window==nil || !surface_size_valid(width,height) || width==0 || height==0 || occlusion_message<0x8000 || occlusion_message>=0xc000 {return INVALID_ARGUMENT}
    pending:Window_Surface
    complete:=false
    defer if !complete {window_surface_destroy(&pending,renderer)}
    device:^dxgi.IDevice
    result:=renderer.device->QueryInterface(dxgi.IDevice_UUID,cast(^rawptr)&device)
    if result<0 {return result}
    defer release(device)
    adapter:^dxgi.IAdapter
    result=device->GetAdapter(&adapter)
    if result<0 {return result}
    defer release(adapter)
    factory:^dxgi.IFactory2
    result=adapter->GetParent(dxgi.IFactory2_UUID,cast(^rawptr)&factory)
    if result<0 {return result}
    defer release(factory)
    descriptor:=dxgi.SWAP_CHAIN_DESC1{Width=u32(width),Height=u32(height),Format=.B8G8R8A8_UNORM,SampleDesc={Count=1},BufferUsage={.RENDER_TARGET_OUTPUT},BufferCount=2,Scaling=.STRETCH,SwapEffect=.FLIP_SEQUENTIAL,AlphaMode=.IGNORE,Flags=SURFACE_FLAGS}
    chain:^dxgi.ISwapChain1
    result=factory->CreateSwapChainForHwnd(cast(^dxgi.IUnknown)renderer.device,window,&descriptor,nil,nil,&chain)
    if result<0 {return result}
    defer release(chain)
    result=chain->QueryInterface(dxgi.ISwapChain2_UUID,cast(^rawptr)&pending.chain)
    if result<0 {return result}
    result=pending.chain->SetMaximumFrameLatency(1)
    if result<0 {return result}
    pending.waitable=pending.chain->GetFrameLatencyWaitableObject()
    if pending.waitable==nil {return INVALID_ARGUMENT}
    result=factory->MakeWindowAssociation(window,{.NO_ALT_ENTER})
    if result<0 {return result}
    result=factory->RegisterOcclusionStatusWindow(window,occlusion_message,&pending.occlusion_cookie)
    if result<0 {return result}
    _=factory->AddRef()
    pending.factory=factory
    result=window_surface_targets(&pending,renderer,u32(width),u32(height))
    if result<0 {return result}
    surface^=pending
    complete=true
    return 0
}

window_surface_resize :: proc(surface:^Window_Surface,renderer:^Renderer,width,height:int)->win.HRESULT {
    if !HOST_CONTROL_ENABLED {return HOST_CONTROL_DISABLED}
    assert(surface!=nil && surface.chain!=nil && renderer!=nil && renderer.immediate!=nil)
    if !surface_size_valid(width,height) {return INVALID_ARGUMENT}
    if width==0 || height==0 {surface.suspended=true;return 0}
    if surface.width==u32(width) && surface.height==u32(height) && surface.color!=nil {surface.suspended=false;return 0}
    renderer.immediate->ClearState()
    window_surface_release_targets(surface)
    result:=surface.chain->ResizeBuffers(2,u32(width),u32(height),.B8G8R8A8_UNORM,SURFACE_FLAGS)
    if result<0 {return result}
    return window_surface_targets(surface,renderer,u32(width),u32(height))
}

window_surface_targets :: proc(surface:^Window_Surface,renderer:^Renderer,width,height:u32)->win.HRESULT {
    assert(surface.color==nil && surface.depth==nil && surface.stencil==nil)
    complete:=false
    defer if !complete {window_surface_release_targets(surface)}
    color:^dx.ITexture2D
    result:=surface.chain->GetBuffer(0,dx.ITexture2D_UUID,cast(^rawptr)&color)
    if result<0 {return result}
    defer release(color)
    result=renderer.device->CreateRenderTargetView(color,nil,&surface.color)
    if result<0 {return result}
    descriptor:=dx.TEXTURE2D_DESC{Width=width,Height=height,MipLevels=1,ArraySize=1,Format=.D24_UNORM_S8_UINT,SampleDesc={Count=1},Usage=.DEFAULT,BindFlags={.DEPTH_STENCIL}}
    result=renderer.device->CreateTexture2D(&descriptor,nil,&surface.depth)
    if result<0 {return result}
    result=renderer.device->CreateDepthStencilView(surface.depth,nil,&surface.stencil)
    if result<0 {return result}
    surface.width=width
    surface.height=height
    surface.suspended=false
    complete=true
    return 0
}

window_surface_present :: proc(surface:^Window_Surface)->win.HRESULT {
    if !HOST_CONTROL_ENABLED {return HOST_CONTROL_DISABLED}
    assert(surface!=nil && surface.chain!=nil)
    if surface.suspended || surface.color==nil {return INVALID_ARGUMENT}
    return surface.chain->Present(1,{})
}

window_surface_release_targets :: proc(surface:^Window_Surface) {
    release(surface.stencil)
    release(surface.depth)
    release(surface.color)
    surface.stencil=nil
    surface.depth=nil
    surface.color=nil
    surface.width=0
    surface.height=0
}

window_surface_destroy :: proc(surface:^Window_Surface,renderer:^Renderer) {
    if !HOST_CONTROL_ENABLED {return}
    if surface==nil {return}
    if surface.chain!=nil {
        assert(renderer!=nil && renderer.immediate!=nil)
        renderer.immediate->ClearState()
        renderer.immediate->Flush()
    }
    if surface.factory!=nil {surface.factory->UnregisterOcclusionStatus(surface.occlusion_cookie)}
    window_surface_release_targets(surface)
    if surface.waitable!=nil {
        closed:=win.CloseHandle(surface.waitable)
        assert(bool(closed))
    }
    release(surface.chain)
    release(surface.factory)
    surface^={}
}
