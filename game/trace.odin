package game

import "core:fmt"

TRACE_CAP :: 32
TRACE_REASON_LEN :: 96

TraceEntry :: struct {
	day:        int,
	mode:       MissionMode,
	reason_buf: [TRACE_REASON_LEN]u8,
	reason_len: int,
}

trace_reason :: proc(e: ^TraceEntry) -> string {
	return string(e.reason_buf[:e.reason_len])
}

DecisionTrace :: struct {
	entries: [TRACE_CAP]TraceEntry,
	count:   int, // total appended (monotonic)
	head:    int, // next write index
}

decision_trace: DecisionTrace

trace_clear :: proc() {
	decision_trace = {}
}

trace_append :: proc(day: int, mode: MissionMode, fmt_str: string, args: ..any) {
	e: TraceEntry
	e.day = day
	e.mode = mode
	s := fmt.bprintf(e.reason_buf[:], fmt_str, ..args)
	e.reason_len = len(s)

	decision_trace.entries[decision_trace.head] = e
	decision_trace.head = (decision_trace.head + 1) % TRACE_CAP
	decision_trace.count += 1
}

// Returns up to `n` most recent entries (oldest first among the returned set).
trace_recent :: proc(n: int, allocator := context.temp_allocator) -> []TraceEntry {
	available := min(n, min(decision_trace.count, TRACE_CAP))
	if available <= 0 {
		return {}
	}
	out := make([]TraceEntry, available, allocator)
	start := decision_trace.head - available
	for i in 0 ..< available {
		idx := start + i
		for idx < 0 {
			idx += TRACE_CAP
		}
		idx %= TRACE_CAP
		out[i] = decision_trace.entries[idx]
	}
	return out
}

mission_mode_name :: proc(m: MissionMode) -> string {
	switch m {
	case .ToGoal:
		return "ToGoal"
	case .Foraging:
		return "Foraging"
	case .Revealing:
		return "Revealing"
	case .Returning:
		return "Returning"
	}
	return "?"
}
