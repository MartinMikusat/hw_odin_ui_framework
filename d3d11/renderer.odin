package d3d11

import win "core:sys/windows"
import dx "vendor:directx/d3d11"
import data "ui_framework:renderdata"

BYTECODE_BYTES_MAX :: 1024*1024
INVALID_ARGUMENT :: win.HRESULT(-2147024809)

Shader_Bytes :: struct {quad_vertex,quad_fragment,path_vertex,path_fragment:[]u8}

Renderer :: struct {
    device:^dx.IDevice,
    immediate:^dx.IDeviceContext,
    quad_vertex:^dx.IVertexShader,
    quad_fragment:^dx.IPixelShader,
    path_vertex:^dx.IVertexShader,
    path_fragment:^dx.IPixelShader,
    quad_layout,path_layout:^dx.IInputLayout,
    over_blend,max_blend,stencil_blend:^dx.IBlendState,
    rasterizer:^dx.IRasterizerState,
    linear_sampler,nearest_sampler:^dx.ISamplerState,
    quads,paths:Upload_Buffer,
}

QUAD_INPUT :: [10]dx.INPUT_ELEMENT_DESC{
    {"POSITION",0,.R32G32B32A32_FLOAT,0,0,.INSTANCE_DATA,1},
    {"TEXCOORD",0,.R32G32B32A32_FLOAT,0,16,.INSTANCE_DATA,1},
    {"COLOR",0,.R32G32B32A32_FLOAT,0,32,.INSTANCE_DATA,1},
    {"COLOR",1,.R32G32B32A32_FLOAT,0,48,.INSTANCE_DATA,1},
    {"COLOR",2,.R32G32B32A32_FLOAT,0,64,.INSTANCE_DATA,1},
    {"COLOR",3,.R32G32B32A32_FLOAT,0,80,.INSTANCE_DATA,1},
    {"TEXCOORD",1,.R32G32B32A32_FLOAT,0,96,.INSTANCE_DATA,1},
    {"TEXCOORD",2,.R32G32_FLOAT,0,112,.INSTANCE_DATA,1},
    {"TEXCOORD",3,.R32G32_FLOAT,0,120,.INSTANCE_DATA,1},
    {"TEXCOORD",4,.R32G32_UINT,0,128,.INSTANCE_DATA,1},
}
PATH_INPUT :: [2]dx.INPUT_ELEMENT_DESC{
    {"POSITION",0,.R32G32_FLOAT,0,0,.VERTEX_DATA,0},
    {"TEXCOORD",0,.R32G32_FLOAT,0,8,.VERTEX_DATA,0},
}

// The renderer owns its device and immediate context; all calls use the host's
// rendering thread. Shader slices are borrowed only during initialization.
renderer_init :: proc(renderer:^Renderer,shaders:Shader_Bytes,software:=false,debug:=false)->win.HRESULT {
    assert(renderer!=nil)
    assert(renderer^==Renderer{})
    bytecodes:=[4][]u8{shaders.quad_vertex,shaders.quad_fragment,shaders.path_vertex,shaders.path_fragment}
    for bytes in bytecodes {
        if len(bytes)<32 || len(bytes)>BYTECODE_BYTES_MAX || string(bytes[:4])!="DXBC" {return INVALID_ARGUMENT}
    }
    pending:Renderer
    complete:=false
    defer if !complete {renderer_destroy(&pending)}
    levels:=[1]dx.FEATURE_LEVEL{._11_0}
    selected:dx.FEATURE_LEVEL
    driver:dx.DRIVER_TYPE=.HARDWARE
    if software {driver=.WARP}
    flags:=dx.CREATE_DEVICE_FLAGS{.SINGLETHREADED,.BGRA_SUPPORT}
    if debug {flags+=dx.CREATE_DEVICE_FLAGS{.DEBUG}}
    result:=dx.CreateDevice(nil,driver,nil,flags,raw_data(levels[:]),1,dx.SDK_VERSION,&pending.device,&selected,&pending.immediate)
    if result<0 {return result}
    assert(selected==._11_0 && pending.device!=nil && pending.immediate!=nil)
    result=renderer_init_shaders(&pending,shaders)
    if result<0 {return result}
    result=renderer_init_states(&pending)
    if result<0 {return result}
    renderer^=pending
    complete=true
    return 0
}

