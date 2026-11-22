package core

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
