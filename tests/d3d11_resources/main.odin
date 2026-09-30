package main

import "core:fmt"
import "core:mem"
import "core:os"
import renderer "ui_framework:d3d11"
import dx "vendor:directx/d3d11"

main :: proc() {
    tracking:mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking,context.allocator)
    defer mem.tracking_allocator_destroy(&tracking)
    context.allocator=mem.tracking_allocator(&tracking)
    verify_resources()
    assert(len(tracking.allocation_map)==0 && len(tracking.bad_free_array)==0)
    fmt.println("Direct3D 11 shader signatures, pipeline states, failure cleanup and retry passed.")
}

verify_resources :: proc() {
    quad_vertex,ev:=os.read_entire_file("build/test/shaders/ui_vertex.cso",context.allocator)
    assert(ev==nil)
    defer delete(quad_vertex)
    quad_fragment,ef:=os.read_entire_file("build/test/shaders/ui_fragment.cso",context.allocator)
    assert(ef==nil)
    defer delete(quad_fragment)
    path_vertex,pv:=os.read_entire_file("build/test/shaders/path_vertex.cso",context.allocator)
    assert(pv==nil)
    defer delete(path_vertex)
    path_fragment,pf:=os.read_entire_file("build/test/shaders/path_fragment.cso",context.allocator)
    assert(pf==nil)
    defer delete(path_fragment)
    shaders:=renderer.Shader_Bytes{quad_vertex,quad_fragment,path_vertex,path_fragment}
    state:renderer.Renderer
    assert(renderer.renderer_init(&state,{})==renderer.INVALID_ARGUMENT)
    assert(state.device==nil && state.immediate==nil)
    wrong_stage:=shaders
    wrong_stage.quad_fragment=quad_vertex
    assert(renderer.renderer_init(&state,wrong_stage,software=true)<0)
    assert(state.device==nil && state.quad_vertex==nil)
    for _ in 0..<2 {
        assert(renderer.renderer_init(&state,shaders,software=true)>=0)
        assert(state.device->GetFeatureLevel()==._11_0)
        assert(state.quad_layout!=nil && state.path_layout!=nil)
        blend:dx.BLEND_DESC
        state.over_blend->GetDesc(&blend)
        assert(blend.RenderTarget[0].SrcBlend==.ONE && blend.RenderTarget[0].DestBlend==.INV_SRC_ALPHA)
        assert(blend.RenderTarget[0].BlendOp==.ADD && blend.RenderTarget[0].RenderTargetWriteMask==15)
        state.max_blend->GetDesc(&blend)
        assert(blend.RenderTarget[0].BlendOp==.MAX && blend.RenderTarget[0].BlendOpAlpha==.MAX)
        state.stencil_blend->GetDesc(&blend)
        assert(blend.RenderTarget[0].RenderTargetWriteMask==0)
        raster:dx.RASTERIZER_DESC
        state.rasterizer->GetDesc(&raster)
        assert(raster.CullMode==.NONE && bool(raster.FrontCounterClockwise) && bool(raster.ScissorEnable))
        sampler:dx.SAMPLER_DESC
        state.linear_sampler->GetDesc(&sampler)
        assert(sampler.Filter==.MIN_MAG_MIP_LINEAR && sampler.AddressU==.CLAMP)
        state.nearest_sampler->GetDesc(&sampler)
        assert(sampler.Filter==.MIN_MAG_MIP_POINT)
        device:=state.device
        _=device->AddRef()
        renderer.renderer_destroy(&state)
        assert(state.device==nil && state.immediate==nil && state.quad_layout==nil)
        assert(device->GetFeatureLevel()==._11_0)
        _=device->Release()
        renderer.renderer_destroy(&state)
    }
}
