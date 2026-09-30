package metal

import "core:testing"

Upload_Test :: struct {
	renderer: Renderer,
	queue:    Object,
}

upload_test_init :: proc(t: ^testing.T, value: ^Upload_Test) -> bool {
	if !testing.expect(t, load_objc()) {return false}
	device := MTLCreateSystemDefaultDevice()
	if !testing.expect(t, device != nil, "Metal device required") {return false}
	// The ring needs only the device; no pipelines are created.
	value.renderer.device = device
	value.queue = msg_id(device, sel_registerName("newCommandQueue"))
	return testing.expect(t, value.queue != nil)
}

upload_test_destroy :: proc(value: ^Upload_Test) {
	upload_destroy(&value.renderer)
	release(value.queue)
	release(value.renderer.device)
	value^ = {}
}

// Autoreleased; valid until the test's pool drains, which the runner never does.
upload_test_command_buffer :: proc(value: ^Upload_Test) -> Object {
	return msg_id(value.queue, sel_registerName("commandBuffer"))
}

upload_test_complete :: proc(command_buffer: Object) {
	msg_void(command_buffer, sel_registerName("commit"))
	msg_void(command_buffer, sel_registerName("waitUntilCompleted"))
}

@(test)
upload_reuses_one_slot_across_completed_frames_test :: proc(t: ^testing.T) {
	value: Upload_Test
	if !upload_test_init(t, &value) {return}
	defer upload_test_destroy(&value)

	for frame in 0 ..< 100 {
		command_buffer := upload_test_command_buffer(&value)
		first, first_ok := upload_reserve(&value.renderer, command_buffer, 144)
		second, second_ok := upload_reserve(&value.renderer, command_buffer, 1000)
		testing.expect(t, first_ok)
		testing.expect(t, second_ok)
		// Reservations for one command buffer share a slot at aligned offsets.
		testing.expect(t, first.buffer == second.buffer)
		testing.expect_value(t, first.offset, 0)
		testing.expect_value(t, second.offset, UPLOAD_ALIGNMENT)
		first.bytes[0] = u8(frame)
		second.bytes[999] = u8(frame)
		upload_test_complete(command_buffer)
	}
	stats := upload_stats(&value.renderer)
	testing.expect_value(t, stats.slots, 1)
	testing.expect_value(t, stats.allocations, 1)
	testing.expect_value(t, stats.waits, 0)
}

@(test)
upload_never_shares_a_slot_with_unfinished_work_test :: proc(t: ^testing.T) {
	value: Upload_Test
	if !upload_test_init(t, &value) {return}
	defer upload_test_destroy(&value)
	event := msg_id(value.renderer.device, sel_registerName("newSharedEvent"))
	if !testing.expect(t, event != nil) {return}
	defer release(event)
	defer msg_void_u(event, sel_registerName("setSignaledValue:"), 1)

	first := upload_test_command_buffer(&value)
	first_upload, first_ok := upload_reserve(&value.renderer, first, 64)
	testing.expect(t, first_ok)
	// Keep the first buffer unfinished until the second reservation completes.
	msg_void_id_u(first, sel_registerName("encodeWaitForEvent:value:"), event, 1)
	msg_void(first, sel_registerName("commit"))
	second := upload_test_command_buffer(&value)
	second_upload, second_ok := upload_reserve(&value.renderer, second, 64)
	testing.expect(t, second_ok)
	testing.expect(t, first_upload.buffer != second_upload.buffer)
	msg_void_u(event, sel_registerName("setSignaledValue:"), 1)
	msg_void(first, sel_registerName("waitUntilCompleted"))
	upload_test_complete(second)

	// Both completed: later frames reuse existing slots without allocating.
	allocations := upload_stats(&value.renderer).allocations
	for _ in 0 ..< 10 {
		command_buffer := upload_test_command_buffer(&value)
		_, ok := upload_reserve(&value.renderer, command_buffer, 64)
		testing.expect(t, ok)
		upload_test_complete(command_buffer)
	}
	testing.expect_value(t, upload_stats(&value.renderer).allocations, allocations)
	testing.expect_value(t, upload_stats(&value.renderer).slots, 2)
}

