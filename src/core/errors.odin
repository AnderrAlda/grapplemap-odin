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

// NO_BLOCK is the `block` of an error not tied to a block. The zero value of `block` is block 0, so every
// constructor sets `block` explicitly (`NO_BLOCK` when none).
NO_BLOCK :: -1

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
	// `line`: 1-based line of the input (0 when unknown); `block`: 0-based block/entry index or NO_BLOCK.
	kind:  Parse_Error_Kind,
	line:  int,
	block: int,
}

// Graph_Error_Kind: rejected while building the graph (docs/original.md §2, `src/graph.cpp:284-285`). May grow.
Graph_Error_Kind :: enum u8 {
	Duplicate_Position_Description,
}

Graph_Error :: struct {
	// `line`: 1-based line of the input (0 when unknown); `block`: 0-based block/entry index or NO_BLOCK.
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
	Empty_Description,
	Duplicate_Description,
	Duplicate_Id,
}

Json_Error :: struct {
	// `line`: 1-based line of the input (0 when unknown); `block`: 0-based block/entry index or NO_BLOCK.
	kind:  Json_Error_Kind,
	line:  int,
	block: int,
}

// Export_Error_Kind: data that cannot be written back (ADR 0005 decisions 5, 8). May grow.
Export_Error_Kind :: enum u8 {
	Description_Starts_With_Space,
	Description_Has_Newline,
	Empty_Description,
	Duplicate_Description,
	Coordinate_Out_Of_Range,
}

Export_Error :: struct {
	// `line`: 1-based line of the input (0 when unknown); `block`: 0-based block/entry index or NO_BLOCK.
	kind:  Export_Error_Kind,
	line:  int,
	block: int,
}
