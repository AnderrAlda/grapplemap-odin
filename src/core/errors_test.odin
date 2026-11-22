package core

import "core:mem"
import "core:testing"

@(private = "file")
no_error :: proc() -> Error {
	return nil
}

@(private = "file")
make_through :: proc(n: int, allocator := context.allocator) -> (s: []int, err: Error) {
	s = make([]int, n, allocator) or_return
	return s, nil
}

@(private = "file")
fail_parse :: proc() -> Error {
	return Parse_Error{kind = .Bad_Base62_Digit, line = 3, block = 0}
}

@(private = "file")
propagate :: proc() -> Error {
	fail_parse() or_return
	return nil
}

@(test)
test_error_nil_is_success :: proc(t: ^testing.T) {
	testing.expect(t, no_error() == nil)
	s, err := make_through(4)
	defer delete(s)
	testing.expect(t, err == nil)
	testing.expect_value(t, len(s), 4)
}

@(test)
test_error_or_return_propagates :: proc(t: ^testing.T) {
	err := propagate()
	pe, ok := err.(Parse_Error)
	testing.expect(t, ok)
	testing.expect_value(t, pe.kind, Parse_Error_Kind.Bad_Base62_Digit)
	testing.expect_value(t, pe.line, 3)
	testing.expect_value(t, pe.block, 0)
}

@(test)
test_error_or_return_allocator_failure :: proc(t: ^testing.T) {
	buf: [64]byte
	arena: mem.Arena
	mem.arena_init(&arena, buf[:])
	s, err := make_through(1000, mem.arena_allocator(&arena))
	testing.expect(t, s == nil)
	ae, ok := err.(mem.Allocator_Error)
	testing.expect(t, ok)
	testing.expect_value(t, ae, mem.Allocator_Error.Out_Of_Memory)
}

@(test)
test_error_allocator_none_is_not_nil :: proc(t: ^testing.T) {
	// The pitfall documented on Error: `.None` stored in the union is not success.
	err: Error = mem.Allocator_Error.None
	testing.expect(t, err != nil)
}
