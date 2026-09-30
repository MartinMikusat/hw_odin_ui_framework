struct VertexOut {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float2 local : TEXCOORD1;
    float2 size : TEXCOORD2;
    float4 color : TEXCOORD3;
    nointerpolation float4 ramp_bottom : TEXCOORD4;
    nointerpolation float4 ramp_mid : TEXCOORD5;
    nointerpolation float4 ramp_top : TEXCOORD6;
    float4 corner_radii : TEXCOORD7;
    float2 effect_offset : TEXCOORD8;
    nointerpolation float2 hole_size : TEXCOORD9;
    nointerpolation float hole_radius : TEXCOORD10;
    float border_thickness : TEXCOORD11;
    float edge_softness : TEXCOORD12;
    nointerpolation uint texture_mode : TEXCOORD13;
    nointerpolation uint corner_shape : TEXCOORD14;
};

struct PathVertexOut {
    float4 position : SV_Position;
    float2 coverage : TEXCOORD0;
};

#define UI_TEXTURE Texture2D<float4>
#define UI_SAMPLER SamplerState
#define UI_SAMPLE(image, sampling, uv) image.Sample(sampling, uv)
#define UI_MIX lerp
#define UI_DISCARD() clip(-1)
#include "ui_common.h"

cbuffer QuadState : register(b0) { BatchUniforms quad_uniforms; };
cbuffer PathState : register(b1) { PathUniforms path_uniforms; };
Texture2D<float4> image_texture : register(t0);
SamplerState image_sampler : register(s0);

struct QuadInput {
    float4 dst : POSITION0;
    float4 src : TEXCOORD0;
    float4 color0 : COLOR0;
    float4 color1 : COLOR1;
    float4 color2 : COLOR2;
    float4 color3 : COLOR3;
    float4 corner_radii : TEXCOORD1;
    float2 effect_offset : TEXCOORD2;
    float2 metrics : TEXCOORD3;
    uint2 modes : TEXCOORD4;
};

VertexOut ui_vertex(QuadInput input, uint vertex_id : SV_VertexID) {
    QuadInstance instance = (QuadInstance)0;
    instance.dst = input.dst;
    instance.src = input.src;
    instance.colors[0] = input.color0;
    instance.colors[1] = input.color1;
    instance.colors[2] = input.color2;
    instance.colors[3] = input.color3;
    instance.corner_radii = input.corner_radii;
    instance.effect_offset = input.effect_offset;
    instance.border_thickness = input.metrics.x;
    instance.edge_softness = input.metrics.y;
    instance.texture_mode = input.modes.x;
    instance.corner_shape = input.modes.y;
    return make_quad_vertex(instance, vertex_id, quad_uniforms);
}

float4 ui_fragment(VertexOut input) : SV_Target {
    return shade_quad(input, image_texture, image_sampler);
}

struct PathInput {
    float2 position : POSITION0;
    float2 coverage : TEXCOORD0;
};

PathVertexOut path_vertex(PathInput input) {
    PathVertex vertex;
    vertex.position = input.position;
    vertex.coverage = input.coverage;
    return make_path_vertex(vertex, path_uniforms);
}

float4 path_fragment(PathVertexOut input) : SV_Target {
    return shade_path(input, path_uniforms);
}
