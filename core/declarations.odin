package ui

top_declarations :: proc(frame: ^Frame) -> ^Declarations {
	assert(frame != nil && len(frame.declaration_stack) > 0)
	return &frame.declaration_stack[len(frame.declaration_stack)-1]
}

push_declarations :: proc(frame: ^Frame) {
	append(&frame.declaration_stack, top_declarations(frame)^)
}

pop_declarations :: proc(frame: ^Frame) {
	assert(frame != nil && len(frame.declaration_stack) > 1)
	resize(&frame.declaration_stack, len(frame.declaration_stack)-1)
}

push_layout :: proc(frame: ^Frame, value: Layout) {
	push_declarations(frame)
	top := top_declarations(frame)
	top.layout = value
	top.fields += {.Layout}
}

push_style :: proc(frame: ^Frame, value: Style) {
	push_declarations(frame)
	top := top_declarations(frame)
	top.style = value
	top.fields += {.Style}
}

push_flags :: proc(frame: ^Frame, value: Box_Flags) {
	push_declarations(frame)
	top := top_declarations(frame)
	top.flags += value
	top.fields += {.Flags}
}

push_layer :: proc(frame: ^Frame, value: Layer) {
	push_declarations(frame)
	top := top_declarations(frame)
	top.layer = value
	top.fields += {.Layer}
}

set_next_layout :: proc(frame: ^Frame, value: Layout) {
	frame.next_declarations.layout = value
	frame.next_declarations.fields += {.Layout}
	frame.has_next_declarations = true
}

set_next_style :: proc(frame: ^Frame, value: Style) {
	frame.next_declarations.style = value
	frame.next_declarations.fields += {.Style}
	frame.has_next_declarations = true
}

set_next_flags :: proc(frame: ^Frame, value: Box_Flags) {
	frame.next_declarations.flags = value
	frame.next_declarations.fields += {.Flags}
	frame.has_next_declarations = true
}

set_next_layer :: proc(frame: ^Frame, value: Layer) {
	frame.next_declarations.layer = value
	frame.next_declarations.fields += {.Layer}
	frame.has_next_declarations = true
}

box_from_declarations :: proc(
	frame: ^Frame,
	label: string,
	flags: Box_Flags = {},
) -> Box {
	assert(frame != nil && len(frame.parent_stack) > 0)
	parent := &frame.boxes[frame.parent_stack[len(frame.parent_stack)-1]]
	declarations := top_declarations(frame)^
	if frame.has_next_declarations {
		next := frame.next_declarations
		if .Layout in next.fields {declarations.layout = next.layout}
		if .Style in next.fields {declarations.style = next.style}
		if .Flags in next.fields {declarations.flags += next.flags}
		if .Layer in next.fields {declarations.layer = next.layer}
		frame.next_declarations = {}
		frame.has_next_declarations = false
	}
	return {
		key = key_from_label(parent.key, label),
		debug_label = display_part(label),
		layout = declarations.layout,
		style = declarations.style,
		flags = declarations.flags+flags,
		text = display_part(label),
		layer = declarations.layer,
	}
}

box_add_label :: proc(frame: ^Frame, label: string, flags: Box_Flags = {}) -> int {
	return box_add(frame, box_from_declarations(frame, label, flags))
}

box_begin_label :: proc(frame: ^Frame, label: string, flags: Box_Flags = {}) -> int {
	return box_begin(frame, box_from_declarations(frame, label, flags))
}
