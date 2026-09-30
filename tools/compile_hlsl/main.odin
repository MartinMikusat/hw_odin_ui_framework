package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import win "core:sys/windows"
import shader "vendor:directx/d3d_compiler"

HLSL_SOURCE :: #load("../../shaders/ui.hlsl")
SHARED_SOURCE :: #load("../../shaders/ui_common.h")
BYTECODE_BYTES_MAX :: 1024*1024

Shader :: struct {entry,profile:cstring,name:string}
SHADERS :: [4]Shader{
    {"ui_vertex","vs_5_0","ui_vertex.cso"},
    {"ui_fragment","ps_5_0","ui_fragment.cso"},
    {"path_vertex","vs_5_0","path_vertex.cso"},
    {"path_fragment","ps_5_0","path_fragment.cso"},
}

release_blob :: proc(blob:^shader.ID3DBlob) {
    if blob!=nil {_=(cast(^win.IUnknown)blob)->Release()}
}

compile_shaders :: proc(output:string)->bool {
    source,owned:=strings.replace_all(string(HLSL_SOURCE),"#include \"ui_common.h\"",string(SHARED_SOURCE))
    if !owned || len(source)==0 {fmt.eprintln("Shader source allocation failed.");return false}
    defer delete(source)
    assert(len(source)>0 && len(source)<64*1024)
    blobs:[4]^shader.ID3DBlob
    defer for blob in blobs {release_blob(blob)}
    flags:=u32(shader.D3DCOMPILE{.ENABLE_STRICTNESS,.WARNINGS_ARE_ERRORS,.OPTIMIZATION_LEVEL3})
    for spec,index in SHADERS {
        errors:^shader.ID3DBlob
        result:=shader.Compile(raw_data(source),win.SIZE_T(len(source)),"ui.hlsl",nil,nil,spec.entry,spec.profile,flags,0,&blobs[index],&errors)
        if errors!=nil {
            size:=errors->GetBufferSize()
            message:=(cast([^]u8)errors->GetBufferPointer())[:int(min(size,16*1024))]
            fmt.eprintln(string(message))
            release_blob(errors)
        }
        if result<0 || blobs[index]==nil {
            fmt.eprintf("Shader compilation failed: %s (0x%08x).\n",spec.name,u32(result))
            return false
        }
        size:=blobs[index]->GetBufferSize()
        if size==0 || size>BYTECODE_BYTES_MAX {fmt.eprintln("Shader bytecode exceeds its bound.");return false}
    }
    for spec,index in SHADERS {
        path,path_error:=filepath.join({output,spec.name})
        if path_error!=nil {fmt.eprintln("Shader path allocation failed.");return false}
        blob:=blobs[index]
        bytes:=(cast([^]u8)blob->GetBufferPointer())[:int(blob->GetBufferSize())]
        write_error:=os.write_entire_file(path,bytes)
        delete(path)
        if write_error!=nil {fmt.eprintf("Shader output failed: %s (%v).\n",spec.name,write_error);return false}
    }
    return true
}

main :: proc() {
    if len(os.args)!=2 || len(os.args[1])==0 || len(os.args[1])>1024 {
        fmt.eprintln("usage: compile_hlsl OUTPUT_DIRECTORY")
        os.exit(2)
    }
    if !compile_shaders(os.args[1]) {os.exit(1)}
    fmt.println("Compiled four Direct3D 11 shaders.")
}
