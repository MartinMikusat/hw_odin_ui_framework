package metal

// Persistent upload ring for per-frame draw data. Each slot is one shared
// MTLBuffer owned by at most one command buffer at a time. Encoders write GPU
// records straight into the slot, then bind it at the reserved offset. A slot is
// reused only after its command buffer completes, so the CPU never overwrites
// bytes the GPU may still read. Allocation happens only when a slot must grow or
// when more command buffers are in flight than slots exist.
//
// Contract: commit every command buffer passed to encode, or discard it without
// committing it later. A slot held by an uncommitted command buffer that is not
// the one being encoded is reclaimed only when every slot is in use.

UPLOAD_SLOT_MAX :: 8
UPLOAD_SLOT_BYTES_MIN :: uint(64 * 1024)
// Offsets satisfy every Metal buffer-binding alignment.
UPLOAD_ALIGNMENT :: uint(256)
MTL_RESOURCE_STORAGE_SHARED :: uint(0)
MTL_COMMAND_BUFFER_STATUS_NOT_ENQUEUED :: uint(0)
MTL_COMMAND_BUFFER_STATUS_COMPLETED :: uint(4)

#assert(UPLOAD_SLOT_BYTES_MIN % UPLOAD_ALIGNMENT == 0)

Upload_Slot :: struct {
	buffer:         Object, // Retained shared MTLBuffer.
	capacity:       uint,
	used:           uint,
	command_buffer: Object, // Retained; nil when the slot has never been used.
}

Upload_Stats :: struct {
	slots:       int, // Slots created so far, at most UPLOAD_SLOT_MAX.
	allocations: u64, // MTLBuffer creations, including growth.
	waits:       u64, // Reservations that waited for a command buffer to complete.
	reclaims:    u64, // Slots taken back from uncommitted command buffers.
}

Upload :: struct {
	buffer: Object,
	offset: uint,
	bytes:  [^]u8,
}

upload_align :: proc(size: uint) -> uint {
	return (size + UPLOAD_ALIGNMENT - 1) & ~(UPLOAD_ALIGNMENT - 1)
}

msg_u_0 :: proc(receiver: Object, selector: Selector) -> uint {
	p := cast(proc "c" (_: Object, _: Selector) -> uint)objc_msgSend
	return p(receiver, selector)
}

msg_id_u_u :: proc(receiver: Object, selector: Selector, first, second: uint) -> Object {
	p := cast(proc "c" (_: Object, _: Selector, _: uint, _: uint) -> Object)objc_msgSend
	return p(receiver, selector, first, second)
}

upload_status :: proc(command_buffer: Object) -> uint {
	return msg_u_0(command_buffer, sel_registerName("status"))
}

// Completed or failed: the GPU no longer reads the slot.
upload_slot_is_free :: proc(slot: ^Upload_Slot) -> bool {
	return slot.command_buffer == nil || upload_status(slot.command_buffer) >= MTL_COMMAND_BUFFER_STATUS_COMPLETED
}

// Reserves size bytes readable by the GPU for command_buffer; the returned bytes
// are written before the command buffer is committed.
upload_reserve :: proc(renderer: ^Renderer, command_buffer: Object, size: uint) -> (Upload, bool) {
	assert(renderer != nil)
	assert(command_buffer != nil)
	assert(size > 0)
	aligned := upload_align(size)
	slots := renderer.upload_slots[:renderer.upload_stats.slots]

	// The slot already serving this command buffer, when it has room.
	for &slot in slots {
		if slot.command_buffer == command_buffer && slot.used + aligned <= slot.capacity {
			return upload_take(&slot, aligned), true
		}
	}
	// A completed slot, preferring one that is already large enough.
	chosen := -1
	for &slot, index in slots {
		if slot.command_buffer == command_buffer || !upload_slot_is_free(&slot) {continue}
		if chosen < 0 || (slot.capacity >= aligned && slots[chosen].capacity < aligned) {chosen = index}
	}
	// A new slot while below the bound.
	if chosen < 0 && renderer.upload_stats.slots < UPLOAD_SLOT_MAX {
		chosen = renderer.upload_stats.slots
		renderer.upload_stats.slots += 1
	}
	// Every slot is in flight: backpressure on another command buffer.
	if chosen < 0 {chosen = upload_wait_for_slot(renderer, command_buffer)}
	// Every slot already serves this command buffer: replace slot 0's buffer. The
	// command buffer retains the buffer its encoders bound, so earlier data stays.
	replace := chosen < 0
	if replace {chosen = 0}

	slot := &renderer.upload_slots[chosen]
	if (replace || slot.capacity < aligned) && !upload_slot_grow(renderer, slot, aligned) {
		return {}, false
	}
	if slot.command_buffer != nil {release(slot.command_buffer)}
	slot.command_buffer = msg_id(command_buffer, sel_registerName("retain"))
	slot.used = 0
	return upload_take(slot, aligned), true
}

upload_take :: proc(slot: ^Upload_Slot, aligned: uint) -> Upload {
	assert(slot.used + aligned <= slot.capacity)
	assert(slot.used % UPLOAD_ALIGNMENT == 0)
	offset := slot.used
	slot.used += aligned
	contents := ([^]u8)(msg_id(slot.buffer, sel_registerName("contents")))
	assert(contents != nil)
	return {buffer = slot.buffer, offset = offset, bytes = contents[offset:]}
}

upload_slot_grow :: proc(renderer: ^Renderer, slot: ^Upload_Slot, aligned: uint) -> bool {
	capacity := max(UPLOAD_SLOT_BYTES_MIN, slot.capacity * 2, aligned)
	buffer := msg_id_u_u(
		renderer.device,
		sel_registerName("newBufferWithLength:options:"),
		capacity,
		MTL_RESOURCE_STORAGE_SHARED,
	)
	if buffer == nil {return false}
	// A command buffer that bound the old buffer retains it until it completes.
	if slot.buffer != nil {release(slot.buffer)}
	slot.buffer = buffer
	slot.capacity = capacity
	renderer.upload_stats.allocations += 1
	return true
}

// Returns a slot index once one is safe to reuse, or -1 when every slot serves
// the command buffer being encoded.
upload_wait_for_slot :: proc(renderer: ^Renderer, command_buffer: Object) -> int {
	slots := renderer.upload_slots[:renderer.upload_stats.slots]
	// An uncommitted command buffer other than the current one was discarded
	// under the contract above; the GPU never reads its slot.
	for &slot, index in slots {
		if slot.command_buffer == command_buffer {continue}
		if upload_status(slot.command_buffer) == MTL_COMMAND_BUFFER_STATUS_NOT_ENQUEUED {
			renderer.upload_stats.reclaims += 1
			return index
		}
	}
	for &slot, index in slots {
		if slot.command_buffer == command_buffer {continue}
		msg_void(slot.command_buffer, sel_registerName("waitUntilCompleted"))
		renderer.upload_stats.waits += 1
		return index
	}
	return -1
}

upload_destroy :: proc(renderer: ^Renderer) {
	for &slot in renderer.upload_slots[:renderer.upload_stats.slots] {
		if slot.buffer != nil {release(slot.buffer)}
		if slot.command_buffer != nil {release(slot.command_buffer)}
		slot = {}
	}
	renderer.upload_stats = {}
}

upload_stats :: proc(renderer: ^Renderer) -> Upload_Stats {
	return renderer.upload_stats
}
