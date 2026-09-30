package d3d11

import "core:math"
import draw "ui_framework:draw"
import data "ui_framework:renderdata"
import dx "vendor:directx/d3d11"
import win "core:sys/windows"

Stencil_Mode :: enum {Disabled,Non_Zero,Even_Odd,Equal,Not_Equal,Stroke,Clear}

renderer_init_encoding :: proc(renderer:^Renderer)->win.HRESULT {
    for mode in Stencil_Mode {
        face:=dx.DEPTH_STENCILOP_DESC{StencilFailOp=.KEEP,StencilDepthFailOp=.KEEP,StencilPassOp=.KEEP,StencilFunc=.ALWAYS}
        descriptor:=dx.DEPTH_STENCIL_DESC{DepthEnable=false,DepthWriteMask=.ZERO,DepthFunc=.ALWAYS,StencilEnable=mode!=.Disabled,StencilReadMask=255,StencilWriteMask=255,FrontFace=face,BackFace=face}
        switch mode {
        case .Disabled:
        case .Non_Zero: descriptor.FrontFace.StencilPassOp=.INCR;descriptor.BackFace.StencilPassOp=.DECR
        case .Even_Odd: descriptor.FrontFace.StencilPassOp=.INVERT;descriptor.BackFace.StencilPassOp=.INVERT
        case .Equal: descriptor.FrontFace.StencilFunc=.EQUAL;descriptor.BackFace.StencilFunc=.EQUAL
        case .Not_Equal: descriptor.FrontFace.StencilFunc=.NOT_EQUAL;descriptor.BackFace.StencilFunc=.NOT_EQUAL;descriptor.FrontFace.StencilPassOp=.ZERO;descriptor.BackFace.StencilPassOp=.ZERO
        case .Stroke: descriptor.FrontFace.StencilFunc=.EQUAL;descriptor.BackFace.StencilFunc=.EQUAL;descriptor.FrontFace.StencilPassOp=.INCR_SAT;descriptor.BackFace.StencilPassOp=.INCR_SAT
        case .Clear: descriptor.FrontFace.StencilPassOp=.ZERO;descriptor.BackFace.StencilPassOp=.ZERO
        }
        result:=renderer.device->CreateDepthStencilState(&descriptor,&renderer.stencil[mode])
        if result<0 {return result}
    }
    quad:=dx.BUFFER_DESC{ByteWidth=size_of(data.Batch_Uniforms),Usage=.DEFAULT,BindFlags={.CONSTANT_BUFFER}}
    result:=renderer.device->CreateBuffer(&quad,nil,&renderer.quad_uniforms)
    if result<0 {return result}
    path:=dx.BUFFER_DESC{ByteWidth=size_of(data.Path_Uniforms),Usage=.DEFAULT,BindFlags={.CONSTANT_BUFFER}}
    return renderer.device->CreateBuffer(&path,nil,&renderer.path_uniforms)
}

