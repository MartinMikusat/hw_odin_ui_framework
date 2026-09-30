#ifndef HW_UI_COMMON_H
#define HW_UI_COMMON_H

struct QuadInstance {
    float4 dst;
    float4 src;
    float4 colors[4];
    float4 corner_radii;
    float2 effect_offset;
    float border_thickness;
    float edge_softness;
    uint texture_mode;
    uint corner_shape;
    uint2 tail;
};

struct BatchUniforms {
    float2 viewport;
    float opacity;
    float padding;
    float4 transform;
    float2 translation;
};

struct PathVertex {
    float2 position;
    float2 coverage;
};

struct PathUniforms {
    float2 viewport;
    float opacity;
    float padding;
    float4 transform;
    float2 translation;
    float2 transform_tail;
    float4 color;
    float stroke_mult;
    float stroke_threshold;
    float2 tail;
};

VertexOut make_quad_vertex(QuadInstance instance, uint vertex_id, BatchUniforms uniforms) {
    const float2 corners[6] = {
        float2(0, 0), float2(1, 0), float2(1, 1),
        float2(0, 0), float2(1, 1), float2(0, 1),
    };
    float2 corner = corners[vertex_id];
    float2 point = instance.dst.xy + corner * instance.dst.zw;
    point = float2(
        uniforms.transform.x * point.x + uniforms.transform.z * point.y,
        uniforms.transform.y * point.x + uniforms.transform.w * point.y
    ) + uniforms.translation;
    float2 ndc = point / uniforms.viewport * 2.0 - 1.0;

    uint color_index = uint(corner.x) * 2u + uint(corner.y);
    VertexOut output;
    output.position = float4(ndc, 0, 1);
    output.uv = instance.src.xy + corner * instance.src.zw;
    output.local = corner * instance.dst.zw;
    output.size = instance.dst.zw;
    output.color = instance.colors[color_index] * uniforms.opacity;
    output.ramp_bottom = instance.colors[0] * uniforms.opacity;
    output.ramp_mid = instance.colors[1] * uniforms.opacity;
    output.ramp_top = instance.colors[2] * uniforms.opacity;
    output.corner_radii = instance.corner_radii;
    output.effect_offset = instance.effect_offset;
    output.hole_size = instance.src.zw;
    output.hole_radius = instance.src.x;
    output.border_thickness = instance.border_thickness;
    output.edge_softness = max(instance.edge_softness, 0.0001);
    output.texture_mode = instance.texture_mode;
    output.corner_shape = instance.corner_shape;
    return output;
}

float rounded_distance(float2 local, float2 size, float4 radii, uint corner_shape) {
    float2 centered = local - size * 0.5;
    bool right = centered.x >= 0.0;
    bool top = centered.y >= 0.0;
    float radius = top ? (right ? radii.w : radii.y)
                       : (right ? radii.z : radii.x);
    radius = clamp(radius, 0.0, min(size.x, size.y) * 0.5);
    float2 q = abs(centered) - size * 0.5 + radius;
    float2 outside = max(q, 0.0);
    float inside = min(max(q.x, q.y), 0.0);
    if ((corner_shape != 1u && corner_shape != 2u) ||
        radius <= 0.0 ||
        outside.x <= 0.0 ||
        outside.y <= 0.0) {
        return length(outside) + inside - radius;
    }

    // Squircle is CSS superellipse(2): x^4 + y^4 = r^4.
    // Squircle_Pill uses p=2.2 so a half-height radius reads as a capsule
    // instead of hugging the box. Normalize by the gradient so AA stays in points.
    float p = corner_shape == 2u ? 2.2 : 4.0;
    float2 ap = pow(outside, float2(p, p));
    float norm = pow(ap.x + ap.y, 1.0 / p);
    float2 gp = pow(outside, float2(p - 1.0, p - 1.0));
    float2 grad = gp * pow(max(norm, 0.0001), 1.0 - p);
    return (norm - radius) / max(length(grad), 0.0001);
}

