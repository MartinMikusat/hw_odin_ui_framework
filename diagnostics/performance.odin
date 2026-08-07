package diagnostics

import "core:mem"
import "core:sync"
import "core:sys/posix"

PERFORMANCE_FRAME_CAPACITY :: 2048
PERFORMANCE_SPAN_CAPACITY :: 32
PERFORMANCE_COUNTER_CAPACITY :: 32
PERFORMANCE_GPU_COMPLETION_CAPACITY :: 256

Performance_Zone_ID :: distinct u16
Performance_Counter_ID :: distinct u16

Performance_Span :: struct {
	zone:     Performance_Zone_ID,
	start_ns: i64,
	end_ns:   i64,
}

Performance_Counter :: struct {
	id:    Performance_Counter_ID,
	value: i64,
}

Performance_Frame :: struct {
	sequence:         u64,
	started_ns:       i64,
	ended_ns:         i64,
	callback_gap_ns:  i64,
	gpu_scheduled_ns: i64,
	gpu_completed_ns: i64,
	gpu_started_ns:   i64,
	gpu_ended_ns:     i64,
	span_count:       int,
	counter_count:    int,
	span_overflow:    bool,
	counter_overflow: bool,
	spans:             [PERFORMANCE_SPAN_CAPACITY]Performance_Span,
	counters:          [PERFORMANCE_COUNTER_CAPACITY]Performance_Counter,
}

Performance_Zone_Token :: struct {
	sequence: u64,
	index:    int,
}

Performance_GPU_Completion :: struct {
	sequence:       u64,
	scheduled_ns:   i64,
	completed_ns:   i64,
	gpu_started_ns: i64,
	gpu_ended_ns:   i64,
}

Performance_Recorder :: struct {
	allocator:            mem.Allocator,
	frames:               []Performance_Frame,
	next_frame:           int,
	frame_count:          int,
	next_sequence:        u64,
	active_index:         int,
	last_callback_ns:     i64,
	gpu_mutex:            sync.Mutex,
	gpu_completions:      [PERFORMANCE_GPU_COMPLETION_CAPACITY]Performance_GPU_Completion,
	gpu_completion_read:  int,
	gpu_completion_count: int,
}

performance_now_ns :: proc "contextless" () -> i64 {
	timestamp: posix.timespec
	if posix.clock_gettime(posix.Clock(4), &timestamp) != .OK {return 0}
	return i64(timestamp.tv_sec)*1_000_000_000+timestamp.tv_nsec
}

performance_recorder_init :: proc(
	recorder: ^Performance_Recorder,
	allocator := context.allocator,
) -> bool {
	if recorder == nil || len(recorder.frames) > 0 {return false}
	frames, allocation_error := make(
		[]Performance_Frame,
		PERFORMANCE_FRAME_CAPACITY,
		allocator,
	)
	if allocation_error != nil {return false}
	recorder^ = {
		allocator = allocator,
		frames = frames,
		active_index = -1,
		next_sequence = 1,
	}
	return true
}

performance_recorder_destroy :: proc(recorder: ^Performance_Recorder) {
	if recorder == nil {return}
	delete(recorder.frames)
	recorder^ = {}
}

performance_find_frame :: proc(
	recorder: ^Performance_Recorder,
	sequence: u64,
) -> ^Performance_Frame {
	if recorder == nil || sequence == 0 {return nil}
	for offset in 0..<recorder.frame_count {
		index := recorder.next_frame-1-offset
		if index < 0 {index += len(recorder.frames)}
		frame := &recorder.frames[index]
		if frame.sequence == sequence {return frame}
		if frame.sequence < sequence {break}
	}
	return nil
}

performance_gpu_completion_apply :: proc(
	recorder: ^Performance_Recorder,
	completion: Performance_GPU_Completion,
) {
	frame := performance_find_frame(recorder, completion.sequence)
	if frame == nil {return}
	frame.gpu_scheduled_ns = completion.scheduled_ns
	frame.gpu_completed_ns = completion.completed_ns
	frame.gpu_started_ns = completion.gpu_started_ns
	frame.gpu_ended_ns = completion.gpu_ended_ns
}

performance_gpu_completions_drain :: proc(recorder: ^Performance_Recorder) {
	if recorder == nil {return}
	local: [PERFORMANCE_GPU_COMPLETION_CAPACITY]Performance_GPU_Completion
	count := 0
	sync.mutex_lock(&recorder.gpu_mutex)
	for count < recorder.gpu_completion_count {
		local[count] = recorder.gpu_completions[recorder.gpu_completion_read]
		recorder.gpu_completion_read =
			(recorder.gpu_completion_read+1)%PERFORMANCE_GPU_COMPLETION_CAPACITY
		count += 1
	}
	recorder.gpu_completion_count = 0
	sync.mutex_unlock(&recorder.gpu_mutex)
	for completion in local[:count] {
		performance_gpu_completion_apply(recorder, completion)
	}
}