// Targets belong to this device and are borrowed for this call. Supply a stencil
// view for compound fills and strokes. Max composition uses RGBA8 or BGRA8
// targets. A failed frame must not be presented.
encode :: proc(renderer:^Renderer,target:^dx.IRenderTargetView,stencil:^dx.IDepthStencilView,list:^draw.List,viewport_points:[2]f32,scale:=f32(1),clear:draw.Color={0,0,0,1})->win.HRESULT {
    assert(renderer!=nil && renderer.device!=nil && renderer.immediate!=nil)
    if renderer.atlas_error<0 {return renderer.atlas_error}
    if target==nil || list==nil || len(list.batches)>BATCHES_MAX || (math.is_nan(scale) || math.is_inf(scale)) || scale<1 || scale>8 {return INVALID_ARGUMENT}
    for side in viewport_points {
        if (math.is_nan(side) || math.is_inf(side)) || side<=0 || side*scale>TEXTURE_SIDE_MAX {return INVALID_ARGUMENT}
    }
    if data.list_requires_stencil(list) && stencil==nil {return INVALID_ARGUMENT}
    needs_max:=false
    for &batch in list.batches {
        if batch.key.combine==.Max {
            if batch.kind!=.Quad {return INVALID_ARGUMENT}
            needs_max=true
        }
        if batch.kind==.Quad && batch.key.texture!=0 && texture_get(renderer,batch.key.texture)==nil {return INVALID_ARGUMENT}
    }
    if needs_max {
        result:=max_target_ensure(renderer,target,u32(max(f32(1),viewport_points[0]*scale)),u32(max(f32(1),viewport_points[1]*scale)))
        if result<0 {return result}
    }
    ranges,range_error:=make([]data.Batch_Range,len(list.batches))
    if range_error!=nil {return OUT_OF_MEMORY}
    defer delete(ranges)
    path_ranges,path_error:=make([]data.Path_Batch_Range,len(list.batches))
    if path_error!=nil {return OUT_OF_MEMORY}
    defer delete(path_ranges)
    result:=upload_list(renderer,list,ranges,path_ranges)
    if result<0 {return result}
    immediate:=renderer.immediate
    targets:=[1]^dx.IRenderTargetView{target}
    immediate->OMSetRenderTargets(1,raw_data(targets[:]),stencil)
    clear_value:=clear
    immediate->ClearRenderTargetView(target,&clear_value)
    if stencil!=nil {immediate->ClearDepthStencilView(stencil,{.STENCIL},0,0)}
    viewport:=dx.VIEWPORT{Width=viewport_points[0]*scale,Height=viewport_points[1]*scale,MinDepth=0,MaxDepth=1}
    immediate->RSSetViewports(1,&viewport)
    immediate->RSSetState(renderer.rasterizer)
    immediate->IASetPrimitiveTopology(.TRIANGLELIST)
    immediate->GSSetShader(nil,nil,0)
    immediate->HSSetShader(nil,nil,0)
    immediate->DSSetShader(nil,nil,0)
    in_max:=false
    for &batch,index in list.batches {
        if batch.key.combine==.Max && !in_max {
            max_target_bind(renderer)
            in_max=true
        } else if batch.key.combine!=.Max && in_max {
            immediate->OMSetRenderTargets(1,raw_data(targets[:]),stencil)
            max_target_composite(renderer,viewport_points,scale)
            in_max=false
        }
        if !encode_scissor(renderer,batch.key,viewport_points,scale) {continue}
        switch batch.kind {
        case .Quad:
            blend:=renderer.over_blend
            if in_max {blend=renderer.max_blend}
            encode_quad(renderer,&batch,ranges[index],viewport_points,blend)
        case .Path: encode_path(renderer,&batch,path_ranges[index],viewport_points)
        }
    }
    if in_max {
        immediate->OMSetRenderTargets(1,raw_data(targets[:]),stencil)
        max_target_composite(renderer,viewport_points,scale)
    }
    return renderer.device->GetDeviceRemovedReason()
}

encode_scissor :: proc(renderer:^Renderer,key:draw.Batch_Key,viewport:[2]f32,scale:f32)->bool {
    rect,visible:=data.scissor_rect(key,viewport,scale)
    if !visible {return false}
    native:=dx.RECT{left=i32(rect[0]),top=i32(rect[1]),right=i32(rect[0]+rect[2]),bottom=i32(rect[1]+rect[3])}
    renderer.immediate->RSSetScissorRects(1,&native)
    return true
}

encode_quad :: proc(renderer:^Renderer,batch:^draw.Batch,range:data.Batch_Range,viewport:[2]f32,blend:^dx.IBlendState) {
    if range.count==0 {return}
    assert(renderer.quads.native!=nil)
    handle:=batch.key.texture
    if handle==0 {handle=renderer.white_texture}
    texture:=texture_get(renderer,handle)
    assert(texture!=nil)
    encode_quad_bind(renderer,batch.key,renderer.quads.native,u32(range.start)*size_of(data.Quad_Instance),u32(range.count),texture.view,viewport,blend)
}

