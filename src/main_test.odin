package main

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
