package diagnostics

import "core:testing"
import ui "ui_framework:core"
import draw "ui_framework:draw"

@(test)
snapshot_diff_reports_structural_and_state_changes_test :: proc(t: ^testing.T) {
	before_records := []ui.Control_Record{
		{id = 1, functional_name = "play", action = 10, rect = {0, 0, 20, 10}, enabled = true},
		{id = 2, functional_name = "stop", action = 11, rect = {20, 0, 20, 10}, enabled = true},
	}
	after_records := []ui.Control_Record{
		{id = 1, functional_name = "play", action = 10, rect = {0, 0, 24, 10}, enabled = false},
		{id = 3, functional_name = "reset", action = 12, rect = {24, 0, 20, 10}, enabled = true},
	}
	before := snapshot_make(1, before_records)
	defer snapshot_destroy(&before)
	after := snapshot_make(2, after_records)
	defer snapshot_destroy(&after)
	diff := diff_make(before, after)
	defer diff_destroy(&diff)
	testing.expect_value(t, len(diff.changes), 4)
	testing.expect_value(t, diff.changes[0].kind, Change_Kind.Moved)
	testing.expect_value(t, diff.changes[1].kind, Change_Kind.Enabled_Changed)
	testing.expect_value(t, diff.changes[2].kind, Change_Kind.Removed)
	testing.expect_value(t, diff.changes[3].kind, Change_Kind.Added)
}

@(test)
render_trace_checks_order_without_requiring_adjacency_test :: proc(t: ^testing.T) {
	trace := []draw.Trace_Entry{
		{label = "background text"},
		{label = "video"},
		{label = "backdrop"},
		{label = "modal surface"},
		{label = "modal text"},
	}
	labels := []string{"background text", "backdrop", "modal surface", "modal text"}
	testing.expect(t, render_order_matches(trace, labels))
	wrong := []string{"backdrop", "background text"}
	testing.expect(t, !render_order_matches(trace, wrong))
}

@(test)
performance_recorder_retains_ordered_recent_frames_test :: proc(t: ^testing.T) {
	recorder: Performance_Recorder
	testing.expect(t, performance_recorder_init(&recorder))
	defer performance_recorder_destroy(&recorder)

	first := performance_frame_begin(&recorder, 1_000)
	zone := performance_zone_begin(&recorder, first, Performance_Zone_ID(1), 1_100)
	performance_counter_set(&recorder, first, Performance_Counter_ID(2), 17)
	performance_zone_end(&recorder, zone, 1_300)
	performance_frame_end(&recorder, first, 1_500)

	second := performance_frame_begin(&recorder, 2_000)
	performance_frame_end(&recorder, second, 2_400)
	frames := performance_recent_frames(&recorder, 1_500)
	defer delete(frames)
	testing.expect_value(t, len(frames), 2)
	testing.expect_value(t, frames[0].sequence, first)
	testing.expect_value(t, frames[0].spans[0].end_ns-frames[0].spans[0].start_ns, i64(200))
	testing.expect_value(t, frames[0].counters[0].value, i64(17))
	testing.expect_value(t, frames[1].sequence, second)
	testing.expect_value(t, frames[1].callback_gap_ns, i64(1_000))
}

@(test)
performance_recorder_applies_and_discards_gpu_completions_test :: proc(t: ^testing.T) {
	recorder: Performance_Recorder
	testing.expect(t, performance_recorder_init(&recorder))
	defer performance_recorder_destroy(&recorder)
	sequence := performance_frame_begin(&recorder, 10_000)
	performance_frame_end(&recorder, sequence, 11_000)
	performance_gpu_complete(&recorder, {
		sequence = sequence,
		scheduled_ns = 11_100,
		completed_ns = 12_000,
		gpu_started_ns = 11_200,
		gpu_ended_ns = 11_800,
	})
	performance_gpu_complete(&recorder, {sequence = sequence+99, completed_ns = 13_000})
	frames := performance_recent_frames(&recorder, 10_000)
	defer delete(frames)
	testing.expect_value(t, frames[0].gpu_completed_ns, i64(12_000))
	testing.expect_value(t, frames[0].gpu_ended_ns-frames[0].gpu_started_ns, i64(600))
}

@(test)
performance_recorder_wraps_and_marks_capacity_overflow_test :: proc(t: ^testing.T) {
	recorder: Performance_Recorder
	testing.expect(t, performance_recorder_init(&recorder))
	defer performance_recorder_destroy(&recorder)
	first_sequence := u64(0)
	for frame_index in 0..<PERFORMANCE_FRAME_CAPACITY+2 {
		sequence := performance_frame_begin(&recorder, i64(frame_index+1)*1_000)
		if frame_index == 0 {first_sequence = sequence}
		if frame_index == PERFORMANCE_FRAME_CAPACITY+1 {
			for zone_index in 0..<PERFORMANCE_SPAN_CAPACITY+1 {
				_ = performance_zone_begin(
					&recorder,
					sequence,
					Performance_Zone_ID(zone_index),
					i64(frame_index+1)*1_000+10,
				)
			}
			for counter_index in 0..<PERFORMANCE_COUNTER_CAPACITY+1 {
				performance_counter_set(
					&recorder,
					sequence,
					Performance_Counter_ID(counter_index),
					i64(counter_index),
				)
			}
		}
		performance_frame_end(&recorder, sequence, i64(frame_index+1)*1_000+500)
	}
	performance_gpu_complete(&recorder, {sequence=first_sequence, completed_ns=99_000})
	frames := performance_recent_frames(&recorder, 10_000_000)
	defer delete(frames)
	testing.expect_value(t, len(frames), PERFORMANCE_FRAME_CAPACITY)
	testing.expect_value(t, frames[0].sequence, u64(3))
	last := frames[len(frames)-1]
	testing.expect(t, last.span_overflow)
	testing.expect(t, last.counter_overflow)
	testing.expect_value(t, last.gpu_completed_ns, i64(0))
}