float4 shade_quad(VertexOut input, UI_TEXTURE image_texture, UI_SAMPLER image_sampler) {
    float2 sdf_local = input.local;
    float2 sdf_size = input.size;
    if (input.texture_mode == 3u) {
        float pad = input.edge_softness;
        sdf_local = input.local - pad;
        sdf_size = max(input.size - 2.0 * pad, float2(0.001, 0.001));
    }
    float distance = rounded_distance(
        sdf_local,
        sdf_size,
        input.corner_radii,
        input.corner_shape
    );
    float outer_alpha = 1.0 - smoothstep(-input.edge_softness, input.edge_softness, distance);
    if (input.texture_mode == 3u && input.hole_size.x > 0.0 && input.hole_size.y > 0.0) {
        float hole_r = max(input.hole_radius, 0.0);
        float4 hole_radii = float4(hole_r, hole_r, hole_r, hole_r);
        float hole_dist = rounded_distance(
            input.local - input.effect_offset,
            input.hole_size,
            hole_radii,
            input.corner_shape
        );
        float hole_inside = 1.0 - smoothstep(-0.5, 0.5, hole_dist);
        outer_alpha *= (1.0 - hole_inside);
    }
    if (input.texture_mode == 4u) {
        float shifted_distance = rounded_distance(
            input.local + input.effect_offset,
            input.size,
            input.corner_radii,
            input.corner_shape
        );
        float shifted_inside = 1.0 - smoothstep(
            -input.edge_softness,
            input.edge_softness,
            shifted_distance
        );
        float clip_alpha = 1.0 - smoothstep(-0.5, 0.5, distance);
        outer_alpha = clip_alpha * (1.0 - shifted_inside);
    }
    if (input.border_thickness > 0.0) {
        float inner_distance = distance + input.border_thickness;
        float inner_alpha = 1.0 - smoothstep(-input.edge_softness, input.edge_softness, inner_distance);
        outer_alpha = max(0.0, outer_alpha - inner_alpha);
    }
    if (input.texture_mode == 5u) {
        float t = input.local.y / max(input.size.y, 0.0001);
        float y0 = input.effect_offset.x;
        float y1 = input.effect_offset.y;
        float feather = max(input.uv.x, 0.0001);
        float low = y0 <= 0.0 ? 1.0 : smoothstep(y0, y0 + feather, t);
        float high = y1 >= 1.0 ? 1.0 : (1.0 - smoothstep(y1 - feather, y1, t));
        outer_alpha *= low * high;
    }

    float4 tint = input.color;
    if (input.texture_mode == 6u) {
        float t = saturate(input.local.y / max(input.size.y, 0.0001));
        float y0 = input.effect_offset.x;
        float y1 = input.effect_offset.y;
        if (t <= y0) {
            float u = y0 <= 0.0 ? 1.0 : saturate(t / max(y0, 0.0001));
            tint = UI_MIX(input.ramp_bottom, input.ramp_mid, smoothstep(0.0, 1.0, u));
        } else if (t <= y1) {
            tint = input.ramp_mid;
        } else {
            float u = y1 >= 1.0 ? 1.0 : saturate((t - y1) / max(1.0 - y1, 0.0001));
            tint = UI_MIX(input.ramp_mid, input.ramp_top, smoothstep(0.0, 1.0, u));
        }
    }
    float4 result;
    if (input.texture_mode == 0u || input.texture_mode == 3u ||
        input.texture_mode == 4u || input.texture_mode == 5u ||
        input.texture_mode == 6u) {
        result = float4(tint.rgb * tint.a, tint.a);
    } else if (input.texture_mode == 1u) {
        float mask = UI_SAMPLE(image_texture, image_sampler, input.uv).r;
        float alpha = tint.a * mask;
        result = float4(tint.rgb * alpha, alpha);
    } else {
        float4 texel = UI_SAMPLE(image_texture, image_sampler, input.uv);
        result = float4(texel.rgb * tint.rgb * tint.a, texel.a * tint.a);
    }
    return result * outer_alpha;
}

PathVertexOut make_path_vertex(PathVertex path_input, PathUniforms uniforms) {
    float2 point = float2(
        uniforms.transform.x * path_input.position.x + uniforms.transform.z * path_input.position.y,
        uniforms.transform.y * path_input.position.x + uniforms.transform.w * path_input.position.y
    ) + uniforms.translation;
    float2 ndc = point / uniforms.viewport * 2.0 - 1.0;
    PathVertexOut output;
    output.position = float4(ndc, 0, 1);
    output.coverage = path_input.coverage;
    return output;
}

float4 shade_path(PathVertexOut input, PathUniforms uniforms) {
    float edge = min(
        1.0,
        (1.0 - abs(input.coverage.x * 2.0 - 1.0)) * uniforms.stroke_mult
    );
    float coverage = min(1.0, edge) * min(1.0, input.coverage.y);
    if (uniforms.stroke_threshold >= 0.0 && coverage < uniforms.stroke_threshold) {
        UI_DISCARD();
    }
    float alpha = uniforms.color.a * uniforms.opacity * coverage;
    return float4(uniforms.color.rgb * alpha, alpha);
}

#endif
