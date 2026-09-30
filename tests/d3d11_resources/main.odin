package main

import "core:fmt"
import "core:mem"
import "core:os"
import renderer "ui_framework:d3d11"
import dx "vendor:directx/d3d11"
import draw "ui_framework:draw"
import data "ui_framework:renderdata"

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
        verify_upload(&state)
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

verify_upload :: proc(state:^renderer.Renderer) {
    list:draw.List
    draw.list_init(&list)
    defer draw.list_destroy(&list)
    draw.solid(&list,{2,3,20,10},{0.2,0.4,0.6,0.8})
    draw.path_begin(&list)
    draw.path_circle(&list,30,30,10)
    draw.path_fill(&list,{1,0,0,1})
    assert(renderer.upload_list(state,&list,nil,nil)==renderer.INVALID_ARGUMENT)
    for round in 0..<2 {
        ranges:=make([]data.Batch_Range,len(list.batches))
        defer delete(ranges)
        path_ranges:=make([]data.Path_Batch_Range,len(list.batches))
        defer delete(path_ranges)
        assert(renderer.upload_list(state,&list,ranges,path_ranges)>=0)
        expected_capacity:=u32(renderer.UPLOAD_BYTES_MIN)
        if round==1 {expected_capacity=256*1024}
        assert(state.quads.capacity==expected_capacity && state.paths.capacity==renderer.UPLOAD_BYTES_MIN)
        for &batch,index in list.batches {
            if batch.kind==.Quad {
                expected:=data.quad_instance(batch.instances[0])
                bytes:=readback(state,state.quads.native,int(ranges[index].start+ranges[index].count)*size_of(data.Quad_Instance))
                defer delete(bytes)
                values:=(cast([^]data.Quad_Instance)raw_data(bytes))[:len(bytes)/size_of(data.Quad_Instance)]
                assert(ranges[index].count==uint(len(batch.instances)))
                assert(values[ranges[index].start]==expected)
                batch.instances[0].dst.x+=7
            } else {
                bytes:=readback(state,state.paths.native,data.path_vertex_count(&list)*size_of(data.Path_Vertex))
                defer delete(bytes)
                values:=(cast([^]data.Path_Vertex)raw_data(bytes))[:len(bytes)/size_of(data.Path_Vertex)]
                range:=path_ranges[index]
                assert(range.fill.count==uint(len(batch.path.fill)))
                assert(range.fringe.count==uint(len(batch.path.fringe)))
                assert(range.cover.count==uint(len(batch.path.cover)))
                for vertex,offset in batch.path.fill {assert(values[int(range.fill.start)+offset]==data.path_vertex(vertex))}
                for vertex,offset in batch.path.fringe {assert(values[int(range.fringe.start)+offset]==data.path_vertex(vertex))}
            }
        }
        if round==0 {
            for offset in 0..<1000 {draw.solid(&list,{f32(offset),2,1,1},{1,1,1,1})}
        }
    }
}

readback :: proc(state:^renderer.Renderer,source:^dx.IBuffer,size:int)->[]u8 {
    descriptor:dx.BUFFER_DESC
    source->GetDesc(&descriptor)
    assert(descriptor.Usage==.DYNAMIC && descriptor.CPUAccessFlags==dx.CPU_ACCESS_FLAGS{.WRITE})
    descriptor.Usage=.STAGING
    descriptor.BindFlags={}
    descriptor.CPUAccessFlags={.READ}
    staging:^dx.IBuffer
    assert(state.device->CreateBuffer(&descriptor,nil,&staging)>=0)
    defer _=staging->Release()
    state.immediate->CopyResource(staging,source)
    mapped:dx.MAPPED_SUBRESOURCE
    assert(state.immediate->Map(staging,0,.READ,{},&mapped)>=0)
    defer state.immediate->Unmap(staging,0)
    assert(size>0 && size<=int(descriptor.ByteWidth))
    result:=make([]u8,size)
    mem.copy(raw_data(result),mapped.pData,len(result))
    return result
}