performance_frame_begin :: proc(
	recorder: ^Performance_Recorder,
	now_ns := i64(0),
) -> u64 {
	if recorder == nil || len(recorder.frames) == 0 {return 0}
	at_ns := now_ns
	if at_ns == 0 {at_ns = performance_now_ns()}
	performance_gpu_completions_drain(recorder)
	index := recorder.next_frame
	sequence := recorder.next_sequence
	recorder.next_sequence += 1
	callback_gap := i64(0)
	if recorder.last_callback_ns > 0 {callback_gap = at_ns-recorder.last_callback_ns}
	recorder.last_callback_ns = at_ns
	recorder.frames[index] = {
		sequence = sequence,
		started_ns = at_ns,
		callback_gap_ns = callback_gap,
	}
	recorder.active_index = index
	recorder.next_frame = (index+1)%len(recorder.frames)
	recorder.frame_count = min(recorder.frame_count+1, len(recorder.frames))
	return sequence
}

performance_frame_end :: proc(
	recorder: ^Performance_Recorder,
	sequence: u64,
	now_ns := i64(0),
) {
	at_ns := now_ns
	if at_ns == 0 {at_ns = performance_now_ns()}
	if recorder == nil || recorder.active_index < 0 {return}
	frame := &recorder.frames[recorder.active_index]
	if frame.sequence != sequence {return}
	frame.ended_ns = at_ns
	recorder.active_index = -1
}

performance_zone_begin :: proc(
	recorder: ^Performance_Recorder,
	sequence: u64,
	zone: Performance_Zone_ID,
	now_ns := i64(0),
) -> Performance_Zone_Token {
	at_ns := now_ns
	if at_ns == 0 {at_ns = performance_now_ns()}
	if recorder == nil || recorder.active_index < 0 {return {}}
	frame := &recorder.frames[recorder.active_index]
	if frame.sequence != sequence {return {}}
	if frame.span_count >= len(frame.spans) {
		frame.span_overflow = true
		return {}
	}
	index := frame.span_count
	frame.span_count += 1
	frame.spans[index] = {zone = zone, start_ns = at_ns}
	return {sequence = sequence, index = index}
}

performance_zone_end :: proc(
	recorder: ^Performance_Recorder,
	token: Performance_Zone_Token,
	now_ns := i64(0),
) {
	at_ns := now_ns
	if at_ns == 0 {at_ns = performance_now_ns()}
	if recorder == nil || token.sequence == 0 {return}
	frame := performance_find_frame(recorder, token.sequence)
	if frame == nil || token.index < 0 || token.index >= frame.span_count {return}
	span := &frame.spans[token.index]
	if span.end_ns == 0 {span.end_ns = max(at_ns, span.start_ns)}
}

performance_zone_record :: proc(
	recorder: ^Performance_Recorder,
	sequence: u64,
	zone: Performance_Zone_ID,
	start_ns, end_ns: i64,
) {
	if start_ns <= 0 || end_ns < start_ns {return}
	token := performance_zone_begin(recorder, sequence, zone, start_ns)
	performance_zone_end(recorder, token, end_ns)
}

performance_counter_set :: proc(
	recorder: ^Performance_Recorder,
	sequence: u64,
	id: Performance_Counter_ID,
	value: i64,
) {
	if recorder == nil || recorder.active_index < 0 {return}
	frame := &recorder.frames[recorder.active_index]
	if frame.sequence != sequence {return}
	for &counter in frame.counters[:frame.counter_count] {
		if counter.id == id {
			counter.value = value
			return
		}
	}
	if frame.counter_count >= len(frame.counters) {
		frame.counter_overflow = true
		return
	}
	frame.counters[frame.counter_count] = {id = id, value = value}
	frame.counter_count += 1
}

performance_gpu_complete :: proc(
	recorder: ^Performance_Recorder,
	completion: Performance_GPU_Completion,
) {
	if recorder == nil || completion.sequence == 0 {return}
	sync.mutex_lock(&recorder.gpu_mutex)
	if recorder.gpu_completion_count < PERFORMANCE_GPU_COMPLETION_CAPACITY {
		write := (recorder.gpu_completion_read+recorder.gpu_completion_count)%
		         PERFORMANCE_GPU_COMPLETION_CAPACITY
		recorder.gpu_completions[write] = completion
		recorder.gpu_completion_count += 1
	}
	sync.mutex_unlock(&recorder.gpu_mutex)
}

performance_recent_frames :: proc(
	recorder: ^Performance_Recorder,
	duration_ns: i64,
	allocator := context.allocator,
) -> []Performance_Frame {
	if recorder == nil || recorder.frame_count == 0 || duration_ns <= 0 {return nil}
	performance_gpu_completions_drain(recorder)
	newest_index := recorder.next_frame-1
	if newest_index < 0 {newest_index += len(recorder.frames)}
	newest := recorder.frames[newest_index]
	cutoff := newest.started_ns-duration_ns
	count := 0
	for offset in 0..<recorder.frame_count {
		index := newest_index-offset
		if index < 0 {index += len(recorder.frames)}
		if recorder.frames[index].started_ns < cutoff {break}
		count += 1
	}
	if count == 0 {return nil}
	result, allocation_error := make([]Performance_Frame, count, allocator)
	if allocation_error != nil {return nil}
	start := count-1
	for destination in 0..<count {
		index := newest_index-start+destination
		for index < 0 {index += len(recorder.frames)}
		index %= len(recorder.frames)
		result[destination] = recorder.frames[index]
	}
	return result
}
