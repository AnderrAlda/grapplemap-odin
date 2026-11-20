package main

import "core:mem"
import "core:testing"

@(test)
test_frames_label :: proc(t: ^testing.T) {
	testing.expect_value(t, frames_label(7), "grapplemap-odin  frame 7")
}

@(test)
test_parse_args :: proc(t: ^testing.T) {
	s := parse_args({"app", "--headless", "--frames", "5"})
	testing.expect(t, s.headless)
	testing.expect_value(t, s.max_frames, 5)
}

@(test)
test_report_leaks_detects_leak :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	alloc := mem.tracking_allocator(&track)

	ptr, _ := mem.alloc(16, allocator = alloc)
	testing.expect(t, report_leaks(&track), "a live allocation must be reported as a problem")
	mem.free(ptr, alloc)
	testing.expect(t, !report_leaks(&track), "no live allocations: no problem")
}
