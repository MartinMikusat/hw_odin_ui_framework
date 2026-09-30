package renderdata

import "core:testing"
import draw "ui_framework:draw"

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
