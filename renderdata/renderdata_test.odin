package renderdata

import "core:testing"
import draw "ui_framework:draw"
import "core:math"

@(test)
scissor_clips_fractional_coordinates_and_rejects_invalid_extents_test :: proc(t:^testing.T) {
    key:=draw.Batch_Key{clip_set=true,clip={10.25,20.25,5.5,7.25}}
    rect,visible:=scissor_rect(key,{100,60},2)
    testing.expect(t,visible)
    testing.expect_value(t,rect,[4]u32{20,65,11,14})
    key.clip={200,0,10,10}
    _,outside:=scissor_rect(key,{100,60},2)
    testing.expect(t,!outside)
    key.clip={0,0,10,-1}
    _,negative:=scissor_rect(key,{100,60},2)
    testing.expect(t,!negative)
    _,invalid:=scissor_rect({}, {math.nan_f32(),60},2)
    testing.expect(t,!invalid)
}

@(test)
shader_uniform_layout_test :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(Batch_Uniforms), 48)
	testing.expect_value(t, size_of(Path_Vertex), 16)
	testing.expect_value(t, size_of(Path_Uniforms), 80)
}

@(test)
gpu_quad_instance_keeps_layout_corner_shape_and_effect_offset_test :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(Quad_Instance), 144)
	instance := quad_instance(draw.Quad_Instance{
		corner_shape = .Squircle,
		effect_offset = {-1.25, 1.25},
	})
	testing.expect_value(t, instance.corner_shape, u32(draw.Corner_Shape.Squircle))
	testing.expect_value(t, instance.effect_offset, [2]f32{-1.25, 1.25})
}
