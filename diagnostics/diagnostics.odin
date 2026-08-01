package diagnostics

import "core:mem"
import "core:strings"
import ui "ui_framework:core"
import draw "ui_framework:draw"

Control :: struct {
	id:              ui.Key,
	functional_name: string,
	action:          ui.Action_ID,
	rect:            draw.Rect,
	capabilities:    ui.Control_Capabilities,
	enabled:         bool,
}

Snapshot :: struct {
	allocator: mem.Allocator,
	frame:     u64,
	controls:  [dynamic]Control,
}

Change_Kind :: enum {
	Added,
	Removed,
	Moved,
	Action_Changed,
	Capabilities_Changed,
	Enabled_Changed,
}

Change :: struct {
	kind:            Change_Kind,
	functional_name: string,
	before:          Control,
	after:           Control,
}

Diff :: struct {
	allocator: mem.Allocator,
	changes:   [dynamic]Change,
}

Box_Record :: struct {
	key:          ui.Key,
	parent:       int,
	label:        string,
	rect:         draw.Rect,
	clipped_rect: draw.Rect,
	desired:      ui.Vec2,
	overflow:     ui.Vec2,
	layer:        ui.Layer,
	flags:        ui.Box_Flags,
}

Frame_Report :: struct {
	allocator:       mem.Allocator,
	frame:           u64,
	boxes:           [dynamic]Box_Record,
	events:          [dynamic]ui.Event,
	signals:         [dynamic]ui.Signal,
	controls:        [dynamic]Control,
	render_trace:    [dynamic]draw.Trace_Entry,
	consumed_events: int,
}

Issue_Kind :: enum {
	Invalid_Parent,
	Empty_Interactive_Rect,
	Invalid_Clip,
	Invalid_Render_Batch,
}

Issue :: struct {
	kind:  Issue_Kind,
	index: int,
	label: string,
}

frame_report_make :: proc(frame: ^ui.Frame, allocator := context.allocator) -> Frame_Report {
	assert(frame != nil)
	result := Frame_Report{allocator = allocator, frame = frame.ui.frame}
	result.boxes = make([dynamic]Box_Record, 0, len(frame.boxes), allocator)
	result.events = make([dynamic]ui.Event, 0, len(frame.events), allocator)
	result.signals = make([dynamic]ui.Signal, 0, len(frame.signals), allocator)
	result.controls = make([dynamic]Control, 0, len(frame.controls), allocator)
	result.render_trace = make([dynamic]draw.Trace_Entry, 0, len(frame.draw_list.trace), allocator)
	for box in frame.boxes {
		append(&result.boxes, Box_Record{
			key = box.key,
			parent = box.parent,
			label = strings.clone(box.debug_label, allocator),
			rect = box.rect,
			clipped_rect = box.clipped_rect,
			desired = box.desired,
			overflow = box.overflow,
			layer = box.layer,
			flags = box.flags,
		})
	}
	for event in frame.events {
		copy := event
		copy.text = strings.clone(event.text, allocator)
		append(&result.events, copy)
		if event.consumed {result.consumed_events += 1}
	}
	for signal in frame.signals {
		copy := signal
		copy.text = strings.clone(signal.text, allocator)
		append(&result.signals, copy)
	}
	for control in frame.controls {
		append(&result.controls, Control{
			id = control.id,
			functional_name = strings.clone(control.functional_name, allocator),
			action = control.action,
			rect = control.rect,
			capabilities = control.capabilities,
			enabled = control.enabled,
		})
	}
	for trace in frame.draw_list.trace {
		copy := trace
		copy.label = strings.clone(trace.label, allocator)
		append(&result.render_trace, copy)
	}
	return result
}

frame_report_destroy :: proc(report: ^Frame_Report) {
	if report == nil {return}
	for &box in report.boxes {delete(box.label, report.allocator)}
	for &event in report.events {delete(event.text, report.allocator)}
	for &signal in report.signals {delete(signal.text, report.allocator)}
	for &control in report.controls {delete(control.functional_name, report.allocator)}
	for &trace in report.render_trace {delete(trace.label, report.allocator)}
	delete(report.boxes)
	delete(report.events)
	delete(report.signals)
	delete(report.controls)
	delete(report.render_trace)
	report^ = {}
}

