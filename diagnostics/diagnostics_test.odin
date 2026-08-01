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
