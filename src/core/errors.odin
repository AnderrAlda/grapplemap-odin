package core

import "core:mem"

// Error is the single error type of `core`; `nil` is success. Propagate it with `or_return`.
//
// Never assign an `mem.Allocator_Error` to an `Error` without checking it: `Allocator_Error.None` is a
// non-nil member of the union, so `err = alloc_err` with `.None` would read as a failure. Use
// `make(...) or_return`, which only returns when the allocator error is not `.None`.
Error :: union {
	Parse_Error,
	Graph_Error,
	Json_Error,
	Export_Error,
	mem.Allocator_Error,
}

// Location of an error: `line` is the 1-based line of the input file (0 when unknown), `block` the 0-based
// index of the position block (or JSON entry) involved (-1 when none).

// Parse_Error_Kind: malformed `GrappleMap.txt` (docs/original.md §1.7, ADR 0005 decision 8). May grow.
Parse_Error_Kind :: enum u8 {
	Bad_Base62_Digit,
	Truncated_Block,
	Missing_Final_Newline,
	Block_Without_Description,
	Bad_Position_Layout,
	Invalid_Utf8,
}

Parse_Error :: struct {
	kind:  Parse_Error_Kind,
	line:  int,
	block: int,
}

// Graph_Error_Kind: rejected while building the graph (docs/original.md §2, `src/graph.cpp:284-285`).
Graph_Error_Kind :: enum u8 {
	Duplicate_Position_Description,
}

Graph_Error :: struct {
	kind:  Graph_Error_Kind,
	line:  int,
	block: int,
}

// Json_Error_Kind: malformed graph JSON (ADR 0005). May grow.
Json_Error_Kind :: enum u8 {
	Syntax,
	Unknown_Key,
	Missing_Key,
	Bad_Schema_Version,
	Coordinate_Out_Of_Range,
	Duplicate_Description,
	Duplicate_Id,
}

Json_Error :: struct {
	kind:  Json_Error_Kind,
	line:  int,
	block: int,
}

// Export_Error_Kind: data that cannot be written back to `GrappleMap.txt` (ADR 0005 decision 8).
Export_Error_Kind :: enum u8 {
	Description_Starts_With_Space,
	Description_Has_Newline,
	Coordinate_Out_Of_Range,
}

Export_Error :: struct {
	kind:  Export_Error_Kind,
	line:  int,
	block: int,
}
