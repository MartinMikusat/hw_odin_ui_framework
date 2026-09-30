package main

import "core:fmt"
import "core:mem"
import "core:os"
import renderer "ui_framework:d3d11"
import dx "vendor:directx/d3d11"
import draw "ui_framework:draw"
import data "ui_framework:renderdata"
import atlas "ui_framework:glyphatlas"
import text "ui_framework:directwrite"

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
        verify_textures(&state)
        verify_glyph_upload(&state)
        verify_encoding(&state)
        verify_atlas_failure(&state)
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

verify_textures :: proc(state:^renderer.Renderer) {
    formats:=[2]atlas.Format{.Alpha,.Color}
    for format in formats {
        handle,status:=renderer.texture_create(state,format,8,8)
        assert(status>=0 && handle!=0)
        io:=renderer.atlas_io(state)
        assert(io.bind(io.user_data,u64(handle))==handle)
        bpp:=1
        if format==.Color {bpp=4}
        zero:[256]u8
        assert(renderer.texture_upload(state,handle,0,0,8,8,zero[:64*bpp],8*bpp)>=0)
        patch:[32]u8
        stride:=3*bpp+1
        for row in 0..<2 {
            for column in 0..<3 {
                for channel in 0..<bpp {patch[row*stride+column*bpp+channel]=u8(17+row*3+column*4+channel)}
            }
        }
        assert(renderer.texture_upload(state,handle,2,1,3,2,patch[:],stride)>=0)
        assert(renderer.texture_upload(state,handle,7,7,3,2,patch[:],stride)==renderer.INVALID_ARGUMENT)
        assert(renderer.texture_upload(state,handle,2,1,3,2,patch[:],3*bpp-1)==renderer.INVALID_ARGUMENT)
        verify_texture_pixels(state,handle,bpp)
        assert(renderer.texture_destroy(state,handle))
        assert(renderer.texture_get(state,handle)==nil && !renderer.texture_destroy(state,handle))
        replacement,replace_status:=renderer.texture_create(state,format,8,8)
        assert(replace_status>=0 && replacement!=handle)
        assert(renderer.texture_get(state,handle)==nil)
        io.destroy(io.user_data,u64(replacement))
        assert(state.texture_bytes==4)
    }
    assert(renderer.begin_frame(state)>=0)
}

verify_atlas_failure :: proc(state:^renderer.Renderer) {
    io:=renderer.atlas_io(state)
    assert(io.bind(io.user_data,0)==0 && state.atlas_error==renderer.INVALID_ARGUMENT)
    assert(renderer.begin_frame(state)==renderer.INVALID_ARGUMENT)
}

verify_texture_pixels :: proc(state:^renderer.Renderer,handle:draw.Texture_Handle,bpp:int) {
    source:=renderer.texture_get(state,handle)
    descriptor:dx.TEXTURE2D_DESC
    source.native->GetDesc(&descriptor)
    descriptor.Usage=.STAGING
    descriptor.BindFlags={}
    descriptor.CPUAccessFlags={.READ}
    staging:^dx.ITexture2D
    assert(state.device->CreateTexture2D(&descriptor,nil,&staging)>=0)
    defer _=staging->Release()
    state.immediate->CopyResource(staging,source.native)
    mapped:dx.MAPPED_SUBRESOURCE
    assert(state.immediate->Map(staging,0,.READ,{},&mapped)>=0)
    defer state.immediate->Unmap(staging,0)
    bytes:=cast([^]u8)mapped.pData
    for row in 0..<8 {
        for column in 0..<8 {
            for channel in 0..<bpp {
                expected:=u8(0)
                if row>=1 && row<3 && column>=2 && column<5 {expected=u8(17+(row-1)*3+(column-2)*4+channel)}
                assert(bytes[row*int(mapped.RowPitch)+column*bpp+channel]==expected)
            }
        }
    }
}

verify_glyph_upload :: proc(state:^renderer.Renderer) {
    font:text.Context
    assert(text.context_init(&font)>=0)
    {
    layout,status:=text.layout_create(&font,"café 😀 العربية","Consolas",12,400,false)
    assert(status>=0)
    defer text.layout_destroy(&layout)
    glyphs,glyph_status:=text.layout_glyphs(&font,&layout)
    assert(glyph_status>=0)
    defer text.glyph_buffer_destroy(&glyphs)
    list:draw.List
    draw.list_init(&list)
    defer draw.list_destroy(&list)
    assert(renderer.begin_frame(state)>=0)
    assert(text.begin_frame(&font,2,renderer.atlas_io(state))>=0)
    assert(text.emit_layout(&font,&list,&layout,&glyphs,{0,0,400,40},{size=12},{1,1,1,1})>=0)
    text.flush(&font)
    assert(state.atlas_error==0 && state.texture_bytes>4 && len(list.batches)>0)
    for &batch in list.batches {assert(renderer.texture_get(state,batch.key.texture)!=nil)}
    }
    text.context_destroy(&font)
    assert(state.texture_bytes==4)
}