encode_quad_bind :: proc(renderer:^Renderer,key:draw.Batch_Key,vertex_buffer:^dx.IBuffer,offset:u32,count:u32,view:^dx.IShaderResourceView,viewport:[2]f32,blend:^dx.IBlendState) {
    uniforms:=data.Batch_Uniforms{viewport=viewport,opacity=key.opacity,transform={key.transform.m00,key.transform.m01,key.transform.m10,key.transform.m11},translation={key.transform.tx,key.transform.ty}}
    immediate:=renderer.immediate
    immediate->UpdateSubresource(renderer.quad_uniforms,0,nil,&uniforms,0,0)
    constants:=[1]^dx.IBuffer{renderer.quad_uniforms}
    immediate->VSSetConstantBuffers(0,1,raw_data(constants[:]))
    immediate->VSSetShader(renderer.quad_vertex,nil,0)
    immediate->PSSetShader(renderer.quad_fragment,nil,0)
    immediate->IASetInputLayout(renderer.quad_layout)
    buffer:=[1]^dx.IBuffer{vertex_buffer}
    stride:=u32(size_of(data.Quad_Instance))
    vertex_offset:=offset
    immediate->IASetVertexBuffers(0,1,raw_data(buffer[:]),&stride,&vertex_offset)
    views:=[1]^dx.IShaderResourceView{view}
    immediate->PSSetShaderResources(0,1,raw_data(views[:]))
    sampler:=renderer.linear_sampler
    if key.sampler==.Nearest {sampler=renderer.nearest_sampler}
    samplers:=[1]^dx.ISamplerState{sampler}
    immediate->PSSetSamplers(0,1,raw_data(samplers[:]))
    immediate->OMSetDepthStencilState(renderer.stencil[.Disabled],0)
    immediate->OMSetBlendState(blend,nil,0xffffffff)
    immediate->DrawInstanced(6,count,0,0)
}

encode_path :: proc(renderer:^Renderer,batch:^draw.Batch,ranges:data.Path_Batch_Range,viewport:[2]f32) {
    uniforms:=data.Path_Uniforms{viewport=viewport,opacity=batch.key.opacity,transform={batch.key.transform.m00,batch.key.transform.m01,batch.key.transform.m10,batch.key.transform.m11},translation={batch.key.transform.tx,batch.key.transform.ty},color=batch.path.color,stroke_mult=batch.path.stroke_mult}
    immediate:=renderer.immediate
    immediate->VSSetShader(renderer.path_vertex,nil,0)
    immediate->PSSetShader(renderer.path_fragment,nil,0)
    immediate->IASetInputLayout(renderer.path_layout)
    buffer:=[1]^dx.IBuffer{renderer.paths.native}
    stride:=u32(size_of(data.Path_Vertex))
    offset:=u32(0)
    immediate->IASetVertexBuffers(0,1,raw_data(buffer[:]),&stride,&offset)
    constants:=[1]^dx.IBuffer{renderer.path_uniforms}
    immediate->VSSetConstantBuffers(1,1,raw_data(constants[:]))
    immediate->PSSetConstantBuffers(1,1,raw_data(constants[:]))
    switch batch.path.kind {
    case .Convex_Fill:
        encode_path_range(renderer,ranges.fill,&uniforms,.Disabled,-1,false)
        encode_path_range(renderer,ranges.fringe,&uniforms,.Disabled,-1,false)
    case .Compound_Fill:
        mode:Stencil_Mode=.Non_Zero
        if batch.path.fill_rule==.Even_Odd {mode=.Even_Odd}
        encode_path_range(renderer,ranges.fill,&uniforms,mode,-1,true)
        encode_path_range(renderer,ranges.fringe,&uniforms,.Equal,-1,false)
        encode_path_range(renderer,ranges.cover,&uniforms,.Not_Equal,-1,false)
    case .Stroke:
        encode_path_range(renderer,ranges.fill,&uniforms,.Stroke,1-0.5/255,false)
        encode_path_range(renderer,ranges.fill,&uniforms,.Equal,-1,false)
        encode_path_range(renderer,ranges.fill,&uniforms,.Clear,-1,true)
    }
}

encode_path_range :: proc(renderer:^Renderer,range:data.Batch_Range,uniforms:^data.Path_Uniforms,mode:Stencil_Mode,threshold:f32,stencil_only:bool) {
    if range.count==0 {return}
    assert(range.count%3==0)
    uniforms.stroke_threshold=threshold
    immediate:=renderer.immediate
    immediate->UpdateSubresource(renderer.path_uniforms,0,nil,uniforms,0,0)
    immediate->OMSetDepthStencilState(renderer.stencil[mode],0)
    blend:=renderer.over_blend
    if stencil_only {blend=renderer.stencil_blend}
    immediate->OMSetBlendState(blend,nil,0xffffffff)
    immediate->Draw(u32(range.count),u32(range.start))
}