renderer_init_shaders :: proc(renderer:^Renderer,shaders:Shader_Bytes)->win.HRESULT {
    device:=renderer.device
    result:=device->CreateVertexShader(raw_data(shaders.quad_vertex),uint(len(shaders.quad_vertex)),nil,&renderer.quad_vertex)
    if result<0 {return result}
    result=device->CreatePixelShader(raw_data(shaders.quad_fragment),uint(len(shaders.quad_fragment)),nil,&renderer.quad_fragment)
    if result<0 {return result}
    result=device->CreateVertexShader(raw_data(shaders.path_vertex),uint(len(shaders.path_vertex)),nil,&renderer.path_vertex)
    if result<0 {return result}
    result=device->CreatePixelShader(raw_data(shaders.path_fragment),uint(len(shaders.path_fragment)),nil,&renderer.path_fragment)
    if result<0 {return result}
    quad_input:=QUAD_INPUT
    path_input:=PATH_INPUT
    result=device->CreateInputLayout(raw_data(quad_input[:]),len(QUAD_INPUT),raw_data(shaders.quad_vertex),uint(len(shaders.quad_vertex)),&renderer.quad_layout)
    if result<0 {return result}
    return device->CreateInputLayout(raw_data(path_input[:]),len(PATH_INPUT),raw_data(shaders.path_vertex),uint(len(shaders.path_vertex)),&renderer.path_layout)
}

renderer_init_states :: proc(renderer:^Renderer)->win.HRESULT {
    blend:=dx.BLEND_DESC{}
    blend.RenderTarget[0]={
        BlendEnable=true,SrcBlend=.ONE,DestBlend=.INV_SRC_ALPHA,BlendOp=.ADD,
        SrcBlendAlpha=.ONE,DestBlendAlpha=.INV_SRC_ALPHA,BlendOpAlpha=.ADD,
        RenderTargetWriteMask=u8(dx.COLOR_WRITE_ENABLE_ALL),
    }
    result:=renderer.device->CreateBlendState(&blend,&renderer.over_blend)
    if result<0 {return result}
    blend.RenderTarget[0].DestBlend=.ONE
    blend.RenderTarget[0].DestBlendAlpha=.ONE
    blend.RenderTarget[0].BlendOp=.MAX
    blend.RenderTarget[0].BlendOpAlpha=.MAX
    result=renderer.device->CreateBlendState(&blend,&renderer.max_blend)
    if result<0 {return result}
    blend.RenderTarget[0].BlendEnable=false
    blend.RenderTarget[0].RenderTargetWriteMask=0
    result=renderer.device->CreateBlendState(&blend,&renderer.stencil_blend)
    if result<0 {return result}
    raster:=dx.RASTERIZER_DESC{FillMode=.SOLID,CullMode=.NONE,FrontCounterClockwise=true,DepthClipEnable=true,ScissorEnable=true}
    result=renderer.device->CreateRasterizerState(&raster,&renderer.rasterizer)
    if result<0 {return result}
    sampler:=dx.SAMPLER_DESC{Filter=.MIN_MAG_MIP_LINEAR,AddressU=.CLAMP,AddressV=.CLAMP,AddressW=.CLAMP,MaxAnisotropy=1,ComparisonFunc=.NEVER,MinLOD=0,MaxLOD=0}
    result=renderer.device->CreateSamplerState(&sampler,&renderer.linear_sampler)
    if result<0 {return result}
    sampler.Filter=.MIN_MAG_MIP_POINT
    return renderer.device->CreateSamplerState(&sampler,&renderer.nearest_sampler)
}

renderer_destroy :: proc(renderer:^Renderer) {
    if renderer==nil {return}
    if renderer.immediate!=nil {renderer.immediate->ClearState();renderer.immediate->Flush()}
    release(renderer.quads.native)
    release(renderer.paths.native)
    release(renderer.quad_layout)
    release(renderer.path_layout)
    release(renderer.quad_vertex)
    release(renderer.quad_fragment)
    release(renderer.path_vertex)
    release(renderer.path_fragment)
    release(renderer.over_blend)
    release(renderer.max_blend)
    release(renderer.stencil_blend)
    release(renderer.rasterizer)
    release(renderer.linear_sampler)
    release(renderer.nearest_sampler)
    release(renderer.immediate)
    release(renderer.device)
    renderer^={}
}

#assert(offset_of(data.Quad_Instance,colors)==32)
#assert(offset_of(data.Quad_Instance,effect_offset)==112)
#assert(offset_of(data.Quad_Instance,border_thickness)==120)
#assert(offset_of(data.Quad_Instance,texture_mode)==128)
#assert(offset_of(data.Path_Vertex,coverage)==8)

release :: proc(value:rawptr) {
    if value!=nil {_=(cast(^win.IUnknown)value)->Release()}
}