validate_frame :: proc(frame: ^ui.Frame, allocator := context.allocator) -> []Issue {
	assert(frame != nil)
	issues := make([dynamic]Issue, allocator)
	for box, index in frame.boxes {
		if index > 0 && (box.parent < 0 || box.parent >= index) {
			append(&issues, Issue{.Invalid_Parent, index, box.debug_label})
		}
		if .Interactive in box.flags && draw.rect_is_empty(box.rect) {
			append(&issues, Issue{.Empty_Interactive_Rect, index, box.debug_label})
		}
		if (box.style.clip || .Clip in box.flags) && draw.rect_is_empty(box.clipped_rect) {
			append(&issues, Issue{.Invalid_Clip, index, box.debug_label})
		}
	}
	for trace, index in frame.draw_list.trace {
		if trace.batch_index >= len(frame.draw_list.batches) {
			append(&issues, Issue{.Invalid_Render_Batch, index, trace.label})
		}
	}
	return issues[:]
}

snapshot_make :: proc(
	frame: u64,
	controls: []ui.Control_Record,
	allocator := context.allocator,
) -> Snapshot {
	result := Snapshot{allocator = allocator, frame = frame}
	result.controls = make([dynamic]Control, 0, len(controls), allocator)
	for control in controls {
		append(&result.controls, Control{
			id = control.id,
			functional_name = strings.clone(control.functional_name, allocator),
			action = control.action,
			rect = control.rect,
			capabilities = control.capabilities,
			enabled = control.enabled,
		})
	}
	return result
}

snapshot_destroy :: proc(snapshot: ^Snapshot) {
	if snapshot == nil {return}
	for &control in snapshot.controls {delete(control.functional_name, snapshot.allocator)}
	delete(snapshot.controls)
	snapshot^ = {}
}

find_control :: proc(controls: []Control, name: string) -> ^Control {
	for &control in controls {if control.functional_name == name {return &control}}
	return nil
}

append_change :: proc(diff: ^Diff, kind: Change_Kind, name: string, before, after: Control) {
	append(&diff.changes, Change{
		kind = kind,
		functional_name = strings.clone(name, diff.allocator),
		before = before,
		after = after,
	})
}

diff_make :: proc(
	before, after: Snapshot,
	allocator := context.allocator,
) -> Diff {
	result := Diff{allocator = allocator}
	result.changes = make([dynamic]Change, allocator)
	for control in before.controls {
		next := find_control(after.controls[:], control.functional_name)
		if next == nil {
			append_change(&result, .Removed, control.functional_name, control, {})
			continue
		}
		if control.rect != next.rect {
			append_change(&result, .Moved, control.functional_name, control, next^)
		}
		if control.action != next.action {
			append_change(&result, .Action_Changed, control.functional_name, control, next^)
		}
		if control.capabilities != next.capabilities {
			append_change(&result, .Capabilities_Changed, control.functional_name, control, next^)
		}
		if control.enabled != next.enabled {
			append_change(&result, .Enabled_Changed, control.functional_name, control, next^)
		}
	}
	for control in after.controls {
		if find_control(before.controls[:], control.functional_name) == nil {
			append_change(&result, .Added, control.functional_name, {}, control)
		}
	}
	return result
}

diff_destroy :: proc(diff: ^Diff) {
	if diff == nil {return}
	for &change in diff.changes {delete(change.functional_name, diff.allocator)}
	delete(diff.changes)
	diff^ = {}
}

render_order_matches :: proc(trace: []draw.Trace_Entry, labels: []string) -> bool {
	if len(labels) == 0 {return true}
	next := 0
	for entry in trace {
		if entry.label != labels[next] {continue}
		next += 1
		if next == len(labels) {return true}
	}
	return false
}
