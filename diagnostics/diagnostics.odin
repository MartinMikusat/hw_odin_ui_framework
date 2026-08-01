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