@(test)
upload_grows_a_slot_for_large_frames_test :: proc(t: ^testing.T) {
	value: Upload_Test
	if !upload_test_init(t, &value) {return}
	defer upload_test_destroy(&value)

	small := upload_test_command_buffer(&value)
	_, small_ok := upload_reserve(&value.renderer, small, 64)
	testing.expect(t, small_ok)
	upload_test_complete(small)
	testing.expect_value(t, value.renderer.upload_slots[0].capacity, UPLOAD_SLOT_BYTES_MIN)

	large_bytes := uint(10_000 * size_of(GPU_Quad_Instance))
	large := upload_test_command_buffer(&value)
	upload, large_ok := upload_reserve(&value.renderer, large, large_bytes)
	testing.expect(t, large_ok)
	upload.bytes[large_bytes - 1] = 1
	upload_test_complete(large)
	testing.expect(t, value.renderer.upload_slots[0].capacity >= large_bytes)
	testing.expect_value(t, upload_stats(&value.renderer).slots, 1)
	testing.expect_value(t, upload_stats(&value.renderer).allocations, 2)

	// The grown slot serves later large frames without allocating.
	again := upload_test_command_buffer(&value)
	_, again_ok := upload_reserve(&value.renderer, again, large_bytes)
	testing.expect(t, again_ok)
	upload_test_complete(again)
	testing.expect_value(t, upload_stats(&value.renderer).allocations, 2)
}

@(test)
upload_exhaustion_reclaims_only_discarded_command_buffers_test :: proc(t: ^testing.T) {
	value: Upload_Test
	if !upload_test_init(t, &value) {return}
	defer upload_test_destroy(&value)

	// Fill every slot with discarded (never committed) command buffers.
	for _ in 0 ..< UPLOAD_SLOT_MAX {
		_, ok := upload_reserve(&value.renderer, upload_test_command_buffer(&value), 64)
		testing.expect(t, ok)
	}
	testing.expect_value(t, upload_stats(&value.renderer).slots, UPLOAD_SLOT_MAX)
	next := upload_test_command_buffer(&value)
	_, ok := upload_reserve(&value.renderer, next, 64)
	testing.expect(t, ok)
	testing.expect_value(t, upload_stats(&value.renderer).reclaims, 1)
	upload_test_complete(next)

	// Once committed, slots are reused only after completion, never reclaimed.
	value.renderer.upload_stats.reclaims = 0
	for &slot in value.renderer.upload_slots {
		if msg_u_0(slot.command_buffer, sel_registerName("status")) == MTL_COMMAND_BUFFER_STATUS_NOT_ENQUEUED {
			msg_void(slot.command_buffer, sel_registerName("commit"))
		}
	}
	last := upload_test_command_buffer(&value)
	for _ in 0 ..< UPLOAD_SLOT_MAX {
		_, reserved := upload_reserve(&value.renderer, last, UPLOAD_SLOT_BYTES_MIN)
		testing.expect(t, reserved)
	}
	testing.expect_value(t, upload_stats(&value.renderer).reclaims, 0)
	upload_test_complete(last)
}

@(test)
upload_one_command_buffer_can_exceed_every_slot_test :: proc(t: ^testing.T) {
	value: Upload_Test
	if !upload_test_init(t, &value) {return}
	defer upload_test_destroy(&value)

	command_buffer := upload_test_command_buffer(&value)
	for _ in 0 ..< UPLOAD_SLOT_MAX + 2 {
		upload, ok := upload_reserve(&value.renderer, command_buffer, UPLOAD_SLOT_BYTES_MIN)
		testing.expect(t, ok)
		upload.bytes[0] = 1
	}
	testing.expect_value(t, upload_stats(&value.renderer).slots, UPLOAD_SLOT_MAX)
	testing.expect_value(t, upload_stats(&value.renderer).waits, 0)
	upload_test_complete(command_buffer)
}
