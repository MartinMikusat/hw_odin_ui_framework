#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float2 local;
    float2 size;
    float4 color;
    float4 ramp_bottom [[flat]];
    float4 ramp_mid [[flat]];
    float4 ramp_top [[flat]];
    float4 corner_radii;
    float2 effect_offset;
    float2 hole_size [[flat]];
    float hole_radius [[flat]];
    float border_thickness;
    float edge_softness;
    uint texture_mode [[flat]];
    uint corner_shape [[flat]];
};

struct PathVertexOut {
    float4 position [[position]];
    float2 coverage;
};

#define UI_TEXTURE texture2d<float>
#define UI_SAMPLER sampler
#define UI_SAMPLE(image, sampling, uv) image.sample(sampling, uv)
#define UI_MIX mix
#define UI_DISCARD discard_fragment
#include "ui_common.h"

vertex VertexOut ui_vertex(
    uint vertex_id [[vertex_id]],
    uint instance_id [[instance_id]],
    const device QuadInstance *instances [[buffer(0)]],
    constant BatchUniforms &uniforms [[buffer(1)]]) {
    return make_quad_vertex(instances[instance_id], vertex_id, uniforms);
}

fragment float4 ui_fragment(
    VertexOut input [[stage_in]],
    texture2d<float> image [[texture(0)]],
    sampler sampling [[sampler(0)]]) {
    return shade_quad(input, image, sampling);
}

vertex PathVertexOut path_vertex(
    uint vertex_id [[vertex_id]],
    const device PathVertex *vertices [[buffer(0)]],
    constant PathUniforms &uniforms [[buffer(1)]]) {
    return make_path_vertex(vertices[vertex_id], uniforms);
}

fragment float4 path_fragment(
    PathVertexOut input [[stage_in]],
    constant PathUniforms &uniforms [[buffer(1)]]) {
    return shade_path(input, uniforms);
}