verify_encoding :: proc(state:^renderer.Renderer) {
    descriptor:=dx.TEXTURE2D_DESC{Width=96,Height=64,MipLevels=1,ArraySize=1,Format=.R8G8B8A8_UNORM,SampleDesc={Count=1},Usage=.DEFAULT,BindFlags={.RENDER_TARGET}}
    target:^dx.ITexture2D
    assert(state.device->CreateTexture2D(&descriptor,nil,&target)>=0)
    defer _=target->Release()
    color:^dx.IRenderTargetView
    assert(state.device->CreateRenderTargetView(target,nil,&color)>=0)
    defer _=color->Release()
    descriptor.Format=.D24_UNORM_S8_UINT
    descriptor.BindFlags={.DEPTH_STENCIL}
    depth:^dx.ITexture2D
    assert(state.device->CreateTexture2D(&descriptor,nil,&depth)>=0)
    defer _=depth->Release()
    stencil:^dx.IDepthStencilView
    assert(state.device->CreateDepthStencilView(depth,nil,&stencil)>=0)
    defer _=stencil->Release()
    rules:=[2]draw.Path_Fill_Rule{.Non_Zero,.Even_Odd}
    for rule in rules {
        list:draw.List
        draw.list_init(&list,pixel_ratio=2)
        defer draw.list_destroy(&list)
        draw.push_clip(&list,{2,2,4,8})
        draw.solid(&list,{2,2,8,8},{1,0,0,0.5},edge_softness=0.5)
        draw.pop_clip(&list)
        draw.path_begin(&list)
        draw.path_circle(&list,16,32,10)
        draw.path_fill(&list,{1,0,0,1})
        draw.path_begin(&list)
        draw.path_circle(&list,48,32,13)
        draw.path_circle(&list,48,32,6)
        draw.path_solidity(&list,.Hole)
        draw.path_fill(&list,{0,1,0,1},rule)
        draw.path_begin(&list)
        draw.path_move_to(&list,70,20)
        draw.path_line_to(&list,90,44)
        draw.path_stroke(&list,{0,0,1,1},6,cap=.Round)
        assert(renderer.encode(state,color,nil,&list,{96,64})==renderer.INVALID_ARGUMENT)
        assert(renderer.encode(state,color,stencil,&list,{96,64})>=0)
        verify_encoded_pixels(state,target)
    }
    state.immediate->OMSetRenderTargets(0,nil,nil)
}

verify_encoded_pixels :: proc(state:^renderer.Renderer,target:^dx.ITexture2D) {
    descriptor:dx.TEXTURE2D_DESC
    target->GetDesc(&descriptor)
    descriptor.Usage=.STAGING
    descriptor.BindFlags={}
    descriptor.CPUAccessFlags={.READ}
    staging:^dx.ITexture2D
    assert(state.device->CreateTexture2D(&descriptor,nil,&staging)>=0)
    defer _=staging->Release()
    state.immediate->CopyResource(staging,target)
    mapped:dx.MAPPED_SUBRESOURCE
    assert(state.immediate->Map(staging,0,.READ,{},&mapped)>=0)
    defer state.immediate->Unmap(staging,0)
    bytes:=cast([^]u8)mapped.pData
    circle:=32*int(mapped.RowPitch)+16*4
    ring:=32*int(mapped.RowPitch)+58*4
    hole:=32*int(mapped.RowPitch)+48*4
    stroke:=32*int(mapped.RowPitch)+80*4
    solid:=58*int(mapped.RowPitch)+3*4
    clipped:=58*int(mapped.RowPitch)+7*4
    assert(bytes[circle]>240 && bytes[circle+1]<10 && bytes[circle+2]<10)
    assert(bytes[ring+1]>240 && bytes[ring]<10 && bytes[ring+2]<10)
    assert(bytes[hole]<10 && bytes[hole+1]<10 && bytes[hole+2]<10)
    assert(bytes[stroke+2]>240 && bytes[stroke]<10 && bytes[stroke+1]<10)
    assert(bytes[solid]>=126 && bytes[solid]<=129 && bytes[solid+3]==255)
    assert(bytes[clipped]==0 && bytes[clipped+1]==0 && bytes[clipped+2]==0)
}
