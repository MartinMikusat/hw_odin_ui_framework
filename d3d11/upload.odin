package d3d11

import draw "ui_framework:draw"
import data "ui_framework:renderdata"
import dx "vendor:directx/d3d11"
import win "core:sys/windows"

UPLOAD_BYTES_MAX :: 64*1024*1024
UPLOAD_BYTES_MIN :: 64*1024
BATCHES_MAX :: 65536

Upload_Buffer :: struct {native:^dx.IBuffer,capacity:u32}

// WRITE_DISCARD lets the driver retain storage used by submitted draws. The
// next upload replaces the current contents; encode them before uploading again.
// Discard the frame if upload fails; partial data must not be encoded.
upload_list :: proc(renderer:^Renderer,list:^draw.List,ranges:[]data.Batch_Range,path_ranges:[]data.Path_Batch_Range)->win.HRESULT {
    assert(renderer!=nil && renderer.device!=nil && renderer.immediate!=nil)
    if list==nil || len(list.batches)>BATCHES_MAX || len(ranges)!=len(list.batches) || len(path_ranges)!=len(list.batches) {return INVALID_ARGUMENT}
    quads,paths:=0,0
    for &batch in list.batches {
        if batch.kind==.Quad {
            if len(batch.instances)>UPLOAD_BYTES_MAX/size_of(data.Quad_Instance)-quads {return INVALID_ARGUMENT}
            quads+=len(batch.instances)
        } else {
            counts:=[3]int{len(batch.path.fill),len(batch.path.fringe),len(batch.path.cover)}
            for count in counts {
                if count>UPLOAD_BYTES_MAX/size_of(data.Path_Vertex)-paths {return INVALID_ARGUMENT}
                paths+=count
            }
        }
    }
    for &range in ranges {range={}}
    for &range in path_ranges {range={}}
    if quads>0 {
        mapped,result:=upload_map(renderer,&renderer.quads,u32(quads*size_of(data.Quad_Instance)))
        if result<0 {return result}
        vertices:=(cast([^]data.Quad_Instance)mapped)[:quads]
        cursor:=0
        for &batch,index in list.batches {
            if batch.kind!=.Quad {continue}
            ranges[index]={uint(cursor),uint(len(batch.instances))}
            for instance in batch.instances {vertices[cursor]=data.quad_instance(instance);cursor+=1}
        }
        assert(cursor==quads)
        renderer.immediate->Unmap(renderer.quads.native,0)
    }
    if paths>0 {
        mapped,result:=upload_map(renderer,&renderer.paths,u32(paths*size_of(data.Path_Vertex)))
        if result<0 {return result}
        data.pack_path_vertices(list,(cast([^]data.Path_Vertex)mapped)[:paths],path_ranges)
        renderer.immediate->Unmap(renderer.paths.native,0)
    }
    return 0
}

upload_map :: proc(renderer:^Renderer,buffer:^Upload_Buffer,size:u32)->(rawptr,win.HRESULT) {
    assert(size>0 && size<=UPLOAD_BYTES_MAX)
    if size>buffer.capacity {
        capacity:=u32(UPLOAD_BYTES_MIN)
        for capacity<size {capacity*=2}
        descriptor:=dx.BUFFER_DESC{ByteWidth=capacity,Usage=.DYNAMIC,BindFlags={.VERTEX_BUFFER},CPUAccessFlags={.WRITE}}
        replacement:^dx.IBuffer
        result:=renderer.device->CreateBuffer(&descriptor,nil,&replacement)
        if result<0 {release(replacement);return nil,result}
        release(buffer.native)
        buffer.native=replacement
        buffer.capacity=capacity
    }
    mapped:dx.MAPPED_SUBRESOURCE
    result:=renderer.immediate->Map(buffer.native,0,.WRITE_DISCARD,{},&mapped)
    if result<0 {return nil,result}
    assert(mapped.pData!=nil)
    return mapped.pData,result
}
